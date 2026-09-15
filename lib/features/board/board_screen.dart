import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/glass_filter_bar.dart' show WideToolbar;
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/events/board_events.dart';
import '../../core/events/issue_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/board_page_models.dart';
import '../../core/models/team_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/project_palette.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/subtask_widgets.dart';
import '../issues/issue_detail_sheet.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassErrorToast, showGlassToast;
import '../sprint/sprint_board_view.dart';
import 'board_drag.dart';
import 'board_filter.dart';
import 'board_header.dart';
import 'board_manage_menu.dart';
import 'board_swimlanes.dart';
import 'create_board_dialog.dart';
import 'board_filter_popup.dart';
import 'board_people_strip.dart';
import 'board_timeline.dart';
import 'issue_quick_create.dart';
import 'wall/board_wall_cubit.dart';
import '../../core/repositories/board_repository.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/team_repository.dart';

part 'board_screen.header.dart';
part 'board_screen.cards.dart';

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

  /// Re-fetch when the set of boards changes anywhere in the app.
  ///
  /// Including from this very screen: creating a board opens it on top of this
  /// list, so the list is still mounted and behind — and without this it was
  /// still showing the boards from before the one that had just been made.
  StreamSubscription<void>? _boardSub;

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
    _boardSub = BoardEvents.instance.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _boardSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        context.read<ProjectRepository>().projects(),
        context.read<BoardRepository>().boards(projectId: _projectFilter),
        context.read<TeamRepository>().teams(),
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
      showGlassToast(
        context,
        context.t('board.needsProject'),
        kind: GlassToastKind.warning,
      );
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
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: filter!,
          ),
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
enum BoardViewMode { board, timeline }

class _KanbanBoardScreenState extends State<KanbanBoardScreen> {
  /// The wall, read page by page and narrowed on the server.
  late final BoardWallCubit _wall = BoardWallCubit(
    boards: context.read<BoardRepository>(),
    issues: context.read<IssueRepository>(),
    boardId: widget.boardId,
  );

  BoardViewMode _mode = BoardViewMode.board;
  BoardFilter _filter = BoardFilter.empty;
  BoardGrouping _grouping = BoardGrouping.none;

  /// The sprint picked in the selector; null leaves the wall on the board's
  /// active sprint.
  String? _pickedSprintId;

  /// The board's own projects by id, fetched once the wall names them. A
  /// cross-project board needs the full project, not just its name, to answer
  /// "which of this column's states does this card's project have?" on a drop.
  Map<String, Project> _projectsById = const {};
  List<String> _projectLabels = const [];
  ProjectPalette _palette = ProjectPalette.empty;
  List<String> _projectIdsLoaded = const [];

  /// What the filter, the row of faces and the epic grouping can offer, over
  /// every card of the board rather than the loaded ones.
  BoardFacets _facets = BoardFacets.empty;
  bool _facetsStale = true;

  /// The timeline's own pages: the cards with a date, and those without.
  PagedCubit<Issue>? _datedPages;
  PagedCubit<Issue>? _undatedPages;
  BoardQuery? _timelineQuery;
  String? _timelineSprintId;

  /// Issue links of the board's projects, drawn as dependency connectors on the
  /// timeline. Only that view needs them, so they load on first switch to it.
  List<GanttLink> _links = const [];
  bool _linksLoaded = false;
  bool _linksLoading = false;

  /// The search over the wall's cards, typed into the board's head.
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// Whether a phone's docked row shows the search field instead of the tools.
  /// A wide window shows both side by side and never sets it.
  bool _searching = false;

  /// Re-reads the wall when an issue is created or changed elsewhere (e.g. the
  /// global nav-rail "new issue" button, which can't reach this screen's state).
  StreamSubscription<void>? _issueSub;

  @override
  void initState() {
    super.initState();
    _issueSub = IssueEvents.instance.changes.listen((_) => _changedElsewhere());
    unawaited(_wall.load());
  }

  @override
  void dispose() {
    _issueSub?.cancel();
    _searchController.dispose();
    _closeTimeline();
    _wall.close();
    super.dispose();
  }

  void _changedElsewhere() {
    _wall.refreshSoon();
    _facetsStale = true;
    _linksLoaded = false;
    // Read the timeline again with the next state of the wall.
    _timelineQuery = null;
  }

  // ---- reacting to the wall ----

  bool _wallChanged(BoardWallState previous, BoardWallState next) =>
      previous.board != next.board ||
      !listEquals(previous.board?.projectIds, next.board?.projectIds) ||
      previous.sprintId != next.sprintId ||
      previous.query != next.query ||
      previous.refreshing != next.refreshing ||
      previous.errorKey != next.errorKey;

  void _onWall(BuildContext context, BoardWallState wall) {
    final board = wall.board;
    if (board == null) return;
    if (!listEquals(board.projectIds, _projectIdsLoaded)) {
      unawaited(_loadProjects(board.projectIds));
    }
    // A Scrum board gathers its facets over the whole board itself.
    if (!board.isScrum && _facetsStale && !wall.refreshing) {
      unawaited(_loadFacets(wall));
    }
    if (_mode == BoardViewMode.timeline && !wall.refreshing) {
      _showTimeline(wall);
    }
    final errorKey = wall.errorKey;
    if (errorKey != null) showGlassErrorToast(context, context.t(errorKey));
  }

  Future<void> _loadProjects(List<String> projectIds) async {
    _projectIdsLoaded = projectIds;
    final repository = context.read<ProjectRepository>();
    try {
      final projects = await repository.resolveProjects(projectIds);
      if (!mounted) return;
      setState(() {
        _projectsById = {for (final p in projects) p.id: p};
        _projectLabels = [for (final p in projects) ...p.labelNames];
        _palette = ProjectPalette.fromProjects(projects);
      });
    } on ApiFailure {
      // Names and colours fall back to plain ones until the next read; the
      // wall itself reads without them.
      _projectIdsLoaded = const [];
    }
  }

  Future<void> _loadFacets(BoardWallState wall) async {
    final board = wall.board;
    if (board == null) return;
    _facetsStale = false;
    final repository = context.read<BoardRepository>();
    try {
      final facets = await repository.facets(board.id, sprintId: wall.sprintId);
      if (!mounted) return;
      setState(() => _facets = facets);
    } on ApiFailure {
      // The filter keeps the options it had; the next read of the wall tries
      // again.
      _facetsStale = true;
    }
  }

  // ---- derived views ----

  BoardPeople _people(BoardWallState wall) =>
      boardPeople([...wall.users.values, ..._facets.users]);

  Map<String, String> get _projectNames => {
    for (final p in _projectsById.values) p.id: p.name,
  };

  /// The loaded cards and what they refer to, by id: what lanes resolve a
  /// sub-task's parent from.
  Map<String, Issue> _issuesById(BoardWallState wall) => {
    ...wall.refs,
    for (final card in wall.cards) card.id: card,
  };

  /// Epics across the board's projects — drive grouping headers + the filter.
  List<Issue> _epics(BoardWallState wall) =>
      boardEpics(_facets.epics, wall.refs.values);

  Map<String, String> _epicNames(BoardWallState wall) => {
    for (final e in _epics(wall)) e.id: '${e.readableId}  ${e.title}',
  };

  Map<String, String> _sprintNames(BoardWallState wall) => {
    for (final s in wall.sprints) s.id: s.name,
  };

  Sprint? _activeSprint(BoardWallState wall) {
    final id = wall.sprintId;
    if (id == null) return null;
    return wall.sprints.where((s) => s.id == id).firstOrNull;
  }

  /// The cards the wall wants: sub-tasks become cards of their own only when
  /// the wall is grouped by them.
  BoardCardShape get _shape => _grouping == BoardGrouping.subtask
      ? BoardCardShape.subtasks
      : BoardCardShape.wall;

  /// Hands the filter, the search and the grouping to the server.
  void _narrow() => _wall.narrow(_filter.toQuery(text: _query, shape: _shape));

  /// No `onChanged` here on purpose: the detail sheet broadcasts every change on
  /// [IssueEvents], which this board already listens to. Passing both would run
  /// the board reload twice per edit.
  void _openIssue(Issue issue) =>
      showIssueDetailSheet(context, issueId: issue.id);

  /// Whether this board spans more than one project — the signal that turns on
  /// the cross-project affordances (column ownership marks, project swimlane).
  bool _isCrossProject(BoardView view) => view.board.projectIds.length > 1;

  /// Whether [column] is a legal drop for [issue] — a different column that
  /// carries a workflow state this card's own project actually defines. Drives
  /// the drop affordance, so an impossible move is refused while the card is
  /// still in the air instead of ending in an error toast.
  bool _canDrop(Issue issue, BoardColumnView column) =>
      column.states.isNotEmpty &&
      !column.states.contains(issue.state) &&
      boardDropState(issue, column.states, _projectsById) != null;

  /// Moves the card on the wall at once; a refusal puts it back, and the wall
  /// raises the reason as a toast.
  Future<void> _moveIssue(Issue issue, BoardColumnView column) async {
    if (column.states.contains(issue.state) || column.states.isEmpty) return;
    final target = boardDropState(issue, column.states, _projectsById);
    if (target == null) {
      showGlassErrorToast(context, context.t('board.dropNotInWorkflow'));
      return;
    }
    if (target == issue.state) return;
    // The card settles in visibly at its new home: the tail end of the drag,
    // not a separate effect.
    boardDrag.land(issue.id);
    await _wall.move(issue, column.name, target);
    _facetsStale = true;
  }

  /// The board's projects in board order — what a column's inline composer may
  /// create into. More than one only on a merged board, where the composer
  /// shows a project control instead of silently picking the first.
  List<Project> _boardProjects(BoardView view) => [
    for (final id in view.board.projectIds)
      if (_projectsById[id] != null) _projectsById[id]!,
  ];

  /// Seeds the inline composer at the foot of [column]: the column's project(s)
  /// and workflow state, plus whatever the surrounding swimlane implies.
  IssueQuickCreateSeed _quickCreateSeed(
    BoardView view,
    BoardPeople people,
    BoardColumnView column, {
    String? parentId,
    String? forcedType,
    String? assigneeId,
  }) => IssueQuickCreateSeed(
    projects: _boardProjects(view),
    // On a merged board the column carries one state per spanned project, so
    // resolve the one belonging to the project the ticket lands in.
    stateFor: (project) => column.states.isEmpty
        ? null
        : column.states.firstWhere(
            (s) => project.stateNames.any(
              (own) => own.toLowerCase() == s.toLowerCase(),
            ),
            orElse: () => column.states.first,
          ),
    // Only a sprint the user explicitly selected: the wall is then that
    // sprint's, so a ticket written on it belongs there. With no selection the
    // wall isn't sprint-scoped and the ticket must not silently join one.
    sprintId: _pickedSprintId,
    parentId: parentId,
    forcedType: forcedType,
    assigneeId: assigneeId,
    assigneeName: assigneeId == null ? null : people.names[assigneeId],
    assigneeAvatarUrl: assigneeId == null ? null : people.avatars[assigneeId],
  );

  void _onQuickCreated(Issue created) {
    _facetsStale = true;
    _timelineQuery = null;
    unawaited(_wall.refresh());
  }

  /// The parent to pre-fill when creating an issue inside a swimlane: the
  /// lane's epic under the epic grouping, the lane's parent issue under the
  /// sub-task grouping — never the catch-all "none" lane.
  String? _laneParentId(BoardLane lane) {
    if (lane.key == kBoardLaneNoneKey) return null;
    return switch (_grouping) {
      BoardGrouping.epic || BoardGrouping.subtask => lane.key,
      _ => null,
    };
  }

  Future<void> _openFilter(
    BoardWallState wall,
    BoardPeople people,
    Rect? anchor,
  ) async {
    if (_facetsStale) await _loadFacets(wall);
    if (!mounted) return;
    await openBoardFilter(
      context,
      anchor: anchor,
      filter: _filter,
      options: BoardFilterOptions.fromFacets(
        _facets,
        boardSprints: wall.sprints,
        projectLabels: _projectLabels,
        epicIds: _epics(wall).map((e) => e.id),
      ),
      names: people.names,
      avatars: people.avatars,
      pronouns: people.pronouns,
      sprintNames: _sprintNames(wall),
      epicNames: _epicNames(wall),
      onChanged: (f) {
        setState(() => _filter = f);
        _narrow();
      },
    );
  }

  /// The server searches; the wall keeps its cards until the answer is there.
  void _onSearch(String value) {
    setState(() => _query = value);
    _narrow();
  }

  void _onGrouping(BoardGrouping grouping) {
    final shapeChanges =
        (grouping == BoardGrouping.subtask) !=
        (_grouping == BoardGrouping.subtask);
    setState(() => _grouping = grouping);
    if (shapeChanges) _narrow();
  }

  void _pickSprint(String? sprintId) {
    setState(() => _pickedSprintId = sprintId);
    _facetsStale = true;
    unawaited(_wall.showSprint(sprintId));
  }

  // ---- timeline ----

  /// Switches view, pulling the timeline's pages and the link graph in the
  /// first time the timeline is shown — the wall draws neither.
  void _switchMode(BoardViewMode mode) {
    setState(() => _mode = mode);
    if (mode == BoardViewMode.timeline) {
      _showTimeline(_wall.state);
      _loadLinks();
    }
  }

  /// Reads the timeline's first pages for the wall's sprint, search and filter,
  /// unless they are the ones on screen already.
  void _showTimeline(BoardWallState wall) {
    final board = wall.board;
    if (board == null) return;
    final query = wall.query.withShape(BoardCardShape.timeline);
    if (_datedPages != null &&
        query == _timelineQuery &&
        wall.sprintId == _timelineSprintId) {
      return;
    }
    _closeTimeline();
    _timelineQuery = query;
    _timelineSprintId = wall.sprintId;
    final repository = context.read<BoardRepository>();
    PagedCubit<Issue> pages({required bool dated}) {
      final pages = PagedCubit<Issue>(
        (page, size) async {
          final result = await repository.cards(
            board.id,
            sprintId: wall.sprintId,
            dated: dated,
            page: page,
            size: size,
            query: query,
          );
          return (items: result.items, total: result.total);
        },
        pageSize: kBoardMaxPageSize,
        keyOf: (issue) => issue.id,
      );
      unawaited(pages.load());
      return pages;
    }

    setState(() {
      _datedPages = pages(dated: true);
      _undatedPages = pages(dated: false);
    });
    if (!_linksLoaded) _loadLinks();
  }

  void _closeTimeline() {
    _datedPages?.close();
    _undatedPages?.close();
    _datedPages = null;
    _undatedPages = null;
  }

  Future<void> _loadLinks() async {
    final board = _wall.state.board;
    if (_linksLoaded || _linksLoading || board == null) return;
    _linksLoading = true;
    final repository = context.read<ProjectRepository>();
    try {
      final lists = await Future.wait(
        board.projectIds.map(repository.ganttLinks),
      );
      if (!mounted) return;
      setState(() {
        _links = [for (final list in lists) ...list];
        _linksLoaded = true;
      });
    } on ApiFailure {
      // Connectors are an overlay on a chart that already renders — a failed
      // graph must not take the board down with it.
    } finally {
      _linksLoading = false;
    }
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) => BlocProvider<BoardWallCubit>.value(
    value: _wall,
    child: BlocConsumer<BoardWallCubit, BoardWallState>(
      listenWhen: _wallChanged,
      listener: _onWall,
      builder: _screen,
    ),
  );

  Widget _screen(BuildContext context, BoardWallState wall) {
    final view = wall.view;
    if (view == null) {
      if (wall.status == BoardWallStatus.failure) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.t(wall.errorKey ?? 'errors.unexpected'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _wall.load,
                child: Text(context.t('common.retry')),
              ),
            ],
          ),
        );
      }
      return const Center(child: HiveLoader());
    }
    // Scrum boards swap the Kanban/Timeline surfaces for the sprint planning ·
    // active · insights surfaces. The sprint view reads its own planning and
    // report and owns its head; its active sprint is this screen's wall.
    if (view.board.isScrum) {
      return ScrumBoardView(
        view: view,
        fullWidth: _needsFullWidth(view),
        projectNames: _projectNames,
        projectsById: _projectsById,
        onOpenIssue: _openIssue,
      );
    }
    final people = _people(wall);
    final compact = context.isCompact;
    final sprint = _activeSprint(wall);
    // Back navigation is handled by the shell app bar (via PageChrome). On a
    // phone the board's name is that bar's title and the tools ride in the row
    // docked under it, so the wall starts right below the bar and its lanes
    // scroll up under the blur. A wide window keeps the page head, which
    // carries the name, so its bar names the section instead.
    return PageChrome(
      title: compact ? view.board.name : context.t('nav.board'),
      titleLeading: true,
      fullWidth: _needsFullWidth(view),
      bottom: compact ? _dock(wall, people) : null,
      bottomHeight: compact ? kBoardDockHeight : 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact)
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.pageGutter,
                22 + context.topGutter,
                context.pageGutter,
                10,
              ),
              child: _wideHead(view),
            ),
          if (sprint != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.pageGutter,
                compact ? context.topGutter + 8 : 0,
                context.pageGutter,
                10,
              ),
              child: _sprintRow(wall, sprint),
            ),
          if (!compact)
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.pageGutter,
                0,
                context.pageGutter,
                10,
              ),
              child: _wideControls(wall, people),
            ),
          Expanded(
            // A search or a filter being read dims the cards it may replace,
            // rather than blanking the wall.
            child: AnimatedOpacity(
              opacity: wall.refreshing ? 0.6 : 1,
              duration: const Duration(milliseconds: 160),
              child: _body(wall, people),
            ),
          ),
        ],
      ),
    );
  }

  /// Whether this board should break out of the page's reading width.
  ///
  /// Only when its wall would otherwise not fit: up to
  /// [BoardWall.columnsPerReadingWidth] columns the board is an ordinary page
  /// and stays where every other page is — widening it would stretch the header
  /// across a screen the wall doesn't fill. The count is the board's own, so a
  /// Scrum board that hides a backlog column may widen one column early; that
  /// costs empty canvas, never a broken layout.
  bool _needsFullWidth(BoardView view) =>
      view.columns.length > BoardWall.columnsPerReadingWidth;

  /// What the body leaves clear at its top. On a phone with no sprint card
  /// above it the wall spends the bar's height itself, so its lanes scroll up
  /// under the blur instead of stopping at the bar's edge.
  double _bodyTop(BoardWallState wall) =>
      context.isCompact && _activeSprint(wall) == null
      ? context.topGutter + 8
      : 0;

  // ---- head: name, views, tools ----

  Widget _wideHead(BoardView view) {
    final projectLabel = view.board.projectIds
        .map((id) => _projectNames[id] ?? '')
        .where((s) => s.isNotEmpty)
        .join(', ');
    final subtitle = projectLabel.isEmpty
        ? context.t('board.agileBoard')
        : '$projectLabel · ${context.t('board.agileBoard')}';
    return PageHead(
      title: view.board.name,
      subtitle: subtitle,
      actions: [_viewSwitch(compact: false)],
    );
  }

  /// The phone's one docked row: the views, the search and the board's tools.
  Widget _dock(BoardWallState wall, BoardPeople people) => BoardHeaderDock(
    switcher: _viewSwitch(compact: true),
    searching: _searching,
    searchController: _searchController,
    onSearchChanged: _onSearch,
    onSearchOpen: () => setState(() => _searching = true),
    onSearchClose: () => setState(() => _searching = false),
    tools: [
      if (_mode == BoardViewMode.board) _groupBy(wall),
      _filterPill(wall, people),
      if (_facets.assigneeIds.isNotEmpty) _peopleStrip(people),
    ],
  );

  /// The same tools on a wide window: the search as a field on the leading
  /// edge, the people's faces, grouping and the filter against the trailing
  /// one, wrapping to the room the window leaves them.
  Widget _wideControls(BoardWallState wall, BoardPeople people) => WideToolbar(
    leading: [
      BoardSearchField(controller: _searchController, onChanged: _onSearch),
    ],
    trailing: [
      if (_facets.assigneeIds.isNotEmpty)
        BoardPeopleSlot(child: _peopleStrip(people)),
      if (_mode == BoardViewMode.board) _groupBy(wall),
      _filterPill(wall, people, showLabel: true),
    ],
  );

  Widget _viewSwitch({required bool compact}) => BoardViewSwitch(
    compact: compact,
    items: [for (final mode in BoardViewMode.values) _itemFor(mode)],
    selected: _mode.index,
    onChanged: (i) => _switchMode(BoardViewMode.values[i]),
  );

  /// Grouping lays the wall out in lanes, so it is offered on the wall only.
  Widget _groupBy(BoardWallState wall) => BoardGroupByButton(
    value: _grouping,
    options: boardGroupingsFor(
      crossProject: wall.view != null && _isCrossProject(wall.view!),
    ),
    onChanged: _onGrouping,
  );

  Widget _filterPill(
    BoardWallState wall,
    BoardPeople people, {
    bool showLabel = false,
  }) => BoardFilterPill(
    count: _filter.activeCount,
    showLabel: showLabel,
    onTap: (anchor) => unawaited(_openFilter(wall, people, anchor)),
  );

  Widget _peopleStrip(BoardPeople people) => BoardPeopleStrip(
    userIds: _facets.assigneeIds,
    names: people.names,
    avatars: people.avatars,
    pronouns: people.pronouns,
    selected: _filter.assignees,
    onToggle: (id) {
      setState(() => _filter = _filter.toggle(BoardFilterFacet.assignee, id));
      _narrow();
    },
  );

  /// The sprint the wall shows, and the way to another one.
  Widget _sprintRow(BoardWallState wall, Sprint sprint) => Row(
    children: [
      Expanded(child: _SprintHeader(sprint: sprint)),
      if (wall.sprints.length > 1) ...[
        const SizedBox(width: 12),
        _SprintSelector(
          sprints: wall.sprints,
          selected: _pickedSprintId,
          onChanged: _pickSprint,
        ),
      ],
    ],
  );

  SegmentItem _itemFor(BoardViewMode mode) => switch (mode) {
    BoardViewMode.board => SegmentItem(
      label: context.t('board.view.board'),
      icon: LucideIcons.squareKanban,
    ),
    BoardViewMode.timeline => SegmentItem(
      label: context.t('board.view.timeline'),
      icon: LucideIcons.waypoints,
    ),
  };

  // ---- body ----

  Widget _body(BoardWallState wall, BoardPeople people) => switch (_mode) {
    BoardViewMode.board => _kanban(wall, people),
    BoardViewMode.timeline => _timeline(wall),
  };

  /// The timeline is roadmap-like, so epics stay (they carry date ranges);
  /// sub-tasks are nested detail and don't belong on it. The server leaves them
  /// out and pages the rest: the cards with a date first, then those without.
  Widget _timeline(BoardWallState wall) {
    final dated = _datedPages;
    final undated = _undatedPages;
    if (dated == null || undated == null) {
      return const Center(child: HiveLoader());
    }
    return BlocBuilder<PagedCubit<Issue>, PagedState<Issue>>(
      bloc: dated,
      builder: (context, datedPages) =>
          BlocBuilder<PagedCubit<Issue>, PagedState<Issue>>(
            bloc: undated,
            builder: (context, undatedPages) {
              final failure = datedPages.errorKey ?? undatedPages.errorKey;
              if (failure != null &&
                  (!datedPages.hasData || !undatedPages.hasData)) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.t(failure),
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () {
                          _timelineQuery = null;
                          _showTimeline(_wall.state);
                        },
                        child: Text(context.t('common.retry')),
                      ),
                    ],
                  ),
                );
              }
              if (!datedPages.hasData || !undatedPages.hasData) {
                return const Center(child: HiveLoader());
              }
              return BoardTimeline(
                issues: [...datedPages.items, ...undatedPages.items],
                links: _links,
                onOpen: _openIssue,
                onNearEnd: datedPages.hasMore
                    ? dated.loadMore
                    : undatedPages.hasMore
                    ? undated.loadMore
                    : null,
                padding: EdgeInsets.fromLTRB(
                  context.pageGutter,
                  _bodyTop(wall),
                  context.pageGutter,
                  context.pageGutter + context.bottomGutter,
                ),
              );
            },
          ),
    );
  }

  Widget _kanban(BoardWallState wall, BoardPeople people) {
    final view = wall.view!;
    final columns = wall.columns;
    if (columns.isEmpty) {
      return Center(
        child: Text(
          context.t('board.empty'),
          style: TextStyle(color: AppColors.inkSoft),
        ),
      );
    }
    if (_grouping != BoardGrouping.none) {
      return _groupedBoard(wall, people);
    }
    // The wall sizes its columns to the space it actually got, so a board with
    // more columns than fit at the design width still shows all of them where
    // there is room. Hence LayoutBuilder rather than the screen width — the
    // rail and the page gutters are already taken out here.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = boardColumnWidth(
          constraints.maxWidth - context.pageGutter * 2,
          columns.length,
        );
        // The horizontal controller lets a carried card pull the wall along
        // when it reaches an edge, so an off-screen column is still reachable
        // mid-drag.
        final snap = boardSnapStride(context, columnWidth: width);
        return BoardDragScroller(
          snapStride: snap,
          builder: (context, _, horizontal) => ListView.separated(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            physics: BoardColumnSnapPhysics.maybe(snap),
            padding: EdgeInsets.fromLTRB(
              context.pageGutter,
              _bodyTop(wall),
              context.pageGutter,
              context.pageGutter + context.bottomGutter,
            ),
            itemCount: columns.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: BoardWall.columnGap),
            itemBuilder: (context, index) {
              final column = columns[index];
              return _BoardColumn(
                column: column,
                width: width,
                issues: column.issues,
                palette: _palette,
                names: people.names,
                avatars: people.avatars,
                pronouns: people.pronouns,
                projectsById: _projectsById,
                onAccept: (issue) => _moveIssue(issue, column),
                canAccept: (issue) => _canDrop(issue, column),
                quickCreate: _quickCreateSeed(view, people, column),
                onCreated: _onQuickCreated,
                onOpenIssue: _openIssue,
                loadingMore: wall.loadingMore.contains(column.name),
                onLoadMore: column.hasMore
                    ? () => _wall.loadMore(column.name)
                    : null,
              );
            },
          ),
        );
      },
    );
  }

  // ---- swimlanes (grouped board) ----

  /// Renders the grouped board via the shared [BoardSwimlanes]: lanes per the
  /// active grouping over the cards loaded so far, each lane carrying the full
  /// column set and its own collapse toggle, and under them the way to every
  /// column's cards that are not loaded yet.
  Widget _groupedBoard(BoardWallState wall, BoardPeople people) {
    final view = wall.view!;
    final lanes = computeBoardLanes(
      context: context,
      grouping: _grouping,
      issues: wall.cards,
      issuesById: _issuesById(wall),
      epics: _epics(wall),
      names: people.names,
      avatars: people.avatars,
      pronouns: people.pronouns,
      palette: _palette,
      projectNames: _projectNames,
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
      columns: wall.columns,
      lanes: lanes,
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        _bodyTop(wall),
        context.pageGutter,
        context.pageGutter + context.bottomGutter,
      ),
      columnBuilder: (column, issues, lane, width) => _BoardColumn(
        column: column,
        laneMode: true,
        width: width,
        issues: issues,
        palette: _palette,
        names: people.names,
        avatars: people.avatars,
        pronouns: people.pronouns,
        projectsById: _projectsById,
        onAccept: (issue) => _moveIssue(issue, column),
        canAccept: (issue) => _canDrop(issue, column),
        quickCreate: _quickCreateSeed(
          view,
          people,
          column,
          parentId: _laneParentId(lane),
          // A sub-task lane's parent is a standard issue, so the only valid
          // child there is a sub-task.
          forcedType:
              _grouping == BoardGrouping.subtask &&
                  lane.key != kBoardLaneNoneKey
              ? 'SUBTASK'
              : null,
          // The assignee lane's user pre-fills the assignee (still editable).
          assigneeId:
              _grouping == BoardGrouping.assignee &&
                  lane.key != kBoardLaneNoneKey
              ? lane.key
              : null,
        ),
        onCreated: _onQuickCreated,
        onOpenIssue: _openIssue,
      ),
      footerBuilder: (column, width) => column.hasMore
          ? BoardLoadMore(
              remaining: column.count - column.issues.length,
              loading: wall.loadingMore.contains(column.name),
              onPressed: () => _wall.loadMore(column.name),
            )
          : null,
    );
  }
}
