import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_privacy_models.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/time_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../sprint/modals/glass_modal.dart' show GlassToastKind, showGlassToast;
import 'lock_notice.dart';

/// The requests the reader can answer, newest first (Art. 16 DSGVO): frozen
/// entries to correct, and older days to open.
///
/// An administrator sees every request, a lead the ones about submitted periods
/// of the projects they lead; the server decides, this only lists. An answer
/// changes nothing by itself. What does is a separate act: a reopen for a
/// submitted period, or opening the days for the person who asked, which an
/// administrator does from here and which closes again by itself.
///
/// Two homes. As its own tab in Approvals it is a page with its own scroll; in
/// the admin area it sits inside a card and pages with a button, because a
/// scroll inside a scroll is a scroll nobody finds the end of.
class CorrectionRequestsList extends StatefulWidget {
  const CorrectionRequestsList({
    super.key,
    this.embedded = false,
    this.padding = EdgeInsets.zero,
  });

  /// Inside a card: no scroll of its own, a short empty line, a "load more".
  final bool embedded;

  /// Around the list when it is a page.
  final EdgeInsets padding;

  @override
  State<CorrectionRequestsList> createState() => _CorrectionRequestsListState();
}

class _CorrectionRequestsListState extends State<CorrectionRequestsList> {
  late final PagedCubit<TimeCorrectionRequest> _requests =
      PagedCubit<TimeCorrectionRequest>(
        (page, size) => context.read<TimeRepository>().correctionRequests(
          page: page,
          size: size,
        ),
        pageSize: 25,
        keyOf: (request) => request.id,
      );

  /// Requests with an answer on its way, so a second tap cannot send it twice.
  final Set<String> _sending = {};

  /// Project keys by id, for the line under each request.
  Map<String, String> _projects = const {};

  /// Every project id already asked about, answered or not. A project deleted
  /// since the request was made never resolves, and asking again on every page
  /// would only spend the request budget the rest of the app shares.
  final Set<String> _askedProjects = {};

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    unawaited(_requests.close());
    super.dispose();
  }

  Future<void> _reload() async {
    await _requests.load();
    if (mounted) unawaited(_resolveProjects());
  }

  Future<void> _loadMore() async {
    final before = _requests.state.items.length;
    await _requests.loadMore();
    // Called on every scroll near the end, and a page already on its way makes
    // it return at once: only a list that grew has projects to name.
    if (mounted && _requests.state.items.length != before) {
      unawaited(_resolveProjects());
    }
  }

  Future<void> _resolveProjects() async {
    final ids = {
      for (final request in _requests.state.items)
        if (request.projectId != null) request.projectId!,
    }..removeWhere(_askedProjects.contains);
    if (ids.isEmpty) return;
    _askedProjects.addAll(ids);
    try {
      final resolved = await context.read<ProjectRepository>().resolveProjects(
        ids.toList(),
      );
      if (!mounted) return;
      setState(
        () => _projects = {
          ..._projects,
          for (final project in resolved) project.id: project.key,
        },
      );
    } on ApiFailure {
      // The request still reads without the key: who asked, which day, why.
      // Asked again with the next page, since the connection may be back.
      _askedProjects.removeAll(ids);
    }
  }

  /// Answers [request] with a sentence, or opens the days for the person who
  /// asked when [grant] is set. The person reads the sentence as the answer.
  ///
  /// Opening needs no sentence: the request already says why, and the audit
  /// keeps who opened which days. An answer without opening is nothing but its
  /// sentence, so there it stays required.
  Future<void> _respond(
    TimeCorrectionRequest request, {
    required bool grant,
  }) async {
    if (_sending.contains(request.id)) return;
    final repository = context.read<TimeRepository>();
    final note = await showGlassNoteDialog(
      context,
      titleKey: grant
          ? 'time.correction.grantTitle'
          : 'time.correction.answerTitle',
      hintKey: grant
          ? 'time.correction.grantHint'
          : 'time.correction.answerHint',
      confirmKey: grant
          ? 'time.correction.grantSend'
          : 'time.correction.answerSend',
      required: !grant,
    );
    if (note == null || !mounted) return;
    setState(() => _sending.add(request.id));
    try {
      final answered = grant
          ? await repository.grantCorrection(request.id, note)
          : await repository.answerCorrection(request.id, note);
      if (!mounted) return;
      // In place rather than reloaded: the list keeps its scroll position, and
      // the answer appears where the buttons were.
      _requests.replaceItem(answered);
      showGlassToast(
        context,
        context.t(
          grant ? 'time.correction.granted' : 'time.correction.answered',
        ),
        kind: GlassToastKind.success,
      );
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      showGlassToast(
        context,
        context.t(failure.message),
        kind: GlassToastKind.error,
      );
      // Somebody else may have answered in the meantime; show what stands now.
      unawaited(_reload());
    } finally {
      if (mounted) setState(() => _sending.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<
      PagedCubit<TimeCorrectionRequest>,
      PagedState<TimeCorrectionRequest>
    >(
      bloc: _requests,
      builder: (context, state) {
        // A page keeps its own padding in every state, so the first line does
        // not jump sideways when the list arrives.
        final framing = widget.embedded ? EdgeInsets.zero : widget.padding;
        if (state.isLoading && state.items.isEmpty) {
          return Padding(
            padding: framing.add(const EdgeInsets.symmetric(vertical: 24)),
            // Aligned, not bare: as a page the list sits in an IndexedStack that
            // hands it tight constraints, and a bare loader grew to the size of
            // the whole page while the first requests were on their way.
            child: const Align(
              alignment: Alignment.topCenter,
              child: HiveLoader(size: 30),
            ),
          );
        }
        if (state.errorKey != null && state.items.isEmpty) {
          return Padding(
            padding: framing.add(const EdgeInsets.symmetric(vertical: 12)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.t(state.errorKey!),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                GhostButton(
                  icon: LucideIcons.refreshCw,
                  label: context.t('common.retry'),
                  onPressed: () => unawaited(_reload()),
                ),
              ],
            ),
          );
        }
        if (state.items.isEmpty) {
          return widget.embedded
              ? Text(
                  context.t('time.correction.empty'),
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                )
              : Padding(
                  padding: widget.padding,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: HiveEmptyState(
                        title: context.t('time.correction.emptyTitle'),
                        message: context.t('time.correction.emptyMessage'),
                      ),
                    ),
                  ),
                );
        }
        final cards = [
          for (final request in state.items)
            _CorrectionCard(
              request: request,
              projectKey: _projects[request.projectId],
              sending: _sending.contains(request.id),
              onAnswer: () => _respond(request, grant: false),
              onGrant: () => _respond(request, grant: true),
            ),
        ];
        if (widget.embedded) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in cards) ...[card, const SizedBox(height: 10)],
              if (state.hasMore)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: state.isLoadingMore
                      ? const HiveLoader(size: 24)
                      : GhostButton(
                          icon: LucideIcons.chevronsDown,
                          label: context.t('time.correction.more'),
                          onPressed: () => unawaited(_loadMore()),
                        ),
                ),
            ],
          );
        }
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification &&
                state.hasMore &&
                notification.metrics.pixels >=
                    notification.metrics.maxScrollExtent - 400) {
              unawaited(_loadMore());
            }
            return false;
          },
          child: ListView.separated(
            padding: widget.padding,
            itemCount: cards.length + (state.isLoadingMore ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => index < cards.length
                ? cards[index]
                : const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: HiveLoader(size: 26)),
                  ),
          ),
        );
      },
    );
  }
}

class _CorrectionCard extends StatelessWidget {
  const _CorrectionCard({
    required this.request,
    required this.projectKey,
    required this.sending,
    required this.onAnswer,
    required this.onGrant,
  });

  final TimeCorrectionRequest request;
  final String? projectKey;

  /// An answer to this request is on its way.
  final bool sending;
  final VoidCallback onAnswer;
  final VoidCallback onGrant;

  /// The reasons this build has words for.
  static const _reasons = {'LOCK_DATE', 'APPROVAL', 'MAX_DAYS_BACK'};

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final day = request.date;
    final from = request.from;
    final to = request.to;
    final at = request.at;
    final answer = request.answer;
    final details = [
      if (request.isSpan && from != null && to != null)
        formatPeriod(context, from, to)
      else if (day != null)
        DateFormat.yMMMd(locale).format(day),
      ?projectKey,
      if (_reasons.contains(request.reason))
        context.t('time.correction.reason.${request.reason}'),
    ];
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                request.isSpan
                    ? LucideIcons.calendarPlus
                    : LucideIcons.messageSquareWarning,
                size: 16,
                color: AppColors.inkSoft,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  request.requesterLabel ?? context.t('time.deletedUser'),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (at != null)
                Text(
                  DateFormat.yMMMd(locale).add_Hm().format(at.toLocal()),
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              details.join(' · '),
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
          if (request.note != null) ...[
            const SizedBox(height: 8),
            Text(
              request.note!,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.ink,
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (answer != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                border: Border.all(color: AppColors.hairline2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t(
                      answer.granted
                          ? 'time.correction.grantedBy'
                          : 'time.correction.answeredBy',
                      variables: {
                        'name': answer.byLabel ?? context.t('time.deletedUser'),
                      },
                    ),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (answer.note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      answer.note!,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ],
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                GhostButton(
                  icon: LucideIcons.reply,
                  label: context.t('time.correction.answer'),
                  onPressed: sending ? null : onAnswer,
                ),
                if (request.grantable)
                  GhostButton(
                    icon: LucideIcons.calendarCheck,
                    label: context.t('time.correction.grant'),
                    onPressed: sending ? null : onGrant,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The reader's own requests about one entry, and the answer to the newest.
///
/// Under the lock in the entry's sheet, because that is where somebody who asked
/// comes back to look. Loaded when the sheet shows a lock and only then, and
/// silent when there is nothing to show: the notice above still says what to do.
class OwnCorrectionRequests extends StatefulWidget {
  const OwnCorrectionRequests({super.key, required this.entryId});

  final String entryId;

  @override
  State<OwnCorrectionRequests> createState() => _OwnCorrectionRequestsState();
}

class _OwnCorrectionRequestsState extends State<OwnCorrectionRequests> {
  TimeCorrectionRequest? _latest;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final found = await context
          .read<TimeRepository>()
          .entryCorrectionRequests(widget.entryId);
      if (mounted && found.isNotEmpty) setState(() => _latest = found.first);
    } catch (_) {
      // Nothing to show reads the same as nothing asked, and the lock notice
      // above still names the way out.
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _latest;
    if (request == null) return const SizedBox.shrink();
    final answer = request.answer;
    final label = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    );
    final body = TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.ink);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.t('time.correction.yourRequest'), style: label),
            if (request.note != null) ...[
              const SizedBox(height: 2),
              Text(request.note!, style: body),
            ],
            const SizedBox(height: 8),
            Text(
              answer == null
                  ? context.t('time.correction.waiting')
                  : context.t(
                      answer.granted
                          ? 'time.correction.grantedBy'
                          : 'time.correction.answeredBy',
                      variables: {
                        'name': answer.byLabel ?? context.t('time.deletedUser'),
                      },
                    ),
              style: label,
            ),
            if (answer?.note case final note?) ...[
              const SizedBox(height: 2),
              Text(note, style: body),
            ],
          ],
        ),
      ),
    );
  }
}
