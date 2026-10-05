import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/time_policy_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_models.dart';
import '../../core/repositories/time_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../sprint/modals/glass_modal.dart';
import 'account_widgets.dart';
import 'calendar_subscription_dialog.dart';
import 'calendar_subscriptions_cubit.dart';

/// Settings → Time tracking → Calendar subscriptions (HIN-94).
///
/// A person hands over the private address of one of their own calendars, and
/// its events appear in the time calendar as suggestions to take over. Only
/// shown where the organisation allows it (`icsImportEnabled`); everything
/// here is the reader's own and nobody else ever sees it.
///
/// One row per calendar, read like a connection: its colour and name, where it
/// comes from, and how the last read went. What can be done with a row is one
/// tap away in its menu, so the list stays a list.
class CalendarSubscriptionsSection extends StatelessWidget {
  const CalendarSubscriptionsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final enabled = context.select(
      (TimePolicyCubit cubit) => cubit.state.icsImportEnabled,
    );
    if (!enabled) return const SizedBox.shrink();
    return BlocProvider(
      create: (context) =>
          CalendarSubscriptionsCubit(context.read<TimeRepository>())..load(),
      child: const CalendarSubscriptionsView(),
    );
  }
}

/// [CalendarSubscriptionsSection] with the gap above it, both only where the
/// section is shown, so a column of sections never ends on an empty space.
class CalendarSubscriptionsSlot extends StatefulWidget {
  const CalendarSubscriptionsSlot({super.key});

  @override
  State<CalendarSubscriptionsSlot> createState() =>
      _CalendarSubscriptionsSlotState();
}

class _CalendarSubscriptionsSlotState extends State<CalendarSubscriptionsSlot> {
  @override
  void initState() {
    super.initState();
    // Opened straight from a link, nothing may have read the policy yet.
    unawaited(context.read<TimePolicyCubit>().ensureLoaded());
  }

  @override
  Widget build(BuildContext context) {
    final enabled = context.select(
      (TimePolicyCubit cubit) => cubit.state.icsImportEnabled,
    );
    if (!enabled) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(top: 16),
      child: CalendarSubscriptionsSection(),
    );
  }
}

/// The section's body, for a cubit provided from outside (and in tests).
class CalendarSubscriptionsView extends StatelessWidget {
  const CalendarSubscriptionsView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CalendarSubscriptionsCubit>().state;
    return AccountSection(
      icon: LucideIcons.calendarSync,
      title: context.t('calendarSubscriptions.title'),
      subtitle: context.t('calendarSubscriptions.subtitle'),
      trailing: AccountActionButton(
        label: context.t('calendarSubscriptions.add'),
        icon: LucideIcons.plus,
        onPressed: state.loading || state.atLimit
            ? null
            : () => unawaited(_add(context)),
      ),
      children: [
        if (state.loading && state.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: HiveLoader(size: 32)),
          )
        else if (state.errorKey != null && state.items.isEmpty)
          HiveEmptyState(
            title: context.t(state.errorKey!),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
            action: OutlinedButton(
              onPressed: () =>
                  unawaited(context.read<CalendarSubscriptionsCubit>().load()),
              child: Text(context.t('common.retry')),
            ),
          )
        else if (state.items.isEmpty)
          HiveEmptyState(
            title: context.t('calendarSubscriptions.empty.title'),
            message: context.t('calendarSubscriptions.empty.message'),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          )
        else
          for (var i = 0; i < state.items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.hairline2),
            _SubscriptionRow(
              subscription: state.items[i],
              busy: state.busy.contains(state.items[i].id),
            ),
          ],
        if (state.atLimit)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AccountNote(
              text: context.t(
                'calendarSubscriptions.limit',
                variables: {'count': '${CalendarSubscriptionsCubit.limit}'},
              ),
              tone: AccountNoteTone.info,
            ),
          ),
      ],
    );
  }

  static Future<void> _add(BuildContext context) async {
    final cubit = context.read<CalendarSubscriptionsCubit>();
    final saved = await showCalendarSubscriptionDialog(
      context,
      onSave: cubit.create,
    );
    if (saved == null || !context.mounted) return;
    showGlassToast(
      context,
      context.t('calendarSubscriptions.added'),
      kind: GlassToastKind.success,
    );
  }
}

/// What a row's menu can do. [none] is the menu's value, so no row is ticked.
enum _RowAction { none, refresh, edit, toggle, delete }

class _SubscriptionRow extends StatelessWidget {
  const _SubscriptionRow({required this.subscription, required this.busy});

  final CalendarSubscription subscription;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final status = _statusLine(context, subscription);
    final skips = subscription.skips;
    return Opacity(
      opacity: subscription.enabled ? 1 : 0.6,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _Swatch(color: subscription.swatch),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subscription.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  if (subscription.hostMasked != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subscription.hostMasked!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.caption,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  // Announced when it changes: a read finishes while the
                  // reader is looking somewhere else.
                  Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        if (busy ||
                            subscription.status ==
                                CalendarSubscriptionStatus.running)
                          const Padding(
                            padding: EdgeInsetsDirectional.only(end: 6),
                            child: HiveLoader(size: 14),
                          )
                        else
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: Icon(
                              status.icon,
                              size: 14,
                              color: status.color,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            status.text,
                            style: TextStyle(
                              fontSize: AppType.caption,
                              color: status.problem
                                  ? status.color
                                  : AppColors.inkSoft,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (subscription.rule.enabled) ...[
                    const SizedBox(height: 4),
                    Text(
                      context.t('calendarSubscriptions.ruleOn'),
                      style: TextStyle(
                        fontSize: AppType.caption,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                  if (skips.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      context.t(
                        'calendarSubscriptions.skipped',
                        count: skips.length,
                        variables: {
                          'count': '${skips.length}',
                          'reason':
                              skips.first.message ??
                              context.t('calendarSubscriptions.status.failed'),
                        },
                      ),
                      style: TextStyle(
                        fontSize: AppType.caption,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _RowMenu(subscription: subscription, busy: busy),
          ],
        ),
      ),
    );
  }

  static ({String text, IconData icon, Color color, bool problem}) _statusLine(
    BuildContext context,
    CalendarSubscription subscription,
  ) {
    String when(DateTime at) {
      final localizations = MaterialLocalizations.of(context);
      return '${localizations.formatMediumDate(at)}, '
          '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(at), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
    }

    // The server says it in the reader's language; the app's own sentence
    // stands in for a failure it did not name.
    String error() =>
        subscription.lastErrorMessage ??
        context.t('calendarSubscriptions.status.failed');
    if (!subscription.enabled) {
      return (
        text: context.t('calendarSubscriptions.status.off'),
        icon: LucideIcons.pause,
        color: AppColors.inkSoft,
        problem: false,
      );
    }
    return switch (subscription.status) {
      CalendarSubscriptionStatus.pending => (
        text: context.t('calendarSubscriptions.status.pending'),
        icon: LucideIcons.clock,
        color: AppColors.inkSoft,
        problem: false,
      ),
      CalendarSubscriptionStatus.running => (
        text: context.t('calendarSubscriptions.status.running'),
        icon: LucideIcons.refreshCw,
        color: AppColors.inkSoft,
        problem: false,
      ),
      CalendarSubscriptionStatus.ok => (
        text: context.t(
          'calendarSubscriptions.status.ok',
          count: subscription.eventCount,
          variables: {
            'count': '${subscription.eventCount}',
            'when': subscription.lastFetchedAt == null
                ? ''
                : when(subscription.lastFetchedAt!),
          },
        ),
        icon: LucideIcons.circleCheck,
        color: AppColors.successInk,
        problem: false,
      ),
      CalendarSubscriptionStatus.truncated => (
        text: error(),
        icon: LucideIcons.triangleAlert,
        color: AppColors.ink,
        problem: true,
      ),
      CalendarSubscriptionStatus.failed => (
        text: error(),
        icon: LucideIcons.circleAlert,
        color: AppColors.dangerInk,
        problem: true,
      ),
      CalendarSubscriptionStatus.paused => (
        text: '${context.t('calendarSubscriptions.status.paused')} ${error()}',
        icon: LucideIcons.circlePause,
        color: AppColors.dangerInk,
        problem: true,
      ),
    };
  }
}

/// The calendar's colour: a dot, with its name beside it doing the telling.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

class _RowMenu extends StatefulWidget {
  const _RowMenu({required this.subscription, required this.busy});

  final CalendarSubscription subscription;
  final bool busy;

  @override
  State<_RowMenu> createState() => _RowMenuState();
}

class _RowMenuState extends State<_RowMenu> {
  final _anchor = GlobalKey();

  Future<void> _open() async {
    final subscription = widget.subscription;
    final anchor = anchorRectOf(_anchor);
    if (anchor == null) return;
    final chosen = await showGlassMenu<_RowAction>(
      context: context,
      anchorRect: anchor,
      width: 240,
      value: _RowAction.none,
      items: [
        GlassMenuItem(
          value: _RowAction.refresh,
          label: context.t('calendarSubscriptions.refresh'),
          leading: Icon(
            LucideIcons.refreshCw,
            size: 16,
            color: AppColors.inkSoft,
          ),
          enabled: subscription.enabled,
        ),
        GlassMenuItem(
          value: _RowAction.edit,
          label: context.t('common.edit'),
          leading: Icon(LucideIcons.pencil, size: 16, color: AppColors.inkSoft),
        ),
        GlassMenuItem(
          value: _RowAction.toggle,
          label: context.t(
            subscription.enabled
                ? 'calendarSubscriptions.pause'
                : 'calendarSubscriptions.resume',
          ),
          leading: Icon(
            subscription.enabled ? LucideIcons.pause : LucideIcons.play,
            size: 16,
            color: AppColors.inkSoft,
          ),
        ),
        GlassMenuItem(
          value: _RowAction.delete,
          label: context.t('common.delete'),
          color: AppColors.danger,
          leading: const Icon(
            LucideIcons.trash2,
            size: 16,
            color: AppColors.danger,
          ),
          dividerAbove: true,
        ),
      ],
    );
    if (chosen == null || !mounted) return;
    final cubit = context.read<CalendarSubscriptionsCubit>();
    switch (chosen) {
      case _RowAction.none:
        return;
      case _RowAction.refresh:
        await _run(() => cubit.refresh(subscription.id));
      case _RowAction.edit:
        await showCalendarSubscriptionDialog(
          context,
          subscription: subscription,
          onSave: (draft) => cubit.update(subscription.id, draft),
        );
      case _RowAction.toggle:
        await _run(
          () =>
              cubit.setEnabled(subscription.id, enabled: !subscription.enabled),
        );
      case _RowAction.delete:
        await _delete(cubit);
    }
  }

  Future<void> _delete(CalendarSubscriptionsCubit cubit) async {
    final subscription = widget.subscription;
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('calendarSubscriptions.delete.title'),
      message: context.t(
        'calendarSubscriptions.delete.message',
        variables: {'name': subscription.name},
      ),
      confirmLabel: context.t('common.delete'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    final done = context.t('calendarSubscriptions.deleted');
    final ok = await _run(() => cubit.delete(subscription.id));
    if (ok && mounted) showGlassToast(context, done);
  }

  /// Runs a write and toasts its refusal; answers whether it went through.
  Future<bool> _run(Future<void> Function() call) async {
    try {
      await call();
      return true;
    } on ApiFailure catch (failure) {
      if (mounted) showGlassErrorToast(context, context.t(failure.message));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: _anchor,
    tooltip: context.t(
      'calendarSubscriptions.actions',
      variables: {'name': widget.subscription.name},
    ),
    onPressed: widget.busy ? null : () => unawaited(_open()),
    icon: Icon(LucideIcons.ellipsis, size: 18, color: AppColors.inkSoft),
  );
}
