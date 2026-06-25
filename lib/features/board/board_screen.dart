import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hinata_repository.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/team_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/project_palette.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../issues/issue_detail_sheet.dart';
import '../issues/issue_form.dart';
import '../issues/issues_screen.dart' show IssueRow;
import '../shell/page_chrome.dart';
import '../sprint/sprint_board_view.dart';
import 'board_filter.dart';
import 'board_manage_menu.dart';
import 'board_swimlanes.dart';
import 'create_board_dialog.dart';
import 'board_filter_popup.dart';
import 'board_people_strip.dart';
import 'board_timeline.dart';

// ─────────────────────────── BoardScreen ──────────────────────────────────
// Shown at /board — lists all boards across projects; can filter by project.
// Tapping a board card navigates to /boards/:id.

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  List<AgileBoard> _boards = const [];
  List<Project> _projects = const [];
  List<Team> _teams = const [];
  String? _projectFilter;
  bool _loading = true;
  String? _error;

  /// Owner / project-lead / team-lead / platform-admin may manage a board.
  bool _canManageBoard(AgileBoard board) {
    final me = context.read<AuthBloc>().state.user;
    if (me == null) return false;
    if (me.isAdmin || board.ownerId == me.id) return true;
    for (final pid in board.projectIds) {
      final project = _projects.where((p) => p.id == pid).firstOrNull;
      if (project != null && project.leadIds.contains(me.id)) return true;
      final teamLead = _teams.any(
        (t) =>
            t.projectIds.contains(pid) &&
            (t.membershipOf(me.id)?.isAdmin ?? false),
      );
      if (teamLead) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = context.read<HinataRepository>();
    try {
      final results = await Future.wait([
        repo.projects(),
        repo.boards(projectId: _projectFilter),
        repo.teams(),
      ]);
      _projects = results[0] as List<Project>;
      _boards = results[1] as List<AgileBoard>;
      _teams = results[2] as List<Team>;
      setState(() => _loading = false);
    } on ApiFailure catch (failure) {
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _showCreate() async {
    if (_projects.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('board.needsProject'))));
      return;
    }
    final created = await showCreateBoardDialog(
      context,
      projects: _projects,
      initialProjectId: _projectFilter,
    );
    if (created != null && mounted) {
      context.push('/boards/${created.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _boards.isEmpty && _error == null) {
      return const Center(child: HiveLoader());
    }
    if (_error != null && _boards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t(_error!),
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              child: Text(context.t('common.retry')),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            context.pageGutter,
            16 + context.topGutter,
            context.pageGutter,
            8,
          ),
          sliver: SliverToBoxAdapter(
            child: _BoardsListHeader(
              title: context.t('board.title'),
              filter: _projects.isEmpty
                  ? null
                  : _ProjectFilterChip(
                      projects: _projects,
                      selected: _projectFilter,
                      onChanged: (id) {
                        _projectFilter = id;
                        _load();
                      },
                    ),
              onCreate: _showCreate,
            ),
          ),
        ),
        if (_boards.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.pageGutter,
                vertical: 24,
              ),
              child: Center(
                child: HiveEmptyState(
                  title: context.t('board.title'),
                  message: context.t('board.empty'),
                  action: FilledButton.icon(
                    onPressed: _showCreate,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: const Color(0xFF2A2410),
                    ),
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: Text(context.t('board.newBoard')),
                  ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              context.pageGutter,
              context.pageGutter,
              context.pageGutter,
              context.pageGutter + context.bottomGutter,
            ),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: context.gridColumns(minTileWidth: 280),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                mainAxisExtent: 150,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _BoardListCard(
                  board: _boards[index],
                  index: index,
                  projects: _projects,
                  canManage: _canManageBoard(_boards[index]),
                  onChanged: _load,
                ),
                childCount: _boards.length,
              ),
            ),
          ),
      ],
    );
  }
}

/// Header for the boards-list screen.
///
/// On compact (phone) layouts the title gets a full-width row of its own and the
/// project filter + create button wrap onto a second row, so the title is never
/// squeezed to an ellipsis. On wider layouts everything sits inline.
class _BoardsListHeader extends StatelessWidget {
  const _BoardsListHeader({
    required this.title,
    required this.filter,
    required this.onCreate,
  });

  final String title;
  final Widget? filter;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final createButton = FilledButton.icon(
      onPressed: onCreate,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF2A2410),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      icon: const Icon(LucideIcons.plus, size: 18),
      label: Text(context.t('board.newBoard')),
    );

    if (context.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleText,
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (filter != null)
                Flexible(child: filter!)
              else
                const SizedBox.shrink(),
              const SizedBox(width: 8),
              createButton,
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: titleText),
        if (filter != null)
          Padding(padding: const EdgeInsets.only(right: 8), child: filter!),
        createButton,
      ],
    );
  }
}

// ─────────────────────────── KanbanBoardScreen ────────────────────────────
// Shown at /boards/:id — the actual drag-and-drop kanban for one board.

class KanbanBoardScreen extends StatefulWidget {
  const KanbanBoardScreen({super.key, required this.boardId});

  final String boardId;

  @override
  State<KanbanBoardScreen> createState() => _KanbanBoardScreenState();
}

/// Which view the kanban screen is showing.
enum BoardViewMode { board, backlog, timeline }

class _KanbanBoardScreenState extends State<KanbanBoardScreen> {
  String? _sprintId;
  BoardView? _view;
  bool _loading = true;
  String? _error;

  BoardViewMode _mode = BoardViewMode.board;
  Map<String, String> _names = const {};
  Map<String, String> _avatars = const {};
  Map<String, String> _projectNames = const {};
  List<String> _projectLabels = const [];
  ProjectPalette _palette = ProjectPalette.empty;
  List<Issue> _backlog = const [];
  BoardFilter _filter = BoardFilter.empty;
  BoardGrouping _grouping = BoardGrouping.none;

  /// Every project issue keyed by id — resolves an issue's epic (a sub-task's
  /// epic is its grandparent) for swimlane grouping and the epic filter.
  Map<String, Issue> _issuesById = const {};

  final GlobalKey _filterKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = context.read<HinataRepository>();
    try {
      final results = await Future.wait([
        repo.boardView(widget.boardId, sprintId: _sprintId),
        repo.users(),
        repo.projects(),
        repo.teams(),
      ]);
      final view = results[0] as BoardView;
      final users = results[1] as List<DirectoryUser>;
      final projects = results[2] as List<Project>;
      final loaded = await _loadBacklog(repo, view.board.projectIds);
      final backlog = loaded.backlog;
      if (!mounted) return;
      final boardProjectIds = view.board.projectIds.toSet();
      setState(() {
        _view = view;
        _names = {for (final u in users) u.id: u.displayName};
        _avatars = {
          for (final u in users)
            if (u.avatarUrl != null && u.avatarUrl!.isNotEmpty)
              u.id: u.avatarUrl!,
        };
        _projectNames = {for (final p in projects) p.id: p.name};
        _projectLabels = [
          for (final p in projects)
            if (boardProjectIds.contains(p.id)) ...p.labelNames,
        ];
        _palette = ProjectPalette.fromProjects(
          projects.where((p) => boardProjectIds.contains(p.id)),
        );
        _backlog = backlog;
        _issuesById = loaded.byId;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  /// Loads every project issue once: the backlog (no-sprint issues) plus a
  /// by-id index used to resolve an issue's epic for grouping / filtering.
  Future<({List<Issue> backlog, Map<String, Issue> byId})> _loadBacklog(
    HinataRepository repo,
    List<String> projectIds,
  ) async {
    if (projectIds.isEmpty) {
      return (backlog: const <Issue>[], byId: const <String, Issue>{});
    }
    final pages = await Future.wait(
      projectIds.map((p) => repo.issues(projectId: p, size: 500)),
    );
    final seen = <String>{};
    final out = <Issue>[];
    final byId = <String, Issue>{};
    for (final page in pages) {
      for (final issue in page.issues) {
        byId[issue.id] = issue;
        if (issue.sprintId == null && seen.add(issue.id)) out.add(issue);
      }
    }
    return (backlog: out, byId: byId);
  }

  // ---- derived views ----

  List<Issue> get _allBoardIssues => [
    for (final c in _view?.columns ?? const <BoardColumnView>[]) ...c.issues,
  ];

  List<BoardColumnView> get _kanbanColumns =>
      (_view?.columns ?? const <BoardColumnView>[]).toList();

  /// Epics across the board's projects — drive grouping headers + the filter.
  List<Issue> get _epics =>
      _issuesById.values.where((i) => i.isEpic).toList()
        ..sort((a, b) => a.readableId.compareTo(b.readableId));

  Map<String, String> get _epicNames => {
    for (final e in _epics) e.id: '${e.readableId}  ${e.title}',
  };

  /// Combined predicate: every facet plus the epic facet (resolved per issue).
  bool _passes(Issue i) =>
      _filter.matches(i) && _filter.matchesEpic(boardEpicOf(i, _issuesById));

  List<String> get _peopleIds {
    final seen = <String>{};
    final out = <String>[];
    for (final issue in [..._allBoardIssues, ..._backlog]) {
      final a = issue.assigneeId;
      if (a != null && a.isNotEmpty && seen.add(a)) out.add(a);
    }
    return out;
  }

  BoardFilterOptions get _options => BoardFilterOptions.from(
    issues: [..._allBoardIssues, ..._backlog],
    boardSprints: _view?.sprints ?? const [],
    projectLabels: _projectLabels,
    epicIds: _epics.map((e) => e.id),
  );

  Map<String, String> get _sprintNames => {
    for (final s in _view?.sprints ?? const <Sprint>[]) s.id: s.name,
  };

  Sprint? get _activeSprint {
    final view = _view;
    if (view == null) return null;
    if (_sprintId != null) {
      return view.sprints.where((s) => s.id == _sprintId).firstOrNull;
    }
    final active = view.board.activeSprintId;
    if (active != null) {
      return view.sprints.where((s) => s.id == active).firstOrNull;
    }
    return null;
  }

  void _openIssue(Issue issue) =>
      showIssueDetailSheet(context, issueId: issue.id, onChanged: _load);

  Future<void> _moveIssue(Issue issue, BoardColumnView column) async {
    if (column.states.contains(issue.state) || column.states.isEmpty) return;
    try {
      await context.read<HinataRepository>().updateIssue(issue.id, {
        'state': column.states.first,
      });
      await _load();
    } on ApiFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  Future<void> _addIssue(BoardColumnView column) async {
    final view = _view;
    if (view == null) return;
    final projectId = view.board.projectIds.isNotEmpty
        ? view.board.projectIds.first
        : null;
    final created = await showIssueForm(
      context,
      projectId: projectId,
      initialState: column.states.isNotEmpty ? column.states.first : null,
    );
    if (created != null) await _load();
  }

  void _openFilter() => openBoardFilter(
    context,
    anchorKey: _filterKey,
    filter: _filter,
    options: _options,
    names: _names,
    avatars: _avatars,
    sprintNames: _sprintNames,
    epicNames: _epicNames,
    onChanged: (f) => setState(() => _filter = f),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading && _view == null) {
      return const Center(child: HiveLoader());
    }
    if (_error != null && _view == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t(_error!),
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              child: Text(context.t('common.retry')),
            ),
          ],
        ),
      );
    }
    final view = _view!;
    // Scrum boards swap the Kanban/Backlog/Timeline surfaces for the sprint
    // planning · active · insights surfaces. The sprint view owns its own data
    // (sprints, story points, report) and reuses the loaded name maps.
    if (view.board.isScrum) {
      return PageChrome(
        title: view.board.name,
        child: ScrumBoardView(
          view: view,
          names: _names,
          avatars: _avatars,
          projectNames: _projectNames,
          onOpenIssue: _openIssue,
        ),
      );
    }
    // Back navigation is handled by the shell app bar (via PageChrome), which
    // also shows the board name as the title.
    return PageChrome(
      title: view.board.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.pageGutter,
              22 + context.topGutter,
              context.pageGutter,
              10,
            ),
            child: _header(view),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.pageGutter,
              0,
              context.pageGutter,
              10,
            ),
            child: _metaArea(view),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  // ---- header: title + view switcher ----

  /// Deletes the open board, then leaves for the boards overview (a fresh route
  /// so the list no longer shows it).
  Widget _header(BoardView view) {
    final projectLabel = view.board.projectIds
        .map((id) => _projectNames[id] ?? '')
        .where((s) => s.isNotEmpty)
        .join(', ');
    final subtitle = projectLabel.isEmpty
        ? context.t('board.agileBoard')
        : '$projectLabel · ${context.t('board.agileBoard')}';

    if (context.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHead(
            title: view.board.name,
            subtitle: subtitle,
          ),
          const SizedBox(height: 12),
          // Right-aligned, collapsible, responsive-label switcher (mobile).
          _CompactViewSwitcher(
            items: _switcherItems(),
            selected: _viewModes.indexOf(_mode).clamp(0, _viewModes.length - 1),
            onChanged: (i) => setState(() => _mode = _viewModes[i]),
          ),
        ],
      );
    }
    return PageHead(
      title: view.board.name,
      subtitle: subtitle,
      actions: [
        SegmentedControl(
          items: _switcherItems(),
          selected: _viewModes.indexOf(_mode).clamp(0, _viewModes.length - 1),
          onChanged: (i) => setState(() => _mode = _viewModes[i]),
        ),
      ],
    );
  }

  /// Views offered for a (Kanban) board. The Backlog view is a Scrum-only
  /// concept, so it isn't offered here — Scrum boards render the dedicated
  /// sprint planning surface instead.
  static const List<BoardViewMode> _viewModes = [
    BoardViewMode.board,
    BoardViewMode.timeline,
  ];

  SegmentItem _itemFor(BoardViewMode mode) => switch (mode) {
    BoardViewMode.board => SegmentItem(
      label: context.t('board.view.board'),
      icon: LucideIcons.squareKanban,
    ),
    BoardViewMode.backlog => SegmentItem(
      label: context.t('board.view.backlog'),
      icon: LucideIcons.list,
    ),
    BoardViewMode.timeline => SegmentItem(
      label: context.t('board.view.timeline'),
      icon: LucideIcons.waypoints,
    ),
  };

  List<SegmentItem> _switcherItems() => [
    for (final mode in _viewModes) _itemFor(mode),
  ];

  // ---- meta area: sprint header + people strip + filter ----

  Widget _metaArea(BoardView view) {
    final sprint = _activeSprint;
    final children = <Widget>[];
    if (sprint != null) {
      children.add(
        Row(
          children: [
            Expanded(child: _SprintHeader(sprint: sprint)),
            if (view.sprints.length > 1) ...[
              const SizedBox(width: 12),
              _SprintSelector(
                sprints: view.sprints,
                selected: _sprintId,
                onChanged: (value) {
                  _sprintId = value;
                  _load();
                },
              ),
            ],
          ],
        ),
      );
      children.add(const SizedBox(height: 10));
    }
    children.add(_controlsRow());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _controlsRow() {
    final people = BoardPeopleStrip(
      userIds: _peopleIds,
      names: _names,
      avatars: _avatars,
      selected: _filter.assignees,
      onToggle: (id) => setState(
        () => _filter = _filter.toggle(BoardFilterFacet.assignee, id),
      ),
    );
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: people,
          ),
        ),
        const SizedBox(width: 10),
        BoardGroupByButton(
          value: _grouping,
          onChanged: (g) => setState(() => _grouping = g),
        ),
        const SizedBox(width: 10),
        _BoardFilterButton(
          key: _filterKey,
          count: _filter.activeCount,
          onTap: _openFilter,
        ),
      ],
    );
  }

  // ---- body ----

  Widget _body() {
    switch (_mode) {
      case BoardViewMode.board:
        return _kanban();
      case BoardViewMode.backlog:
        return _backlogList();
      case BoardViewMode.timeline:
        return BoardTimeline(
          issues: _allBoardIssues.where(_passes).toList(),
          onOpen: _openIssue,
          padding: EdgeInsets.fromLTRB(
            context.pageGutter,
            0,
            context.pageGutter,
            context.pageGutter + context.bottomGutter,
          ),
        );
    }
  }

  Widget _kanban() {
    final columns = _kanbanColumns;
    if (columns.isEmpty) {
      return Center(
        child: Text(
          context.t('board.empty'),
          style: TextStyle(color: AppColors.inkSoft),
        ),
      );
    }
    if (_grouping != BoardGrouping.none) return _groupedBoard(columns);
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        0,
        context.pageGutter,
        context.pageGutter + context.bottomGutter,
      ),
      itemCount: columns.length,
      separatorBuilder: (_, _) => const SizedBox(width: 16),
      itemBuilder: (context, index) {
        final column = columns[index];
        final issues = column.issues.where(_passes).toList();
        return _BoardColumn(
          column: column,
          issues: issues,
          palette: _palette,
          names: _names,
          avatars: _avatars,
          onAccept: (issue) => _moveIssue(issue, column),
          onAddIssue: () => _addIssue(column),
          onOpenIssue: _openIssue,
        );
      },
    );
  }

  // ---- swimlanes (grouped board) ----

  /// Renders the grouped board via the shared [BoardSwimlanes]: lanes per the
  /// active grouping, each lane carrying the full column set and its own
  /// collapse toggle.
  Widget _groupedBoard(List<BoardColumnView> columns) {
    final lanes = computeBoardLanes(
      context: context,
      grouping: _grouping,
      issues: _allBoardIssues.where(_passes).toList(),
      issuesById: _issuesById,
      epics: _epics,
      names: _names,
      palette: _palette,
      onOpenIssue: _openIssue,
    );
    if (lanes.isEmpty) {
      return Center(
        child: Text(
          context.t('board.empty'),
          style: TextStyle(color: AppColors.inkSoft),
        ),
      );
    }
    return BoardSwimlanes(
      columns: columns,
      lanes: lanes,
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        0,
        context.pageGutter,
        context.pageGutter + context.bottomGutter,
      ),
      columnBuilder: (column, issues) => _BoardColumn(
        column: column,
        laneMode: true,
        issues: issues,
        palette: _palette,
        names: _names,
        avatars: _avatars,
        onAccept: (issue) => _moveIssue(issue, column),
        onAddIssue: () => _addIssue(column),
        onOpenIssue: _openIssue,
      ),
    );
  }

  Widget _backlogList() {
    const rank = {'URGENT': 4, 'HIGH': 3, 'NORMAL': 2, 'LOW': 1};
    int prio(Issue i) => switch (i.priority.toUpperCase()) {
      'SHOWSTOPPER' || 'CRITICAL' || 'URGENT' => 5,
      'MAJOR' || 'HIGH' => 3,
      'MINOR' || 'LOW' => 1,
      _ => rank[i.priority.toUpperCase()] ?? 2,
    };
    final items = _backlog.where(_passes).toList()
      ..sort((a, b) => prio(b).compareTo(prio(a)));

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          context.pageGutter,
          0,
          context.pageGutter,
          context.pageGutter + context.bottomGutter,
        ),
        children: [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 72),
              child: Center(
                child: Text(
                  context.t('board.backlogEmpty'),
                  style: TextStyle(color: AppColors.inkSoft),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                context.t(
                  'board.backlogSubtitle',
                  variables: {'count': '${items.length}'},
                ),
                style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
              ),
            ),
            if (!context.isCompact) const _BacklogTableHeader(),
            for (final issue in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: IssueRow(
                  issue: issue,
                  assignee: _names[issue.assigneeId],
                  assigneeAvatar: _avatars[issue.assigneeId],
                  onTap: () => _openIssue(issue),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── Filter button ────────────────────────────────

/// White pill that opens the glass filter popup; shows an amber badge with the
/// active-criteria count. Its [key] anchors the popup's position.
class _BoardFilterButton extends StatelessWidget {
  const _BoardFilterButton({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(
              color: count > 0 ? AppColors.accentLine : AppColors.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.slidersHorizontal,
                size: 16,
                color: AppColors.inkSoft,
              ),
              const SizedBox(width: 7),
              Text(
                context.t('board.filterButton'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 7),
                Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2A2410),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Compact view switcher ────────────────────────

/// Mobile Board/Backlog/Timeline switcher: right-aligned, manually
/// collapsible (a chevron handle, expanded initially), with labels that
/// animate in/out as horizontal space allows, and an animated selection fill.
class _CompactViewSwitcher extends StatefulWidget {
  const _CompactViewSwitcher({
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<SegmentItem> items;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  State<_CompactViewSwitcher> createState() => _CompactViewSwitcherState();
}

class _CompactViewSwitcherState extends State<_CompactViewSwitcher> {
  static const _labelStyle = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
  );
  static const _dur = Duration(milliseconds: 240);

  bool _expanded = true;

  /// Whether the handle + all three labelled segments fit within [maxWidth].
  bool _labelsFit(double maxWidth) {
    final scaler = MediaQuery.textScalerOf(context);
    var total = 6.0 + 30.0; // outer pill padding + handle (12 pad + 18 icon)
    for (final item in widget.items) {
      final tp = TextPainter(
        text: TextSpan(text: item.label, style: _labelStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      total += 24 + 15 + 6 + tp.width; // segment: h-padding + icon + gap + text
    }
    // Comfortable slack so labels never appear right at the overflow boundary.
    return total + 8 <= maxWidth;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final showLabels = _expanded && _labelsFit(maxW);
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _handle(),
                for (var i = 0; i < widget.items.length; i++)
                  _segment(i, showLabels),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _handle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: AnimatedRotation(
          duration: _dur,
          curve: hiveEase,
          turns: _expanded ? 0 : 0.5,
          child: Icon(
            LucideIcons.chevronRight,
            size: 18,
            color: AppColors.inkFaint,
          ),
        ),
      ),
    );
  }

  Widget _segment(int i, bool showLabels) {
    final selected = i == widget.selected;
    final fg = selected ? Colors.white : AppColors.inkSoft;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onChanged(i),
      child: AnimatedContainer(
        duration: _dur,
        curve: hiveEase,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<Color?>(
              duration: _dur,
              curve: hiveEase,
              tween: ColorTween(end: fg),
              builder: (_, color, _) =>
                  Icon(widget.items[i].icon, size: 15, color: color),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: hiveEase,
              switchOutCurve: hiveEase,
              transitionBuilder: (child, anim) => SizeTransition(
                axis: Axis.horizontal,
                alignment: Alignment.centerLeft,
                sizeFactor: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: showLabels
                  ? Padding(
                      key: const ValueKey('label'),
                      padding: const EdgeInsets.only(left: 6),
                      child: AnimatedDefaultTextStyle(
                        duration: _dur,
                        curve: hiveEase,
                        style: _labelStyle.copyWith(color: fg),
                        child: Text(
                          widget.items[i].label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                        ),
                      ),
                    )
                  : const SizedBox(key: ValueKey('empty')),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Sprint header & selector ─────────────────────

/// Sprint info card: "Active" pill, sprint name + goal, and a linear
/// day-progress ("Day X/Y") when the sprint has start & end dates. Stacks the
/// progress under the name on compact widths so it never overflows.
class _SprintHeader extends StatelessWidget {
  const _SprintHeader({required this.sprint});
  final Sprint sprint;

  @override
  Widget build(BuildContext context) {
    final start = sprint.startDate;
    final end = sprint.endDate;
    Widget? progress;
    if (start != null && end != null && !end.isBefore(start)) {
      final total = end.difference(start).inDays + 1;
      final today = DateTime.now();
      final dayRaw =
          DateTime(
            today.year,
            today.month,
            today.day,
          ).difference(start).inDays +
          1;
      final day = dayRaw.clamp(1, total);
      progress = _SprintProgress(value: day / total, day: day, total: total);
    }

    final compact = context.isCompact;
    final nameBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sprint.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
        if ((sprint.goal ?? '').isNotEmpty)
          Text(
            sprint.goal!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
          ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.hairline),
      ),
      child: compact
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _ActivePill(),
                    const SizedBox(width: 12),
                    Expanded(child: nameBlock),
                  ],
                ),
                if (progress != null) ...[const SizedBox(height: 12), progress],
              ],
            )
          : Row(
              children: [
                const _ActivePill(),
                const SizedBox(width: 12),
                Expanded(child: nameBlock),
                if (progress != null) ...[
                  const SizedBox(width: 16),
                  SizedBox(width: 170, child: progress),
                ],
              ],
            ),
    );
  }
}

class _ActivePill extends StatelessWidget {
  const _ActivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.zap, size: 13, color: AppColors.accentStrong),
          const SizedBox(width: 4),
          Text(
            context.t('board.active'),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.accentStrong,
            ),
          ),
        ],
      ),
    );
  }
}

class _SprintProgress extends StatelessWidget {
  const _SprintProgress({
    required this.value,
    required this.day,
    required this.total,
  });
  final double value;
  final int day;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(child: HiveProgress(value: value, height: 6)),
        const SizedBox(width: 10),
        Text(
          context.t(
            'board.sprintDay',
            variables: {'day': '$day', 'total': '$total'},
          ),
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.inkSoft,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────── Backlog table header ─────────────────────────

/// Column header for the Backlog list, mirroring the Issues page columns.
class _BacklogTableHeader extends StatelessWidget {
  const _BacklogTableHeader();

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

class _SprintSelector extends StatelessWidget {
  const _SprintSelector({
    required this.sprints,
    required this.selected,
    required this.onChanged,
  });

  final List<Sprint> sprints;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = selected != null
        ? sprints.where((s) => s.id == selected).firstOrNull?.name ??
              context.t('board.allSprints')
        : context.t('board.allSprints');
    return GlassPopupMenu<String?>(
      value: selected,
      onSelected: onChanged,
      items: [
        GlassMenuItem(value: null, label: context.t('board.allSprints')),
        for (final s in sprints) GlassMenuItem(value: s.id, label: s.name),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.zap, size: 15, color: AppColors.inkSoft),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 16, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Board list card ──────────────────────────────

class _BoardListCard extends StatelessWidget {
  const _BoardListCard({
    required this.board,
    required this.index,
    required this.projects,
    required this.canManage,
    required this.onChanged,
  });

  final AgileBoard board;
  final int index;
  final List<Project> projects;
  final bool canManage;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final projectNames = board.projectIds
        .map(
          (id) => projects.firstWhere(
            (p) => p.id == id,
            orElse: () => Project(id: id, key: id, name: id),
          ),
        )
        .map((p) => p.name)
        .join(', ');

    return SoftCard(
      color: AppColors.pastelFor(index),
      onTap: () => context.push('/boards/${board.id}'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      board.isScrum ? LucideIcons.zap : LucideIcons.columns3,
                      size: 13,
                      color: AppColors.navy,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      context.t(
                        board.isScrum ? 'board.typeScrum' : 'board.typeKanban',
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (canManage)
                Builder(
                  builder: (btnContext) => IconButton(
                    tooltip: context.t('board.manageBoard'),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: () => openBoardManageMenu(
                      btnContext,
                      board: board,
                      onChanged: onChanged,
                    ),
                    icon: Icon(
                      LucideIcons.ellipsisVertical,
                      size: 16,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Text(
              board.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          if (projectNames.isNotEmpty)
            Text(
              projectNames,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Icon(
              LucideIcons.arrowRight,
              size: 14,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Project filter chip ──────────────────────────

class _ProjectFilterChip extends StatelessWidget {
  const _ProjectFilterChip({
    required this.projects,
    required this.selected,
    required this.onChanged,
  });

  final List<Project> projects;
  final String? selected;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    final label = selected != null
        ? projects
              .firstWhere((p) => p.id == selected, orElse: () => projects.first)
              .name
        : context.t('board.allProjects');

    return GlassPopupMenu<String?>(
      value: selected,
      onSelected: onChanged,
      items: [
        GlassMenuItem(value: null, label: context.t('board.allProjects')),
        ...projects.map((p) => GlassMenuItem(value: p.id, label: p.name)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 16, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Kanban column ────────────────────────────────

class _BoardColumn extends StatefulWidget {
  const _BoardColumn({
    required this.column,
    required this.issues,
    required this.palette,
    required this.names,
    required this.avatars,
    required this.onAccept,
    required this.onAddIssue,
    required this.onOpenIssue,
    this.laneMode = false,
  });

  final BoardColumnView column;
  final List<Issue> issues;
  final ProjectPalette palette;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final void Function(Issue) onAccept;
  final VoidCallback onAddIssue;
  final void Function(Issue) onOpenIssue;

  /// In a swimlane the board scrolls as one unit, so the column sizes to its
  /// content (no [Flexible], which needs a bounded height) instead of filling
  /// the viewport like the flat board's horizontally-scrolled columns.
  final bool laneMode;

  @override
  State<_BoardColumn> createState() => _BoardColumnState();
}

class _BoardColumnState extends State<_BoardColumn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final column = widget.column;
    final issues = widget.issues;
    final overWip = column.wipLimit != null && issues.length > column.wipLimit!;
    // Tint from the column's first workflow state, falling back to its display
    // name so the header dot still matches the theme when `states` is empty.
    // stateColor normalises case/separators, so either form resolves correctly.
    final dotColor = widget.palette.stateColor(
      column.states.isNotEmpty ? column.states.first : column.name,
    );
    final countLabel = column.wipLimit != null
        ? '${issues.length}/${column.wipLimit}'
        : '${issues.length}';

    // On mouse-driven platforms the "add issue" button stays hidden until the
    // column is hovered; on touch platforms (no hover) it's always visible.
    final platform = Theme.of(context).platform;
    final isTouch =
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.fuchsia;
    final revealAdd = isTouch || _hovered;

    return SizedBox(
      width: 300,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: DragTarget<Issue>(
          onAcceptWithDetails: (details) => widget.onAccept(details.data),
          builder: (context, candidates, rejected) {
            final dropping = candidates.isNotEmpty;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: dropping ? AppColors.accentSoft : AppColors.canvas2,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                border: dropping
                    ? Border.all(color: AppColors.accentLine, width: 2)
                    : Border.all(color: Colors.transparent, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            column.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: overWip
                                ? AppColors.dangerSoft
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: overWip
                                  ? AppColors.danger.withValues(alpha: 0.3)
                                  : AppColors.hairline,
                            ),
                          ),
                          child: Text(
                            countLabel,
                            style: TextStyle(
                              fontFamily: AppTheme.fontMono,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: overWip
                                  ? AppColors.danger
                                  : AppColors.inkSoft,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  LaneAwareFlexible(
                    laneMode: widget.laneMode,
                    child: issues.isEmpty
                        ? const SizedBox(height: 8)
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: widget.laneMode
                                ? const NeverScrollableScrollPhysics()
                                : null,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            itemCount: issues.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 9),
                            itemBuilder: (context, index) {
                              final issue = issues[index];
                              final card = _BoardCard(
                                issue: issue,
                                palette: widget.palette,
                                assigneeName: widget.names[issue.assigneeId],
                                assigneeAvatar:
                                    widget.avatars[issue.assigneeId],
                                onOpen: () => widget.onOpenIssue(issue),
                              );
                              // Touch platforms: no drag — it fights the scroll
                              // gesture. State changes happen in the detail sheet.
                              if (isTouch) return card;
                              return Draggable<Issue>(
                                data: issue,
                                dragAnchorStrategy: childDragAnchorStrategy,
                                maxSimultaneousDrags: 1,
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: SizedBox(
                                    width: 276,
                                    child: _BoardCard(
                                      issue: issue,
                                      palette: widget.palette,
                                      assigneeName:
                                          widget.names[issue.assigneeId],
                                      assigneeAvatar:
                                          widget.avatars[issue.assigneeId],
                                      dragging: true,
                                    ),
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.35,
                                  child: _BoardCard(
                                    issue: issue,
                                    palette: widget.palette,
                                    assigneeName: widget.names[issue.assigneeId],
                                    assigneeAvatar:
                                        widget.avatars[issue.assigneeId],
                                  ),
                                ),
                                child: card,
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  // Reveal the add button on hover (mouse) / always (touch); keep
                  // its space reserved so columns don't resize.
                  SizedBox(
                    width: double.infinity,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      opacity: revealAdd ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !revealAdd,
                        child: DottedAddButton(
                          label: context.t('board.addIssue'),
                          onTap: widget.onAddIssue,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.issue,
    required this.palette,
    this.assigneeName,
    this.assigneeAvatar,
    this.dragging = false,
    this.onOpen,
  });

  final Issue issue;
  final ProjectPalette palette;
  final String? assigneeName;
  final String? assigneeAvatar;
  final bool dragging;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final accent = palette.stateColor(issue.state);
    final due = dueLabel(issue.dueDate);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D191637),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: dragging ? null : onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(height: 2, color: accent),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        TypeGlyph(type: issue.type, size: 18),
                        const SizedBox(width: 8),
                        IdMono(issue.readableId),
                        const Spacer(),
                        PriorityFlag(priority: issue.priority),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      issue.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    if (issue.tags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (final t in issue.tags.take(3))
                            LabelTag(t, hue: palette.labelHue(t)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        if (issue.estimateMinutes != null &&
                            issue.estimateMinutes! > 0)
                          _MiniMeta(
                            icon: LucideIcons.timer,
                            text: fmtDuration(issue.spentMinutes),
                          ),
                        if (due != null) ...[
                          if (issue.estimateMinutes != null)
                            const SizedBox(width: 10),
                          _MiniMeta(
                            icon: LucideIcons.calendar,
                            text: due.text,
                            color: due.late ? AppColors.danger : null,
                          ),
                        ],
                        const Spacer(),
                        if (issue.assigneeId != null)
                          HiveAvatar(
                            name: assigneeName ?? issue.assigneeId!,
                            imageUrl: assigneeAvatar,
                            size: 24,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniMeta extends StatelessWidget {
  const _MiniMeta({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.inkFaint;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 11,
            color: c,
          ),
        ),
      ],
    );
  }
}

/// Dashed "Add issue" button used at the foot of board columns.
class DottedAddButton extends StatefulWidget {
  const DottedAddButton({super.key, required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  State<DottedAddButton> createState() => _DottedAddButtonState();
}

class _DottedAddButtonState extends State<DottedAddButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radiusControl);
    final accent = _hovered ? AppColors.accentStrong : AppColors.inkFaint;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: _hovered ? AppColors.accentSoft : null,
          ),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: _hovered ? AppColors.accent : AppColors.hairline,
              radius: AppTheme.radiusControl,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.plus, size: 15, color: accent),
                  const SizedBox(width: 7),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a rounded-rectangle border made of evenly spaced dashes.
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;
  static const double dashWidth = 5;
  static const double dashGap = 4;
  static const double strokeWidth = 1.3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final inset = strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        inset,
        inset,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
