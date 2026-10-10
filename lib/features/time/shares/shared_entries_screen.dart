import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/blocs/paged_cubit.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_share_models.dart';
import '../../../core/repositories/time_repository.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/glass_filter_bar.dart' show kGlassDockRow;
import '../../../core/widgets/glass_switch_chip.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../../core/widgets/soft_card.dart';
import '../../shell/page_chrome.dart';
import '../../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassToast;
import 'accept_share_sheet.dart';
import 'time_shares_cubit.dart';

/// The page behind `/time/shared` (HIN-95): invitations waiting for the
/// reader's answer, and what the reader offered with where each stands.
///
/// Two lists, one switch. The inbox is the reason the page exists, so it opens
/// there unless a link names the other side — the note that somebody accepted
/// points at `sent`.
class SharedEntriesScreen extends StatelessWidget {
  const SharedEntriesScreen({super.key, this.box = TimeShareBox.inbox});

  final TimeShareBox box;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => TimeSharesCubit(context.read<TimeRepository>()),
    child: _SharedEntriesView(initial: box),
  );
}

class _SharedEntriesView extends StatefulWidget {
  const _SharedEntriesView({required this.initial});

  final TimeShareBox initial;

  @override
  State<_SharedEntriesView> createState() => _SharedEntriesViewState();
}

class _SharedEntriesViewState extends State<_SharedEntriesView> {
  late TimeShareBox _box = widget.initial;

  /// One list per side, built when first shown and kept, so switching back
  /// does not read the page again or lose its scroll.
  final Map<TimeShareBox, PagedCubit<TimeEntryShare>> _lists = {};

  /// Invitations with an answer on its way, so a second tap cannot send it.
  final Set<String> _busy = {};

  static const double _dockHeight = kGlassDockRow;

  PagedCubit<TimeEntryShare> _list(TimeShareBox box) =>
      _lists.putIfAbsent(box, () {
        final shares = context.read<TimeSharesCubit>();
        final list = PagedCubit<TimeEntryShare>(
          (page, size) => shares.page(box, page: page, size: size),
          pageSize: 20,
          keyOf: (share) => share.id,
        );
        unawaited(list.load());
        return list;
      });

  @override
  void dispose() {
    for (final list in _lists.values) {
      unawaited(list.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageChrome(
    contentMax: Breakpoints.readingWidth,
    title: context.t('time.share.pageTitle'),
    bottom: _switcher(),
    bottomHeight: _dockHeight,
    child: _ShareList(
      key: ValueKey(_box),
      box: _box,
      list: _list(_box),
      busy: _busy,
      onAccept: _accept,
      onAdjust: _adjust,
      onDecline: _decline,
      onRevoke: _revoke,
    ),
  );

  // The page's gutter on a phone only. A wide window lays the docked band out
  // in the page's column already, and a second gutter there set the switch in
  // from the cards; a phone's band runs edge to edge, as the time list's does.
  Widget _switcher() => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: context.isCompact ? context.pageGutter : 0,
    ),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: LayoutBuilder(
        builder: (context, constraints) => GlassSwitchBar(
          maxWidth: constraints.maxWidth,
          chips: [
            for (final box in TimeShareBox.values)
              GlassSwitchChip(
                label: context.t('time.share.box.${box.name}'),
                icon: box == TimeShareBox.inbox
                    ? LucideIcons.inbox
                    : LucideIcons.send,
                active: box == _box,
                onTap: () => setState(() => _box = box),
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _run(
    TimeEntryShare share,
    Future<void> Function() action, {
    required String doneKey,
  }) async {
    if (_busy.contains(share.id)) return;
    setState(() => _busy.add(share.id));
    try {
      await action();
      if (!mounted) return;
      showGlassToast(context, context.t(doneKey), kind: GlassToastKind.success);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      showGlassToast(
        context,
        context.t(failure.message),
        kind: GlassToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _busy.remove(share.id));
    }
  }

  Future<void> _accept(TimeEntryShare share) => _run(share, () async {
    await context.read<TimeSharesCubit>().accept(share.id);
    _list(TimeShareBox.inbox).removeItem(share.id);
  }, doneKey: 'time.share.accepted');

  Future<void> _adjust(TimeEntryShare share) async {
    final accepted = await showAcceptShareSheet(
      context,
      share: share,
      shares: context.read<TimeSharesCubit>(),
    );
    if (accepted != true || !mounted) return;
    _list(TimeShareBox.inbox).removeItem(share.id);
    showGlassToast(
      context,
      context.t('time.share.accepted'),
      kind: GlassToastKind.success,
    );
  }

  Future<void> _decline(TimeEntryShare share) => _run(share, () async {
    await context.read<TimeSharesCubit>().decline(share.id);
    _list(TimeShareBox.inbox).removeItem(share.id);
  }, doneKey: 'time.share.declined');

  Future<void> _revoke(TimeEntryShare share) => _run(share, () async {
    final entryId = share.entryId;
    if (entryId == null) return;
    await context.read<TimeSharesCubit>().revoke(entryId, share.to.id);
    // Read back rather than patched: the server says when it was taken back.
    await _list(TimeShareBox.sent).load();
  }, doneKey: 'time.share.revoked');
}

class _ShareList extends StatelessWidget {
  const _ShareList({
    super.key,
    required this.box,
    required this.list,
    required this.busy,
    required this.onAccept,
    required this.onAdjust,
    required this.onDecline,
    required this.onRevoke,
  });

  final TimeShareBox box;
  final PagedCubit<TimeEntryShare> list;
  final Set<String> busy;
  final void Function(TimeEntryShare) onAccept;
  final void Function(TimeEntryShare) onAdjust;
  final void Function(TimeEntryShare) onDecline;
  final void Function(TimeEntryShare) onRevoke;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.fromLTRB(
      context.pageGutter,
      context.topGutter + 12,
      context.pageGutter,
      context.bottomGutter + 24,
    );
    return BlocBuilder<PagedCubit<TimeEntryShare>, PagedState<TimeEntryShare>>(
      bloc: list,
      builder: (context, state) {
        if (state.isLoading && state.items.isEmpty) {
          return Padding(
            padding: padding,
            child: const Align(
              alignment: Alignment.topCenter,
              child: HiveLoader(size: 30),
            ),
          );
        }
        if (state.errorKey != null && state.items.isEmpty) {
          return Padding(
            padding: padding,
            child: Align(
              alignment: Alignment.topCenter,
              child: HiveEmptyState(
                title: context.t('time.share.pageTitle'),
                message: context.t(state.errorKey!),
                action: GhostButton(
                  icon: LucideIcons.refreshCw,
                  label: context.t('common.retry'),
                  onPressed: () => unawaited(list.load()),
                ),
              ),
            ),
          );
        }
        if (state.items.isEmpty) {
          return Padding(
            padding: padding,
            child: Align(
              alignment: Alignment.topCenter,
              child: HiveEmptyState(
                title: context.t('time.share.empty.${box.name}.title'),
                message: context.t('time.share.empty.${box.name}.message'),
              ),
            ),
          );
        }
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification &&
                state.hasMore &&
                notification.metrics.pixels >=
                    notification.metrics.maxScrollExtent - 400) {
              unawaited(list.loadMore());
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: list.load,
            child: ListView.separated(
              padding: padding,
              itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index >= state.items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: HiveLoader(size: 26)),
                  );
                }
                final share = state.items[index];
                return SharedEntryCard(
                  share: share,
                  incoming: box == TimeShareBox.inbox,
                  busy: busy.contains(share.id),
                  onAccept: () => onAccept(share),
                  onAdjust: () => onAdjust(share),
                  onDecline: () => onDecline(share),
                  onRevoke: () => onRevoke(share),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// One invitation: who and when, the entry as it was offered, and what the
/// reader can do about it.
class SharedEntryCard extends StatelessWidget {
  const SharedEntryCard({
    super.key,
    required this.share,
    required this.incoming,
    this.busy = false,
    this.onAccept,
    this.onAdjust,
    this.onDecline,
    this.onRevoke,
  });

  final TimeEntryShare share;

  /// The reader is the recipient; otherwise the sender.
  final bool incoming;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onAdjust;
  final VoidCallback? onDecline;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final other = incoming ? share.from : share.to;
    final name = other.name ?? context.t('time.deletedUser');
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                incoming ? LucideIcons.inbox : LucideIcons.send,
                size: 16,
                color: AppColors.inkSoft,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.t(
                    incoming ? 'time.share.from' : 'time.share.to',
                    variables: {'name': name},
                  ),
                  style: TextStyle(
                    fontSize: AppType.label,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (!incoming) ShareStatusLabel(status: share.status),
            ],
          ),
          const SizedBox(height: 8),
          SharedEntrySummary(share: share),
          if (incoming || share.isPending) ...[
            const SizedBox(height: 12),
            _actions(context),
          ],
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    if (!incoming) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: GhostButton(
          icon: LucideIcons.undo2,
          label: context.t('time.share.revoke'),
          onPressed: busy ? null : onRevoke,
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        GhostButton(
          icon: LucideIcons.x,
          label: context.t('time.share.decline'),
          onPressed: busy ? null : onDecline,
        ),
        GhostButton(
          icon: LucideIcons.slidersHorizontal,
          label: context.t('time.share.adjust'),
          onPressed: busy ? null : onAdjust,
        ),
        FilledButton.icon(
          onPressed: busy ? null : onAccept,
          icon: busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.check, size: 16),
          label: Text(context.t('time.share.accept')),
        ),
      ],
    );
  }
}

/// The entry as it was offered: day and hours, where it sits, what it says.
class SharedEntrySummary extends StatelessWidget {
  const SharedEntrySummary({super.key, required this.share});

  final TimeEntryShare share;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final localizations = MaterialLocalizations.of(context);
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    String clock(DateTime moment) => localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(moment.toLocal()),
      alwaysUse24HourFormat: use24,
    );
    final start = share.startedAt;
    final end = share.endedAt;
    final when = [
      if (share.date != null) DateFormat.yMMMEd(locale).format(share.date!),
      if (start != null && end != null) '${clock(start)} – ${clock(end)}',
      fmtDuration(context, share.durationMinutes),
    ].join(' · ');
    final where = [
      share.projectName ?? context.t('time.share.projectHidden'),
      if (share.issueKey != null)
        share.issueTitle == null
            ? share.issueKey!
            : '${share.issueKey} ${share.issueTitle}',
    ].join(' · ');
    final description = share.description?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          description.isEmpty
              ? context.t('time.share.noDescription')
              : description,
          style: TextStyle(
            fontSize: AppType.body,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: description.isEmpty ? AppColors.inkFaint : AppColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          when,
          style: TextStyle(
            fontSize: AppType.label,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          where,
          style: TextStyle(
            fontSize: AppType.label,
            color: AppColors.textSecondary,
          ),
        ),
        if (share.tags.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            share.tags.map((tag) => '#$tag').join(' '),
            style: TextStyle(
              fontSize: AppType.caption,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ],
    );
  }
}

/// Where an invitation stands, in words with a glyph — never colour alone.
class ShareStatusLabel extends StatelessWidget {
  const ShareStatusLabel({super.key, required this.status});

  final TimeShareStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      TimeShareStatus.pending => (LucideIcons.hourglass, AppColors.accentInk),
      TimeShareStatus.accepted => (
        LucideIcons.circleCheck,
        AppColors.successInk,
      ),
      TimeShareStatus.declined => (LucideIcons.circleSlash, AppColors.inkSoft),
      TimeShareStatus.revoked => (LucideIcons.undo2, AppColors.inkSoft),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          context.t(status.labelKey),
          style: TextStyle(
            fontSize: AppType.caption,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
