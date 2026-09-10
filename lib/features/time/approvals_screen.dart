import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/blocs/time_policy_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/time_approval_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/time_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/glass_filter_bar.dart';
import '../../core/widgets/glass_switch_chip.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../issues/work_item_labels.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart'
    show GlassModalHeader, showGlassModal;
import 'approval_actions.dart';
import 'lock_notice.dart';
import 'time_views.dart';

/// Handed-in periods: one's own, and the ones waiting for a decision.
///
/// Two lists on one page rather than two pages, because they are the same row
/// read from two sides and the difference is one rule on the server. Everyone has
/// the first — the history of what they handed in and what became of it, which
/// the timesheet's chips only show for the period on screen. The second appears
/// for whoever can decide something; a member who leads nothing sees an empty
/// inbox, and an empty inbox is an honest answer rather than a hidden feature.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  final _scroll = ScrollController();
  late final PagedCubit<TimesheetApproval> _approvals;

  /// `mine` or `inbox`. A field rather than two cubits: the rows are the same
  /// shape, and two cubits would be two scroll positions to keep in step.
  String _scope = 'mine';

  /// Names for exactly the people and projects the loaded rows mention. Never the
  /// whole directory or catalogue — an instance can hold hundreds of each.
  Map<String, DirectoryUser> _users = const {};
  Map<String, Project> _projects = const {};

  @override
  void initState() {
    super.initState();
    _approvals = PagedCubit<TimesheetApproval>(
      (page, size) => context.read<TimeRepository>().approvals(
        scope: _scope,
        page: page,
        size: size,
      ),
      pageSize: 25,
      keyOf: (approval) => approval.id,
    );
    _scroll.addListener(_onScroll);
    // The rules, once: whether approvals exist at all decides whether this page
    // has anything to say, and the lock vocabulary below reads from them.
    unawaited(context.read<TimePolicyCubit>().ensureLoaded());
    unawaited(_reload());
  }

  @override
  void dispose() {
    _scroll.dispose();
    unawaited(_approvals.close());
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      unawaited(_approvals.loadMore());
    }
  }

  Future<void> _reload() async {
    await _approvals.load();
    if (mounted) unawaited(_resolveLabels());
  }

  void _switchScope(String scope) {
    if (_scope == scope) return;
    setState(() => _scope = scope);
    unawaited(_reload());
  }

  /// Names for the ids on screen. A failure keeps whatever is already held: a
  /// name that could not be fetched is still better shown as the last one known
  /// than as nothing.
  Future<void> _resolveLabels() async {
    final rows = _approvals.state.items;
    final userIds = {for (final row in rows) row.userId}
      ..removeWhere((id) => id.isEmpty);
    final projectIds = {for (final row in rows) row.projectId}
      ..removeWhere((id) => id.isEmpty);
    final resolved = await Future.wait([
      _resolveUsers(userIds),
      _resolveProjects(projectIds),
    ]);
    if (!mounted) return;
    setState(() {
      _users = (resolved[0] as Map<String, DirectoryUser>?) ?? _users;
      _projects = (resolved[1] as Map<String, Project>?) ?? _projects;
    });
  }

  Future<Map<String, DirectoryUser>?> _resolveUsers(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    try {
      final users = await context.read<UserRepository>().usersByIds(
        ids.toList(),
      );
      return {for (final user in users) user.id: user};
    } on ApiFailure {
      return null;
    }
  }

  Future<Map<String, Project>?> _resolveProjects(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    try {
      final projects = await context.read<ProjectRepository>().resolveProjects(
        ids.toList(),
      );
      return {for (final project in projects) project.id: project};
    } on ApiFailure {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return PageChrome(
      onTitleTap: compact
          ? (anchor) => unawaited(
              showTimeViewMenu<Never>(
                context,
                anchor: anchor,
                current: TimeView.approvals,
              ),
            )
          : null,
      titleLeading: true,
      bottom: compact ? _dockedScopes() : null,
      bottomHeight: compact ? kGlassDockRow : 0,
      child: compact
          ? _body()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.pageGutter,
                    18 + context.topGutter,
                    context.pageGutter,
                    12,
                  ),
                  child: PageHead(
                    title: context.t('nav.time'),
                    actions: const [
                      TimeViewSwitcher(current: TimeView.approvals),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.pageGutter,
                    0,
                    context.pageGutter,
                    12,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _scopeSwitch(),
                  ),
                ),
                Expanded(child: _body()),
              ],
            ),
    );
  }

  /// The two lists, as one switch. Same control the module's views wear, so a
  /// reader meets one idiom rather than two.
  Widget _scopeSwitch() => GlassSwitchBar(
    maxWidth: 280,
    chips: [
      GlassSwitchChip(
        label: context.t('time.approval.scope.mine'),
        icon: LucideIcons.user,
        active: _scope == 'mine',
        onTap: _scope == 'mine' ? null : () => _switchScope('mine'),
      ),
      const SizedBox(width: 2),
      GlassSwitchChip(
        label: context.t('time.approval.scope.inbox'),
        icon: LucideIcons.inbox,
        active: _scope == 'inbox',
        onTap: _scope == 'inbox' ? null : () => _switchScope('inbox'),
      ),
    ],
  );

  Widget _dockedScopes() => Align(
    alignment: AlignmentDirectional.centerStart,
    child: SizedBox(
      height: kGlassControlHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
        children: [_scopeSwitch()],
      ),
    ),
  );

  Widget _body() {
    return BlocBuilder<
      PagedCubit<TimesheetApproval>,
      PagedState<TimesheetApproval>
    >(
      bloc: _approvals,
      builder: (context, state) {
        if (state.isLoading && state.items.isEmpty) {
          return const Center(
            child: Padding(padding: EdgeInsets.all(40), child: HiveLoader()),
          );
        }
        if (state.errorKey != null && state.items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.t(state.errorKey!),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => unawaited(_reload()),
                    child: Text(context.t('common.retry')),
                  ),
                ],
              ),
            ),
          );
        }
        if (state.items.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                context.pageGutter,
                context.isCompact ? context.topGutter + context.pageGutter : 8,
                context.pageGutter,
                context.pageGutter + context.bottomGutter,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: HiveEmptyState(
                  title: context.t('time.approval.empty.$_scope.title'),
                  message: context.t('time.approval.empty.$_scope.message'),
                ),
              ),
            ),
          );
        }
        return ListView.separated(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(
            context.pageGutter,
            context.isCompact ? context.topGutter + context.pageGutter : 0,
            context.pageGutter,
            context.pageGutter + context.bottomGutter,
          ),
          itemCount: state.items.length + (state.hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index >= state.items.length) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: HiveLoader()),
              );
            }
            return _ApprovalCard(
              approval: state.items[index],
              user: _users[state.items[index].userId],
              project: _projects[state.items[index].projectId],
              // The inbox is where decisions are made. On one's own list the
              // same row is read-only: nobody signs off their own period, and a
              // button that always answered 403 would be a worse way to say so.
              decidable: _scope == 'inbox',
              onChanged: _reload,
            );
          },
        );
      },
    );
  }
}

/// One submission: whose, which project, which span, where it stands.
class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.approval,
    required this.user,
    required this.project,
    required this.decidable,
    required this.onChanged,
  });

  final TimesheetApproval approval;
  final DirectoryUser? user;
  final Project? project;
  final bool decidable;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final pending = approval.status == ApprovalStatus.submitted;
    final approved = approval.status == ApprovalStatus.approved;
    final name = user?.displayName ?? context.t('time.deletedUser');
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(
                name: name,
                imageUrl: user?.avatarUrl,
                pronouns: user?.pronouns,
                radius: 14,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatPeriod(
                        context,
                        approval.periodStart,
                        approval.periodEnd,
                      ),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$name · ${project?.key ?? project?.name ?? context.t('time.fmt.none')}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    fmtDuration(context, approval.totalMinutes),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ApprovalStatusChip(status: approval.status),
                ],
              ),
            ],
          ),
          if ((approval.note ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.hairline2),
              ),
              child: Text(
                approval.note!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GhostButton(
                icon: LucideIcons.listTree,
                label: context.t('time.approval.showEntries'),
                onPressed: () =>
                    unawaited(_showEntries(context, approval, project)),
              ),
              if (decidable && pending) ...[
                PrimaryButton(
                  icon: LucideIcons.check,
                  label: context.t('time.approval.approveAction'),
                  onPressed: () => unawaited(_act(context, _Decision.approve)),
                ),
                GhostButton(
                  icon: LucideIcons.undo2,
                  label: context.t('time.approval.rejectAction'),
                  onPressed: () => unawaited(_act(context, _Decision.reject)),
                ),
              ],
              if (decidable && approved)
                GhostButton(
                  icon: LucideIcons.unlock,
                  label: context.t('time.approval.reopenAction'),
                  onPressed: () => unawaited(_act(context, _Decision.reopen)),
                ),
            ],
          ),
          if (approval.history.length > 1) ...[
            const SizedBox(height: 10),
            _History(history: approval.history, users: user),
          ],
        ],
      ),
    );
  }

  Future<void> _act(BuildContext context, _Decision decision) async {
    // The context is handed to exactly one of the three, which awaits inside
    // itself and guards its own mounted checks. Nothing here touches it after
    // the await, which is why the list can be reloaded unconditionally.
    final done = switch (decision) {
      _Decision.approve => ApprovalActions.approve(context, approval.id),
      _Decision.reject => ApprovalActions.reject(context, approval.id),
      _Decision.reopen => ApprovalActions.reopen(context, approval.id),
    };
    if (await done) await onChanged();
  }
}

enum _Decision { approve, reject, reopen }

/// The round trip, oldest first — what makes a rejection legible.
class _History extends StatelessWidget {
  const _History({required this.history, required this.users});

  final List<ApprovalEvent> history;
  final DirectoryUser? users;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final event in history)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(
                  LucideIcons.cornerDownRight,
                  size: 11,
                  color: AppColors.inkFaint,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${context.t(event.to?.labelKey ?? 'time.approval.status.open')}'
                    '${event.at == null ? '' : ' · ${localizations.formatShortDate(event.at!.toLocal())}'}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The entries a submission covers, paged — what an approver actually reads.
///
/// Paged rather than all at once, and for a reason that is not only size: a month
/// of somebody else's working time is exactly the data R2 of the epic keeps
/// behind an explicit policy, and a screen that drained it into memory to render
/// twenty rows would hold the rest for no purpose.
Future<void> _showEntries(
  BuildContext context,
  TimesheetApproval approval,
  Project? project,
) => showGlassModal<void>(
  context,
  width: 560,
  builder: (modalContext) => BlocProvider(
    create: (_) => PagedCubit<WorkItem>(
      (page, size) => context.read<TimeRepository>().approvalEntries(
        approval.id,
        page: page,
        size: size,
      ),
      pageSize: 25,
      keyOf: (entry) => entry.id,
    )..load(),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.listTree,
          title: formatPeriod(
            modalContext,
            approval.periodStart,
            approval.periodEnd,
          ),
          subtitle:
              project?.name ?? project?.key ?? modalContext.t('time.fmt.none'),
        ),
        Flexible(
          child: BlocBuilder<PagedCubit<WorkItem>, PagedState<WorkItem>>(
            builder: (innerContext, state) {
              if (state.isLoading && state.items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: HiveLoader()),
                );
              }
              if (state.items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
                  child: Text(
                    innerContext.t('time.noEntries'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              }
              return NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.pixels >=
                      notification.metrics.maxScrollExtent - 200) {
                    unawaited(
                      innerContext.read<PagedCubit<WorkItem>>().loadMore(),
                    );
                  }
                  return false;
                },
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
                  itemCount: state.items.length + (state.hasMore ? 1 : 0),
                  separatorBuilder: (_, _) =>
                      Divider(height: 14, color: AppColors.hairline2),
                  itemBuilder: (rowContext, index) {
                    if (index >= state.items.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: HiveLoader()),
                      );
                    }
                    final entry = state.items[index];
                    return Row(
                      children: [
                        SizedBox(
                          width: 74,
                          child: Text(
                            entry.date == null
                                ? ''
                                : MaterialLocalizations.of(
                                    rowContext,
                                  ).formatShortDate(entry.date!),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            (entry.description ?? '').trim().isEmpty
                                ? activityLabel(rowContext, entry.activityType)
                                : entry.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          fmtDuration(rowContext, entry.durationMinutes),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    ),
  ),
);
