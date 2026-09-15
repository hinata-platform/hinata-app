import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/events/issue_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/board_page_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/board_repository.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/project_palette.dart';
import '../../core/widgets/glass_filter_bar.dart' show WideToolbar;
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/subtask_widgets.dart';
import '../issues/issue_detail_sheet.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart' show showGlassErrorToast;
import '../sprint/sprint_board_view.dart';
import 'board_card_list.dart';
import 'board_drag.dart';
import 'board_feedback.dart';
import 'board_header.dart';
import 'board_people_strip.dart';
import 'board_swimlanes.dart';
import 'board_timeline.dart';
import 'head/board_head.dart';
import 'head/board_head_cubit.dart';
import 'issue_quick_create.dart';
import 'timeline/board_timeline_cubit.dart';
import 'wall/board_wall_columns.dart';
import 'wall/board_wall_cubit.dart';

part 'board_screen.header.dart';
part 'board_screen.cards.dart';

// ─────────────────────────── KanbanBoardScreen ────────────────────────────
// Shown at /boards/:id — one board: a Kanban wall and its timeline, or the
// Scrum planning, active sprint and insights.

class KanbanBoardScreen extends StatefulWidget {
  const KanbanBoardScreen({super.key, required this.boardId});

  final String boardId;

  @override
  State<KanbanBoardScreen> createState() => _KanbanBoardScreenState();
}

/// Which view the kanban screen is showing.
enum BoardViewMode { board, timeline }

/// What both kinds of board share: the wall, read page by page and narrowed on
/// the server, the head, and the board's projects. Once the wall says which
/// kind the board is, the Kanban or the Scrum view takes over.
class _KanbanBoardScreenState extends State<KanbanBoardScreen> {
  late final BoardWallCubit _wall = BoardWallCubit(
    boards: context.read<BoardRepository>(),
    issues: context.read<IssueRepository>(),
    boardId: widget.boardId,
  );

  late final BoardHeadCubit _head = BoardHeadCubit(
    boards: context.read<BoardRepository>(),
    boardId: widget.boardId,
  );

  /// The board's own projects by id, fetched once the wall names them. A
  /// cross-project board needs the full project, not just its name, to answer
  /// "which of this column's states does this card's project have?" on a drop.
  Map<String, Project> _projectsById = const {};
  Map<String, String> _projectNames = const {};
  ProjectPalette _palette = ProjectPalette.empty;
  List<String> _projectIdsLoaded = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_wall.load());
  }

  @override
  void dispose() {
    _wall.close();
    _head.close();
    super.dispose();
  }

  void _onWall(BuildContext context, BoardWallState wall) {
    final board = wall.board;
    if (board != null && !listEquals(board.projectIds, _projectIdsLoaded)) {
      unawaited(_loadProjects(board.projectIds));
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
        _projectNames = {for (final p in projects) p.id: p.name};
        _palette = ProjectPalette.fromProjects(projects);
      });
    } on ApiFailure {
      // Names and colours fall back to plain ones until the next read; the
      // wall itself reads without them.
      _projectIdsLoaded = const [];
    }
  }

  /// No `onChanged` here on purpose: the detail sheet broadcasts every change
  /// on [IssueEvents], which the board's views already listen to. Passing both
  /// would read the board twice per edit.
  void _openIssue(Issue issue) =>
      showIssueDetailSheet(context, issueId: issue.id);

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider<BoardWallCubit>.value(value: _wall),
      BlocProvider<BoardHeadCubit>.value(value: _head),
    ],
    child: BlocConsumer<BoardWallCubit, BoardWallState>(
      listenWhen: (previous, next) =>
          previous.board != next.board ||
          previous.refreshing != next.refreshing ||
          previous.errorKey != next.errorKey,
      listener: _onWall,
      buildWhen: (previous, next) =>
          previous.status != next.status ||
          previous.board != next.board ||
          previous.columns.length != next.columns.length,
      builder: _view,
    ),
  );

  Widget _view(BuildContext context, BoardWallState wall) {
    final board = wall.board;
    if (board == null) {
      return wall.status == BoardWallStatus.failure
          ? BoardErrorRetry(
              message: context.t(wall.errorKey ?? 'errors.unexpected'),
              onRetry: _wall.load,
            )
          : const Center(child: HiveLoader());
    }
    // A board breaks out of the page's reading width only when its wall would
    // otherwise not fit. Up to [BoardWall.columnsPerReadingWidth] columns it
    // is an ordinary page and stays where every other page is; widening it
    // would stretch the header across a screen the wall doesn't fill. The count
    // is the board's own, so a Scrum board that hides a backlog column may
    // widen one column early; that costs empty canvas, never a broken layout.
    final fullWidth = wall.columns.length > BoardWall.columnsPerReadingWidth;
    if (board.isScrum) {
      return ScrumBoardView(
        board: board,
        fullWidth: fullWidth,
        projectNames: _projectNames,
        projectsById: _projectsById,
        onOpenIssue: _openIssue,
      );
    }
    return _KanbanView(
      board: board,
      fullWidth: fullWidth,
      projectNames: _projectNames,
      projectsById: _projectsById,
      palette: _palette,
      onOpenIssue: _openIssue,
    );
  }
}

/// A Kanban board: its wall of columns, laid out in lanes when grouped, and
/// its timeline.
class _KanbanView extends StatefulWidget {
  const _KanbanView({
    required this.board,
    required this.fullWidth,
    required this.projectNames,
    required this.projectsById,
    required this.palette,
    required this.onOpenIssue,
  });

  final AgileBoard board;
  final bool fullWidth;
  final Map<String, String> projectNames;
  final Map<String, Project> projectsById;
  final ProjectPalette palette;
  final void Function(Issue) onOpenIssue;

  @override
  State<_KanbanView> createState() => _KanbanViewState();
}

class _KanbanViewState extends State<_KanbanView>
    with BoardHeadHost<_KanbanView> {
  late final BoardWallCubit _wall = context.read<BoardWallCubit>();

  @override
  late final BoardHeadCubit head = context.read<BoardHeadCubit>();

  late final BoardTimelineCubit _timeline = BoardTimelineCubit(
    boards: context.read<BoardRepository>(),
    boardId: widget.board.id,
  );

  BoardViewMode _mode = BoardViewMode.board;

  /// Whether the wall missed a change while the timeline was on screen, to be
  /// read again once the wall is back.
  bool _wallStale = false;

  final BoardPeopleMemo _people = BoardPeopleMemo();
  Object? _issuesByIdKey;
  Map<String, Issue> _issuesById = const {};

  /// Reads again what is on screen when an issue is created or changed
  /// elsewhere (e.g. the global nav-rail "new issue" button, which can't reach
  /// this screen's state).
  StreamSubscription<void>? _issueSub;

  @override
  void initState() {
    super.initState();
    _issueSub = IssueEvents.instance.changes.listen((_) => _changedElsewhere());
    // The faces want their facets from the start, and the wall may have
    // arrived before this view did.
    unawaited(head.ensureFacets(_facetsScope(_wall.state)));
  }

  @override
  void dispose() {
    _issueSub?.cancel();
    _timeline.close();
    super.dispose();
  }

  void _changedElsewhere() {
    head.facetsChanged();
    if (_mode == BoardViewMode.timeline) {
      _timeline.refreshSoon();
      _wallStale = true;
    } else {
      _wall.refreshSoon();
      _timeline.changed();
    }
  }

  BoardFacetsScope _facetsScope(BoardWallState wall) =>
      BoardFacetsScope(sprintId: wall.sprintId, shape: head.state.wallShape);

  // ---- reacting to reads and to the head ----

  /// A read of the wall arrived.
  bool _wallRead(BoardWallState previous, BoardWallState next) =>
      next.status == BoardWallStatus.ready &&
      !next.refreshing &&
      (previous.refreshing ||
          previous.status != next.status ||
          previous.sprintId != next.sprintId);

  void _onWallRead(BuildContext context, BoardWallState wall) {
    unawaited(head.ensureFacets(_facetsScope(wall)));
    // The timeline follows the sprint the wall shows.
    if (_mode == BoardViewMode.timeline) _showTimeline(wall);
  }

  /// The search, the filter or the grouping changed: the view on screen reads
  /// the cards they narrow to, the other one once it is shown.
  void _onNarrowed(BuildContext context, BoardHeadState state) {
    switch (_mode) {
      case BoardViewMode.board:
        _wall.narrow(state.query(state.wallShape));
      case BoardViewMode.timeline:
        _showTimeline(_wall.state);
    }
  }

  void _onTimelineFailed(BuildContext context, BoardTimelineState timeline) {
    final errorKey = timeline.errorKey;
    // A timeline that never arrived says so in its place instead.
    if (errorKey != null && timeline.status == BoardTimelineStatus.ready) {
      showGlassErrorToast(context, context.t(errorKey));
    }
  }

  // ---- derived views ----

  /// The loaded cards and what they refer to, by id: what lanes resolve a
  /// sub-task's parent from.
  Map<String, Issue> _issuesByIdOf(BoardWallState wall) {
    final key = (wall.refs, wall.columns);
    if (key != _issuesByIdKey) {
      _issuesByIdKey = key;
      _issuesById = {
        ...wall.refs,
        for (final card in wall.cards) card.id: card,
      };
    }
    return _issuesById;
  }

  Sprint? _activeSprint(BoardWallState wall) {
    final id = wall.sprintId;
    if (id == null) return null;
    return wall.sprints.where((s) => s.id == id).firstOrNull;
  }

  /// Whether this board spans more than one project — the signal that turns on
  /// the cross-project affordances (column ownership marks, project swimlane).
  bool get _crossProject => widget.board.projectIds.length > 1;

  /// Whether [column] is a legal drop for [issue] — a different column that
  /// carries a workflow state this card's own project actually defines. Drives
  /// the drop affordance, so an impossible move is refused while the card is
  /// still in the air instead of ending in an error toast.
  bool _canDrop(Issue issue, BoardColumnView column) =>
      column.states.isNotEmpty &&
      !column.states.contains(issue.state) &&
      boardDropState(issue, column.states, widget.projectsById) != null;

  /// Moves the card on the wall at once; a refusal puts it back, and the wall
  /// raises the reason as a toast.
  Future<void> _moveIssue(Issue issue, BoardColumnView column) async {
    if (column.states.contains(issue.state) || column.states.isEmpty) return;
    final target = boardDropState(issue, column.states, widget.projectsById);
    if (target == null) {
      showGlassErrorToast(context, context.t('board.dropNotInWorkflow'));
      return;
    }
    if (target == issue.state) return;
    // The card settles in visibly at its new home: the tail end of the drag,
    // not a separate effect.
    boardDrag.land(issue.id);
    if (await _wall.move(issue, column.name, target) != null) return;
    // The filter may offer a state it did not before, and the timeline draws
    // the card's state.
    head.facetsChanged();
    _timeline.changed();
  }

  /// The board's projects in board order — what a column's inline composer may
  /// create into. More than one only on a merged board, where the composer
  /// shows a project control instead of silently picking the first.
  List<Project> get _boardProjects => [
    for (final id in widget.board.projectIds) ?widget.projectsById[id],
  ];

  /// Seeds the inline composer at the foot of [column]: the column's project(s)
  /// and workflow state, plus whatever the surrounding swimlane implies.
  IssueQuickCreateSeed _quickCreateSeed(
    BoardWallState wall,
    BoardPeople people,
    BoardColumnView column, {
    String? parentId,
    String? forcedType,
    String? assigneeId,
  }) => IssueQuickCreateSeed(
    projects: _boardProjects,
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
    // Only a sprint the user explicitly picked: the wall is then that sprint's,
    // so a ticket written on it belongs there. With no pick the wall isn't
    // sprint-scoped and the ticket must not silently join one.
    sprintId: wall.pickedSprintId,
    parentId: parentId,
    forcedType: forcedType,
    assigneeId: assigneeId,
    assigneeName: assigneeId == null ? null : people.names[assigneeId],
    assigneeAvatarUrl: assigneeId == null ? null : people.avatars[assigneeId],
  );

  void _onQuickCreated(Issue created) {
    head.facetsChanged();
    _timeline.changed();
    unawaited(_wall.refresh());
  }

  /// The parent to pre-fill when creating an issue inside a swimlane: the
  /// lane's epic under the epic grouping, the lane's parent issue under the
  /// sub-task grouping — never the catch-all "none" lane.
  String? _laneParentId(BoardLane lane, BoardGrouping grouping) {
    if (lane.key == kBoardLaneNoneKey) return null;
    return switch (grouping) {
      BoardGrouping.epic || BoardGrouping.subtask => lane.key,
      _ => null,
    };
  }

  Future<void> _openFilter(Rect? anchor) {
    final wall = _wall.state;
    return openHeadFilter(
      scope: _facetsScope(wall),
      anchor: anchor,
      sprints: wall.sprints,
      projects: widget.projectsById.values,
      refs: wall.refs.values,
      users: wall.users.values,
    );
  }

  void _openFilterAt(Rect? anchor) => unawaited(_openFilter(anchor));

  void _pickSprint(String? sprintId) => unawaited(_wall.showSprint(sprintId));

  // ---- views ----

  /// Switches view. The view coming back reads what changed while it was away:
  /// the search or filter set meanwhile, or a change made elsewhere.
  void _switchMode(BoardViewMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    switch (mode) {
      case BoardViewMode.timeline:
        _showTimeline(_wall.state);
      case BoardViewMode.board:
        final state = head.state;
        final query = state.query(state.wallShape);
        if (query != _wall.requestedQuery) {
          _wall.narrow(query);
        } else if (_wallStale) {
          unawaited(_wall.refresh());
        }
        _wallStale = false;
    }
  }

  /// Shows the timeline of the wall's sprint for the head's search and filter.
  void _showTimeline(BoardWallState wall) => unawaited(
    _timeline.show(
      sprintId: wall.sprintId,
      query: head.state.query(BoardCardShape.timeline),
    ),
  );

  // ---- build ----

  @override
  Widget build(BuildContext context) => MultiBlocListener(
    listeners: [
      BlocListener<BoardWallCubit, BoardWallState>(
        listenWhen: _wallRead,
        listener: _onWallRead,
      ),
      BlocListener<BoardHeadCubit, BoardHeadState>(
        listenWhen: (previous, next) => next.narrowsOtherThan(previous),
        listener: _onNarrowed,
      ),
      BlocListener<BoardTimelineCubit, BoardTimelineState>(
        bloc: _timeline,
        listenWhen: (previous, next) => previous.errorKey != next.errorKey,
        listener: _onTimelineFailed,
      ),
    ],
    child: BlocBuilder<BoardHeadCubit, BoardHeadState>(
      buildWhen: (previous, next) => next.drawsOtherThan(previous),
      builder: (context, headState) =>
          BlocBuilder<BoardWallCubit, BoardWallState>(
            // The columns pick up their own cards; see [BoardWallColumns].
            buildWhen: boardWallReshaped,
            builder: (context, wall) => _page(wall, headState),
          ),
    ),
  );

  Widget _page(BoardWallState wall, BoardHeadState headState) {
    final compact = context.isCompact;
    final sprint = _activeSprint(wall);
    final people = _people.of(wall.users, headState.facets.users);
    // Back navigation is handled by the shell app bar (via PageChrome). On a
    // phone the board's name is that bar's title and the tools ride in the row
    // docked under it, so the wall starts right below the bar and its lanes
    // scroll up under the blur. A wide window keeps the page head, which
    // carries the name, so its bar names the section instead.
    return PageChrome(
      title: compact ? widget.board.name : context.t('nav.board'),
      titleLeading: true,
      fullWidth: widget.fullWidth,
      bottom: compact ? _dock(headState) : null,
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
              child: _wideHead(),
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
              child: _wideControls(headState),
            ),
          Expanded(child: _body(wall, headState, people)),
        ],
      ),
    );
  }

  /// What the body leaves clear at its top. On a phone with no sprint card
  /// above it the wall spends the bar's height itself, so its lanes scroll up
  /// under the blur instead of stopping at the bar's edge.
  double _bodyTop(BoardWallState wall) =>
      context.isCompact && _activeSprint(wall) == null
      ? context.topGutter + 8
      : 0;

  EdgeInsets _bodyPadding(BoardWallState wall) => EdgeInsets.fromLTRB(
    context.pageGutter,
    _bodyTop(wall),
    context.pageGutter,
    context.pageGutter + context.bottomGutter,
  );

  // ---- head: name, views, tools ----

  Widget _wideHead() {
    final projectLabel = widget.board.projectIds
        .map((id) => widget.projectNames[id] ?? '')
        .where((s) => s.isNotEmpty)
        .join(', ');
    final subtitle = projectLabel.isEmpty
        ? context.t('board.agileBoard')
        : '$projectLabel · ${context.t('board.agileBoard')}';
    return PageHead(
      title: widget.board.name,
      subtitle: subtitle,
      actions: [_viewSwitch(compact: false)],
    );
  }

  /// The phone's one docked row: the views, the search and the board's tools.
  Widget _dock(BoardHeadState headState) => headDock(
    switcher: _viewSwitch(compact: true),
    tools: [
      if (_mode == BoardViewMode.board)
        headGroupBy(headState, crossProject: _crossProject),
      headFilterPill(headState, onOpen: _openFilterAt),
      ?headPeople(headState),
    ],
  );

  /// The same tools on a wide window: the search as a field on the leading
  /// edge, the people's faces, grouping and the filter against the trailing
  /// one, wrapping to the room the window leaves them.
  Widget _wideControls(BoardHeadState headState) {
    final people = headPeople(headState);
    return WideToolbar(
      leading: [headSearchField()],
      trailing: [
        if (people != null) BoardPeopleSlot(child: people),
        if (_mode == BoardViewMode.board)
          headGroupBy(headState, crossProject: _crossProject),
        headFilterPill(headState, onOpen: _openFilterAt, showLabel: true),
      ],
    );
  }

  Widget _viewSwitch({required bool compact}) => BoardViewSwitch(
    compact: compact,
    items: [for (final mode in BoardViewMode.values) _itemFor(mode)],
    selected: _mode.index,
    onChanged: (i) => _switchMode(BoardViewMode.values[i]),
  );

  /// The sprint the wall shows, and the way to another one.
  Widget _sprintRow(BoardWallState wall, Sprint sprint) => Row(
    children: [
      Expanded(child: _SprintHeader(sprint: sprint)),
      if (wall.sprints.length > 1) ...[
        const SizedBox(width: 12),
        _SprintSelector(
          sprints: wall.sprints,
          selected: wall.pickedSprintId,
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

  Widget _body(
    BoardWallState wall,
    BoardHeadState headState,
    BoardPeople people,
  ) => switch (_mode) {
    BoardViewMode.board => BoardWallDimmed(
      child: headState.grouping == BoardGrouping.none
          ? _flatWall(wall, people)
          : _lanes(headState, people),
    ),
    BoardViewMode.timeline => _timelineBody(wall),
  };

  Widget _emptyWall() => Center(
    child: Text(
      context.t('board.empty'),
      style: TextStyle(color: AppColors.inkSoft),
    ),
  );

  /// The timeline is roadmap-like, so epics stay (they carry date ranges);
  /// sub-tasks are nested detail and don't belong on it. The server leaves them
  /// out and pages the rest: the cards with a date first, then those without.
  Widget _timelineBody(BoardWallState wall) =>
      BlocBuilder<BoardTimelineCubit, BoardTimelineState>(
        bloc: _timeline,
        builder: (context, timeline) => switch (timeline.status) {
          BoardTimelineStatus.idle ||
          BoardTimelineStatus.loading => const Center(child: HiveLoader()),
          BoardTimelineStatus.failure => BoardErrorRetry(
            message: context.t(timeline.errorKey ?? 'errors.unexpected'),
            onRetry: () => _showTimeline(_wall.state),
          ),
          BoardTimelineStatus.ready => BoardDimmed(
            dimmed: timeline.refreshing,
            child: BoardTimeline(
              issues: timeline.issues,
              links: timeline.links,
              onOpen: widget.onOpenIssue,
              onNearEnd: timeline.hasMore ? _timeline.loadMore : null,
              padding: _bodyPadding(wall),
            ),
          ),
        },
      );

  /// The wall's columns side by side, each following its own cards.
  Widget _flatWall(BoardWallState wall, BoardPeople people) {
    if (wall.columns.isEmpty) return _emptyWall();
    return BoardWallColumns(
      names: [for (final column in wall.columns) column.name],
      padding: _bodyPadding(wall),
      columnBuilder: (context, slice, width) {
        final column = slice.column;
        return _BoardColumn(
          column: column,
          width: width,
          issues: column.issues,
          palette: widget.palette,
          names: people.names,
          avatars: people.avatars,
          pronouns: people.pronouns,
          projectsById: widget.projectsById,
          onAccept: (issue) => _moveIssue(issue, column),
          canAccept: (issue) => _canDrop(issue, column),
          quickCreate: _quickCreateSeed(wall, people, column),
          onCreated: _onQuickCreated,
          onOpenIssue: widget.onOpenIssue,
          loadingMore: slice.loadingMore,
          failed: slice.failed,
          onLoadMore: slice.canLoadMore
              ? () => _wall.loadMore(column.name)
              : null,
        );
      },
    );
  }

  // ---- swimlanes (grouped board) ----

  /// Renders the grouped board via the shared [BoardSwimlanes]: lanes per the
  /// active grouping over the cards loaded so far, each lane carrying the full
  /// column set and its own collapse toggle, and under them the way to every
  /// column's cards that are not loaded yet. Laid out from every loaded card,
  /// so it follows every change to them.
  Widget _lanes(BoardHeadState headState, BoardPeople people) =>
      BlocBuilder<BoardWallCubit, BoardWallState>(
        buildWhen: (previous, next) =>
            !identical(previous.columns, next.columns) ||
            !identical(previous.refs, next.refs),
        builder: (context, wall) {
          final grouping = headState.grouping;
          final lanes = computeBoardLanes(
            context: context,
            grouping: grouping,
            issues: wall.cards,
            issuesById: _issuesByIdOf(wall),
            epics: boardEpics(headState.facets.epics, wall.refs.values),
            names: people.names,
            avatars: people.avatars,
            pronouns: people.pronouns,
            palette: widget.palette,
            projectNames: widget.projectNames,
            onOpenIssue: widget.onOpenIssue,
          );
          if (lanes.isEmpty) return _emptyWall();
          return BoardSwimlanes(
            columns: wall.columns,
            lanes: lanes,
            padding: _bodyPadding(wall),
            columnBuilder: (column, issues, lane, width) => _BoardColumn(
              column: column,
              laneMode: true,
              width: width,
              issues: issues,
              palette: widget.palette,
              names: people.names,
              avatars: people.avatars,
              pronouns: people.pronouns,
              projectsById: widget.projectsById,
              onAccept: (issue) => _moveIssue(issue, column),
              canAccept: (issue) => _canDrop(issue, column),
              quickCreate: _quickCreateSeed(
                wall,
                people,
                column,
                parentId: _laneParentId(lane, grouping),
                // A sub-task lane's parent is a standard issue, so the only
                // valid child there is a sub-task.
                forcedType:
                    grouping == BoardGrouping.subtask &&
                        lane.key != kBoardLaneNoneKey
                    ? 'SUBTASK'
                    : null,
                // The assignee lane's user pre-fills the assignee (still
                // editable).
                assigneeId:
                    grouping == BoardGrouping.assignee &&
                        lane.key != kBoardLaneNoneKey
                    ? lane.key
                    : null,
              ),
              onCreated: _onQuickCreated,
              onOpenIssue: widget.onOpenIssue,
            ),
            footerBuilder: (column) => BoardLaneFooter(name: column.name),
          );
        },
      );
}
