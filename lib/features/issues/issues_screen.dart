import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/hinata_repository.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/project_palette.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';
import 'issue_detail_sheet.dart';
import 'issue_form.dart';

typedef _IssuesData = ({
  List<Issue> issues,
  int total,
  Map<String, String> names,
  Map<String, String> avatars,
  ProjectPalette palette,
});

class IssuesScreen extends StatefulWidget {
  const IssuesScreen({super.key, this.projectId});

  final String? projectId;

  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

enum _IssueFilter { all, mine, open, bugs }

class _IssuesScreenState extends State<IssuesScreen> {
  late FetchCubit<_IssuesData> _cubit;
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  _IssueFilter _filter = _IssueFilter.all;

  @override
  void initState() {
    super.initState();
    _cubit = FetchCubit<_IssuesData>(() async {
      final repo = context.read<HinataRepository>();
      final results = await Future.wait([
        repo.issues(projectId: widget.projectId, query: _query),
        repo.users(),
        repo.projects(),
      ]);
      final page = results[0] as ({List<Issue> issues, int total});
      final users = results[1] as List<DirectoryUser>;
      final projects = results[2] as List<Project>;
      final names = {for (final u in users) u.id: u.displayName};
      final avatars = {
        for (final u in users)
          if (u.avatarUrl != null && u.avatarUrl!.isNotEmpty) u.id: u.avatarUrl!,
      };
      return (
        issues: page.issues,
        total: page.total,
        names: names,
        avatars: avatars,
        palette: ProjectPalette.fromProjects(projects),
      );
    })..load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _cubit.close();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = value;
      _cubit.load();
    });
  }

  List<Issue> _apply(List<Issue> issues) {
    var list = issues;
    switch (_filter) {
      case _IssueFilter.open:
        list = list.where((i) => !i.resolved).toList();
      case _IssueFilter.bugs:
        list = list.where((i) => i.type.toUpperCase() == 'BUG').toList();
      case _IssueFilter.mine:
        final myId = context.read<AuthBloc>().state.user?.id;
        list = myId == null
            ? const []
            : list.where((i) => i.assigneeId == myId).toList();
      case _IssueFilter.all:
        break;
    }
    const rank = {'URGENT': 4, 'HIGH': 3, 'NORMAL': 2, 'LOW': 1};
    list = [...list]
      ..sort(
        (a, b) => (rank[b.priority.toUpperCase()] ?? 2).compareTo(
          rank[a.priority.toUpperCase()] ?? 2,
        ),
      );
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<FetchCubit<_IssuesData>, FetchState<_IssuesData>>(
        builder: (context, state) {
          final all = state.data?.issues ?? const <Issue>[];
          final names = state.data?.names ?? const <String, String>{};
          final avatars = state.data?.avatars ?? const <String, String>{};
          final palette = state.data?.palette ?? ProjectPalette.empty;
          final list = _apply(all);
          return RefreshIndicator(
            onRefresh: _cubit.load,
            color: AppColors.accent,
            edgeOffset: context.topGutter,
            child: AsyncView(
              isLoading: state.isLoading,
              hasData: state.hasData,
              errorKey: state.errorKey,
              onRetry: _cubit.load,
              builder: (context) => CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      context.pageGutter,
                      24 + context.topGutter,
                      context.pageGutter,
                      16,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: PageHead(
                        title: context.t('nav.issues'),
                        subtitle: context.t(
                          'issues.countSummary',
                          variables: {'count': '${list.length}'},
                        ),
                        actions: [
                          PrimaryButton(
                            label: context.t('issues.new'),
                            onPressed: () async {
                              final created = await showIssueForm(
                                context,
                                projectId: widget.projectId,
                              );
                              if (created != null) _cubit.load();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  // filter chips + search
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      context.pageGutter,
                      0,
                      context.pageGutter,
                      14,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final f in _IssueFilter.values)
                            _FilterChip(
                              icon: _filterIcon(f),
                              label: context.t(_filterKey(f)),
                              active: _filter == f,
                              onTap: () => setState(() => _filter = f),
                            ),
                          SizedBox(
                            width: 240,
                            child: _SearchField(
                              controller: _search,
                              hint: context.t('issues.searchHint'),
                              onChanged: _onSearchChanged,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (list.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: context.pageGutter, vertical: 40),
                        child: HiveEmptyState(
                          title: context.t('nav.issues'),
                          message: context.t('issues.empty'),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        context.pageGutter,
                        0,
                        context.pageGutter,
                        context.pageGutter + context.bottomGutter,
                      ),
                      sliver: SliverList.list(
                        children: [
                          if (!context.isCompact) const _IssueTableHeader(),
                          for (final issue in list)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: IssueRow(
                                issue: issue,
                                assignee: names[issue.assigneeId],
                                assigneeAvatar: avatars[issue.assigneeId],
                                palette: palette,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _filterIcon(_IssueFilter f) => switch (f) {
    _IssueFilter.all => LucideIcons.layers,
    _IssueFilter.mine => LucideIcons.user,
    _IssueFilter.open => LucideIcons.circle,
    _IssueFilter.bugs => LucideIcons.bug,
  };

  String _filterKey(_IssueFilter f) => switch (f) {
    _IssueFilter.all => 'issues.filterAll',
    _IssueFilter.mine => 'issues.filterMine',
    _IssueFilter.open => 'issues.filterOpen',
    _IssueFilter.bugs => 'issues.filterBugs',
  };
}

// ───────────────────────────── filter chip / search ─────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.accentSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(
            color: active ? AppColors.accentLine : AppColors.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? AppColors.ink : AppColors.inkSoft,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: active ? AppColors.ink : AppColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppColors.hairline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 16, color: AppColors.inkFaint),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(fontSize: 13, color: AppColors.ink),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── table ────────────────────────────────────

class _IssueTableHeader extends StatelessWidget {
  const _IssueTableHeader();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: AppColors.inkFaint,
    );
    Widget cell(String key, {int? flex, double? width}) {
      final text = Text(
        context.t(key).toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
      if (width != null) return SizedBox(width: width, child: text);
      return Expanded(flex: flex!, child: text);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          cell('issues.colId', width: 76),
          const SizedBox(width: 12),
          cell('issues.colTitle', flex: 5),
          const SizedBox(width: 12),
          cell('issues.colStatus', flex: 3),
          const SizedBox(width: 8),
          cell('issues.colPriority', flex: 3),
          const SizedBox(width: 8),
          cell('issues.colAssignee', flex: 3),
          const SizedBox(width: 8),
          cell('issues.colDue', width: 60),
          const SizedBox(width: 18),
        ],
      ),
    );
  }
}

class IssueRow extends StatelessWidget {
  const IssueRow({
    super.key,
    required this.issue,
    this.assignee,
    this.assigneeAvatar,
    this.onTap,
    this.palette,
  });

  final Issue issue;
  final String? assignee;
  final String? assigneeAvatar;
  final VoidCallback? onTap;
  final ProjectPalette? palette;

  @override
  Widget build(BuildContext context) {
    final due = dueLabel(issue.dueDate);
    final compact = context.isCompact;
    final name = assignee ?? '';

    final tap =
        onTap ??
        () => showIssueDetailSheet(
          context,
          issueId: issue.id,
          onChanged: () => context.read<FetchCubit<_IssuesData>>().load(),
        );

    if (compact) {
      return SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: tap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IdMono(issue.readableId),
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: PriorityFlag(
                    priority: issue.priority,
                    withLabel: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TypeGlyph(type: issue.type),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    issue.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: StateDotBadge(
                    state: issue.state,
                    color: palette?.stateColor(issue.state),
                  ),
                ),
                if (name.isNotEmpty)
                  HiveAvatar(name: name, imageUrl: assigneeAvatar, size: 22),
                if (due != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    due.text,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 12,
                      color: due.late ? AppColors.danger : AppColors.inkSoft,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      onTap: tap,
      child: Row(
        children: [
          SizedBox(width: 76, child: IdMono(issue.readableId)),
          const SizedBox(width: 12),
          // title
          Expanded(
            flex: 5,
            child: Row(
              children: [
                TypeGlyph(type: issue.type),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    issue.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (issue.tags.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: LabelTag(
                      issue.tags.first,
                      hue: palette?.labelHue(issue.tags.first),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StateDotBadge(
                state: issue.state,
                color: palette?.stateColor(issue.state),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: PriorityFlag(priority: issue.priority, withLabel: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: name.isEmpty
                ? Text('—', style: TextStyle(color: AppColors.inkFaint))
                : Row(
                    children: [
                      HiveAvatar(name: name, imageUrl: assigneeAvatar, size: 24),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          name.split(' ').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              due?.text ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 12,
                color: due != null && due.late
                    ? AppColors.danger
                    : AppColors.inkSoft,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Icon(
            LucideIcons.chevronRight,
            size: 18,
            color: AppColors.inkFaint,
          ),
        ],
      ),
    );
  }
}
