import 'dart:async';

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
import '../../core/repositories/sprint_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_filter_bar.dart' show WideToolbar;
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart' show SegmentItem;
import '../board/board_drag.dart';
import '../board/board_feedback.dart';
import '../board/board_header.dart';
import '../board/board_people_strip.dart';
import '../board/board_projects_cubit.dart';
import '../board/board_swimlanes.dart';
import '../board/head/board_head.dart';
import '../board/head/board_head_cubit.dart';
import '../board/issue_quick_create.dart';
import '../board/wall/board_cards_by_id.dart';
import '../board/wall/board_wall_columns.dart';
import '../board/wall/board_wall_cubit.dart';
import '../shell/page_chrome.dart';
import 'modals/complete_sprint_dialog.dart';
import 'modals/create_sprint_dialog.dart';
import 'modals/estimate_dialog.dart';
import 'modals/glass_modal.dart' show GlassToastKind, showGlassToast;
import 'modals/start_sprint_dialog.dart';
import 'planning/sprint_planning_cubit.dart';
import 'sprint_active_surface.dart';
import 'sprint_insights_surface.dart';
import 'sprint_planning_surface.dart';

/// The Scrum board: Planning · Active sprint · Insights, switched by a
/// segmented control.
///
/// The planning is read by its own [SprintPlanningCubit]: the open sprints a
/// page at a time with their heads counted on the server, and the backlog a
/// page at a time. The active sprint is the board screen's wall, which shows
/// the sprint the board runs. The search and the filter in the head narrow the
/// tab on screen on the server, and only that tab reads when something changes;
/// the other one catches up once it is shown.
class ScrumBoardView extends StatefulWidget {
  const ScrumBoardView({
    super.key,
    required this.board,
    this.projects = BoardProjectsState.none,
    required this.onOpenIssue,
    this.fullWidth = false,
  });

  final AgileBoard board;

  /// The board's spanned projects, as far as they have been read: their names,
  /// and on a cross-project board which state of a merged column belongs to a
  /// dropped card's own project.
  final BoardProjectsState projects;
  final void Function(Issue) onOpenIssue;

  /// Whether the board breaks out of the reading width. The board screen
  /// decides it from the columns, for both kinds of board alike.
  final bool fullWidth;

  @override
  State<ScrumBoardView> createState() => _ScrumBoardViewState();
}

enum _Tab { planning, active, insights }

class _ScrumBoardViewState extends State<ScrumBoardView>
    with BoardHeadHost<ScrumBoardView> {
  /// The board screen's wall, which shows the sprint the board runs.
  late final BoardWallCubit _wall = context.read<BoardWallCubit>();

  @override
  late final BoardHeadCubit head = context.read<BoardHeadCubit>();

  late final BoardRepository _boardApi = context.read<BoardRepository>();
  late final SprintRepository _sprintApi = context.read<SprintRepository>();
  late final SprintPlanningCubit _planning = SprintPlanningCubit(
    boards: _boardApi,
    issues: context.read<IssueRepository>(),
    sprints: _sprintApi,
    boardId: widget.board.id,
  );

  /// The planning lists every issue type over the whole board, and its filter
  /// offers what those hold.
  static const _facetsShape = BoardCardShape.planning;

  // Store-screenshot builds open straight on the Active-sprint board (the kanban
  // columns) rather than Planning, so the marketing shot shows the live board.
  _Tab _tab = const bool.fromEnvironment('SCREENSHOT_MODE')
      ? _Tab.active
      : _Tab.planning;

  // Planning selection / drag.
  final Set<String> _selected = {};

  // Insights report (lazy, for the active sprint).
  SprintReport? _report;
  bool _reportLoading = false;
  String? _reportError;

  /// What changed while another tab was on screen, read again once its tab
  /// shows: the whole planning or only the sprints named, and the wall.
  bool _planningStale = false;
  final Set<String> _staleSprints = {};
  bool _wallStale = false;

  final BoardPeopleMemo _planningPeople = BoardPeopleMemo();
  final BoardPeopleMemo _wallPeople = BoardPeopleMemo();
  final BoardCardsByIdMemo _cardsById = BoardCardsByIdMemo();

  /// Reads the tab on screen again when an issue changes anywhere: an edit made
  /// in the issue detail (a new sub-task, a sub-task ticked off, a title change)
  /// would otherwise leave its cards stale.
  StreamSubscription<void>? _issueSub;

  @override
  void initState() {
    super.initState();
    _issueSub = IssueEvents.instance.changes.listen((_) => _changedElsewhere());
    unawaited(_planning.load());
    // The faces want their facets from the start.
    unawaited(head.ensureFacets(_facetsShape));
  }

  @override
  void dispose() {
    _issueSub?.cancel();
    _planning.close();
    super.dispose();
  }

  void _changedElsewhere() {
    head.facetsChanged();
    switch (_tab) {
      case _Tab.planning:
        _planning.refreshSoon();
        _wallStale = true;
        _report = null;
      case _Tab.active:
        _wall.refreshSoon();
        _planningStale = true;
        _report = null;
      case _Tab.insights:
        unawaited(_loadReport());
        _planningStale = true;
        _wallStale = true;
    }
  }

  // ── derived ─────────────────────────────────────────────────────────────

  /// The sprint the board runs, as its wall shows it.
  static Sprint? _activeSprint(BoardWallState wall) {
    final id = wall.sprintId;
    if (id == null) return null;
    return wall.sprints.where((s) => s.id == id && !s.archived).firstOrNull;
  }

  /// The open sprints the board does not run.
  List<Sprint> _plannedSprints(
    SprintPlanningState planning,
    String? activeSprintId,
  ) => [
    for (final sprint in planning.sprints)
      if (sprint.id != activeSprintId) sprint,
  ];

  bool get _crossProject => widget.board.projectIds.length > 1;

  // ── loading ─────────────────────────────────────────────────────────────

  bool _planningRead(SprintPlanningState previous, SprintPlanningState next) =>
      previous.status != next.status ||
      previous.refreshing != next.refreshing ||
      previous.errorKey != next.errorKey;

  void _onPlanning(BuildContext context, SprintPlanningState planning) {
    final ready = planning.status == SprintPlanningStatus.ready;
    if (ready && !planning.refreshing) {
      unawaited(head.ensureFacets(_facetsShape));
    }
    // A planning that never arrived says so in its place instead.
    final errorKey = planning.errorKey;
    if (ready && errorKey != null) {
      _toastKey(errorKey, kind: GlassToastKind.error);
    }
  }

  /// The search, the filter or the grouping changed: the tab on screen reads
  /// the cards they narrow to, the other one once it is shown.
  void _onNarrowed(BuildContext context, BoardHeadState state) {
    switch (_tab) {
      case _Tab.planning:
        _planning.narrow(state.query(BoardCardShape.planning));
      case _Tab.active:
        _wall.narrow(state.query(state.wallShape));
      case _Tab.insights:
        break;
    }
  }

  Future<void> _loadReport() async {
    final id = _activeSprint(_wall.state)?.id;
    if (id == null || !mounted) return;
    setState(() {
      _reportLoading = true;
      _reportError = null;
    });
    try {
      final report = await _sprintApi.sprintReport(id);
      if (!mounted) return;
      setState(() {
        _report = report;
        _reportLoading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _reportLoading = false;
        _reportError = failure.message;
      });
    }
  }

  // ── mutations ───────────────────────────────────────────────────────────

  /// Resolves [key] against i18n only after confirming the widget is still
  /// mounted, so [context] is never read across an async gap.
  void _toastKey(
    String key, {
    Map<String, dynamic>? vars,
    GlassToastKind kind = GlassToastKind.info,
  }) {
    if (!mounted) return;
    showGlassToast(context, context.t(key, variables: vars), kind: kind);
  }

  /// What follows a change the planning made to the cards of [sprintIds], or
  /// of any sprint when [anySprint]: the wall reads again once it is shown
  /// when the board runs one of them, and the insights count again. A refusal
  /// needs neither; the planning has put its cards back and says why.
  void _afterPlanningChange({
    Iterable<String?> sprintIds = const [],
    bool anySprint = false,
  }) {
    head.facetsChanged();
    final active = _activeSprint(_wall.state)?.id;
    if (active != null && (anySprint || sprintIds.contains(active))) {
      _wallStale = true;
    }
    _report = null;
  }

  Future<void> _moveIssueToSprint(Issue issue, String? sprintId) async {
    if (issue.sprintId == sprintId) return;
    setState(() => _selected.remove(issue.id));
    if (await _planning.moveToSprint(issue, sprintId) != null || !mounted) {
      return;
    }
    _afterPlanningChange(sprintIds: [issue.sprintId, sprintId]);
  }

  Future<void> _bulkMove(String? sprintId) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    setState(_selected.clear);
    if (await _planning.moveAll(ids, sprintId) != null || !mounted) return;
    // Cards picked where they are no longer shown may come from any sprint.
    _afterPlanningChange(anySprint: true);
  }

  Future<void> _estimate(Issue issue) async {
    final result = await showEstimateDialog(context, issue: issue);
    if (result == null || !mounted) return;
    if (await _planning.estimate(issue, result.points) != null || !mounted) {
      return;
    }
    // Story points feed the cards, committed, velocity and burndown.
    _afterPlanningChange(sprintIds: [issue.sprintId]);
  }

  /// Moves a card of the active sprint into [column]: on the wall at once, and
  /// back again when the server refuses, which the board screen then says.
  Future<void> _moveIssueState(Issue issue, BoardColumnView column) async {
    if (column.states.isEmpty || column.states.contains(issue.state)) return;
    final target = boardDropState(issue, column.states, widget.projects.byId);
    if (target == null || target == issue.state) return;
    // Let the card settle in visibly at its new home — the tail end of the
    // drag, not a separate effect.
    boardDrag.land(issue.id);
    if (await _wall.move(issue, column.name, target) != null || !mounted) {
      return;
    }
    // The sprint's head in the planning counts by state, and the filter may
    // offer a new one. Only that sprint is read again, once the planning shows.
    head.facetsChanged();
    final active = _wall.state.sprintId;
    if (active != null) _staleSprints.add(active);
    _report = null;
  }

  void _toggleSelected(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  /// Seeds a section's inline composer. [sprintId] targets the sprint the
  /// ticket is written into (null = the backlog); [stateFor] carries the column
  /// state on the active board, where a composer sits under a column.
  IssueQuickCreateSeed _quickCreateSeed(
    String? sprintId, {
    String? Function(Project project)? stateFor,
  }) => IssueQuickCreateSeed(
    projects: widget.projects.inBoardOrder,
    stateFor: stateFor,
    sprintId: sprintId,
  );

  /// A ticket written into a sprint or the backlog of the planning: only where
  /// it landed is read again.
  void _onPlannedCreated(Issue created) {
    unawaited(_planning.rereadSprints({created.sprintId}));
    _afterPlanningChange(sprintIds: [created.sprintId]);
  }

  /// A ticket written under a column of the active sprint.
  void _onActiveCreated(Issue created) {
    head.facetsChanged();
    unawaited(_wall.refresh());
    final active = _wall.state.sprintId;
    if (active != null) _staleSprints.add(active);
    _report = null;
  }

  int _nextSprintNumber(List<Sprint> sprints) {
    var max = 0;
    final re = RegExp(r'(\d+)');
    for (final s in sprints) {
      final m = re.allMatches(s.name).lastOrNull;
      final n = m == null ? null : int.tryParse(m.group(1)!);
      if (n != null && n > max) max = n;
    }
    return (max == 0 ? sprints.length : max) + 1;
  }

  Future<void> _createSprint() async {
    final sprints = _planning.state.sprints;
    final lastEnd = sprints
        .map((s) => s.endDate)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final data = await showCreateSprintDialog(
      context,
      nextNumber: _nextSprintNumber(sprints),
      defaultStart: lastEnd?.add(const Duration(days: 3)),
    );
    if (data == null) return;
    try {
      await _sprintApi.createSprint(
        boardId: widget.board.id,
        name: data.name,
        goal: data.goal,
        startDate: data.start,
        endDate: data.end,
      );
      _toastKey(
        'sprint.toast.created',
        vars: {'name': data.name},
        kind: GlassToastKind.success,
      );
      await _planning.load();
    } on ApiFailure catch (failure) {
      _toastKey(failure.message, kind: GlassToastKind.error);
    }
  }

  /// Every card of [sprint] by state, whatever narrows the planning, or null
  /// once a toast has said why it could not be read.
  Future<List<BoardStateSummary>?> _wholeSprint(Sprint sprint) async {
    try {
      return await _planning.summaryOf(sprint.id);
    } catch (error) {
      _toastKey(
        error is ApiFailure ? error.message : 'errors.unexpected',
        kind: GlassToastKind.error,
      );
      return null;
    }
  }

  Future<void> _startSprint(Sprint sprint) async {
    final summary = await _wholeSprint(sprint);
    if (summary == null || !mounted) return;
    // A narrowed planning keeps the button open, since it may not show what a
    // sprint holds; the whole sprint counted says whether there is anything.
    if (summary.cardCount == 0) {
      _toastKey(
        'sprint.nothingToStart',
        vars: {'name': sprint.name},
        kind: GlassToastKind.warning,
      );
      return;
    }
    final data = await showStartSprintDialog(
      context,
      sprintName: sprint.name,
      initialGoal: sprint.goal,
      start: sprint.startDate ?? DateTime.now(),
      issueCount: summary.cardCount,
      committedPoints: summary.points,
      capacityPoints: sprint.capacityPoints,
    );
    if (data == null) return;
    try {
      await _sprintApi.startSprint(
        sprint.id,
        goal: data.goal,
        endDate: data.endDate,
      );
      _report = null;
      _toastKey(
        'sprint.toast.started',
        vars: {'name': sprint.name},
        kind: GlassToastKind.success,
      );
      // The wall shows the started sprint once it has read the board again,
      // narrowed the way the active tab it opens on is.
      final state = head.state;
      _wall.narrow(state.query(state.wallShape));
      await Future.wait([_wall.load(), _planning.load()]);
      _wallStale = false;
      if (mounted) _switchTab(_Tab.active);
    } on ApiFailure catch (failure) {
      _toastKey(failure.message, kind: GlassToastKind.error);
    }
  }

  Future<void> _completeSprint(Sprint sprint) async {
    final summary = await _wholeSprint(sprint);
    if (summary == null || !mounted) return;
    final done = summary.where((row) => row.resolved);
    final open = summary.where((row) => !row.resolved);
    final dest = await showCompleteSprintDialog(
      context,
      sprintName: sprint.name,
      doneCount: done.cardCount,
      donePoints: done.points,
      openCount: open.cardCount,
      openPoints: open.points,
      plannedDestinations: _plannedSprints(_planning.state, sprint.id),
    );
    if (dest == null) return;
    try {
      await _sprintApi.completeSprint(sprint.id, moveOpenTo: dest);
      _report = null;
      _toastKey(
        'sprint.toast.completed',
        vars: {'name': sprint.name},
        kind: GlassToastKind.success,
      );
      // The board runs no sprint any more, which only a read of the wall says.
      await Future.wait([_wall.load(), _planning.load()]);
    } on ApiFailure catch (failure) {
      _toastKey(failure.message, kind: GlassToastKind.error);
    }
  }

  // ── head ────────────────────────────────────────────────────────────────

  /// Shows [tab]. The tab coming back reads what changed while it was away:
  /// the search or filter set meanwhile, or a change made elsewhere.
  void _switchTab(_Tab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    final state = head.state;
    switch (tab) {
      case _Tab.planning:
        _planning.catchUp(
          state.query(BoardCardShape.planning),
          stale: _planningStale,
          staleSprints: _staleSprints,
        );
        _planningStale = false;
        _staleSprints.clear();
      case _Tab.active:
        _wall.catchUp(state.query(state.wallShape), stale: _wallStale);
        _wallStale = false;
      case _Tab.insights:
        if (_report == null) unawaited(_loadReport());
    }
  }

  /// The bar's button for a new sprint. A method rather than a closure, so the
  /// action compares equal from one build to the next (see [PageAction.==]).
  void _createSprintFromBar(Rect? anchor) => unawaited(_createSprint());

  /// The search, the filter and the faces apply to the planning and the active
  /// sprint. The insights are numbers about the whole sprint.
  bool get _filterable => _tab != _Tab.insights;

  Widget _tabSwitch({required bool compact}) => BoardViewSwitch(
    compact: compact,
    items: [
      SegmentItem(
        icon: LucideIcons.listChecks,
        label: context.t('sprint.tab.planning'),
      ),
      SegmentItem(
        icon: LucideIcons.columns3,
        label: context.t('sprint.tab.active'),
      ),
      SegmentItem(
        icon: LucideIcons.chartLine,
        label: context.t('sprint.tab.insights'),
      ),
    ],
    selected: _tab.index,
    onChanged: (i) => _switchTab(_Tab.values[i]),
  );

  Future<void> _openFilter(Rect? anchor) {
    final wall = _wall.state;
    final planning = _planning.state;
    return openHeadFilter(
      shape: _facetsShape,
      anchor: anchor,
      sprints: planning.sprints,
      projects: widget.projects.byId.values,
      refs: wall.refs.values,
      users: [...planning.users.values, ...wall.users.values],
    );
  }

  void _openFilterAt(Rect? anchor) => unawaited(_openFilter(anchor));

  /// The phone's one docked row: the three views, the search and the tools.
  Widget _dock(BoardHeadState headState) => headDock(
    switcher: _tabSwitch(compact: true),
    canSearch: _filterable,
    tools: [
      if (_tab == _Tab.active)
        headGroupBy(headState, crossProject: _crossProject, compact: true),
      if (_filterable) headFilterPill(headState, onOpen: _openFilterAt),
      if (_filterable) ?headPeople(headState),
    ],
  );

  /// The same tools on a wide window: the views on the leading edge, the rest
  /// against the trailing one, wrapping to the room the window leaves them.
  Widget _wideToolbar(BoardHeadState headState) {
    // Faces only where there is plenty of room; a narrower window has the
    // filter's assignee section for them.
    final people = context.isExpanded && _filterable
        ? headPeople(headState)
        : null;
    return WideToolbar(
      leading: [_tabSwitch(compact: false)],
      trailing: [
        if (_filterable) headSearchField(),
        if (people != null) BoardPeopleSlot(child: people),
        if (_tab == _Tab.active)
          headGroupBy(headState, crossProject: _crossProject),
        if (_filterable)
          headFilterPill(headState, onOpen: _openFilterAt, showLabel: true),
      ],
    );
  }

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => MultiBlocListener(
    listeners: [
      BlocListener<SprintPlanningCubit, SprintPlanningState>(
        bloc: _planning,
        listenWhen: _planningRead,
        listener: _onPlanning,
      ),
      BlocListener<BoardHeadCubit, BoardHeadState>(
        listenWhen: (previous, next) => next.narrowsOtherThan(previous),
        listener: _onNarrowed,
      ),
    ],
    child: BlocBuilder<BoardHeadCubit, BoardHeadState>(
      buildWhen: (previous, next) => next.drawsOtherThan(previous),
      // The page needs no more of the wall than the sprint the board runs; the
      // active tab follows the rest of it on its own.
      builder: (context, headState) =>
          BlocSelector<BoardWallCubit, BoardWallState, Sprint?>(
            selector: _activeSprint,
            builder: (context, active) => _page(headState, active),
          ),
    ),
  );

  Widget _page(BoardHeadState headState, Sprint? active) {
    final compact = context.isCompact;
    return PageChrome(
      title: widget.board.name,
      titleLeading: true,
      contentMax: widget.fullWidth ? double.infinity : Breakpoints.readingWidth,
      // Sprints are made while planning. On a phone this is the bar's one page
      // action, on a wide window a labelled button in the sub-page bar.
      actions: _tab == _Tab.planning
          ? [
              PageAction(
                icon: LucideIcons.plus,
                label: context.t('sprint.createSprint'),
                primary: true,
                onTap: _createSprintFromBar,
              ),
            ]
          : const [],
      // Docked from the first frame, so the bar does not grow a row once the
      // sprints arrive and push the page down.
      bottom: compact ? _dock(headState) : null,
      bottomHeight: compact ? kBoardDockHeight : 0,
      child: compact
          // On a phone the tools are in the bar, and the surface leaves the
          // bar's height clear itself so its content scrolls up under the blur.
          ? _surface(headState, active, top: context.topGutter + 8)
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
                  child: _wideToolbar(headState),
                ),
                Expanded(child: _surface(headState, active, top: 0)),
              ],
            ),
    );
  }

  Widget _surface(
    BoardHeadState headState,
    Sprint? active, {
    required double top,
  }) {
    switch (_tab) {
      case _Tab.planning:
        return BlocBuilder<SprintPlanningCubit, SprintPlanningState>(
          bloc: _planning,
          builder: (context, planning) =>
              _planningSurface(planning, headState, active?.id, top: top),
        );
      case _Tab.active:
        if (active == null) {
          return _EmptyState(
            icon: LucideIcons.zap,
            title: context.t('sprint.noActive'),
            subtitle: context.t('sprint.noActiveSub'),
          );
        }
        return _activeSurface(headState, active, top: top);
      case _Tab.insights:
        if (active == null) {
          return _EmptyState(
            icon: LucideIcons.chartLine,
            title: context.t('sprint.noActive'),
            subtitle: context.t('sprint.noInsights'),
          );
        }
        return SprintInsightsSurface(
          topInset: top,
          report: _report,
          loading: _reportLoading,
          error: _reportError == null ? null : context.t(_reportError!),
          names: boardPeople(headState.facets.users).names,
          onRetry: _loadReport,
        );
    }
  }

  /// The active sprint's wall, watched only while its tab is on screen. Flat,
  /// every column follows its own cards; lanes are laid out from all of them.
  Widget _activeSurface(
    BoardHeadState headState,
    Sprint active, {
    required double top,
  }) => BlocBuilder<BoardWallCubit, BoardWallState>(
    buildWhen: (previous, next) =>
        boardWallReshaped(previous, next) ||
        (headState.grouping != BoardGrouping.none &&
            !identical(previous.columns, next.columns)),
    builder: (context, wall) {
      final people = _wallPeople.of(wall.users, headState.facets.users);
      final grouped = headState.grouping != BoardGrouping.none;
      return BoardWallDimmed(
        child: SprintActiveSurface(
          topInset: top,
          sprint: active,
          columns: wall.columns,
          onLoadMore: _wall.loadMore,
          grouping: headState.grouping,
          // Only lanes look cards' parents up.
          issuesById: grouped ? _cardsById.of(wall) : const {},
          epics: boardEpics(headState.facets.epics, wall.refs.values),
          names: people.names,
          avatars: people.avatars,
          pronouns: people.pronouns,
          projectNames: widget.projects.names,
          projectsById: widget.projects.byId,
          onOpenIssue: widget.onOpenIssue,
          onMove: _moveIssueState,
          quickCreateSeed: (stateFor) =>
              _quickCreateSeed(active.id, stateFor: stateFor),
          onCreated: _onActiveCreated,
        ),
      );
    },
  );

  Widget _planningSurface(
    SprintPlanningState planning,
    BoardHeadState headState,
    String? activeSprintId, {
    required double top,
  }) {
    switch (planning.status) {
      case SprintPlanningStatus.loading:
        return const Center(child: HiveLoader());
      case SprintPlanningStatus.failure:
        return BoardErrorRetry(
          message: context.t(planning.errorKey ?? 'errors.unexpected'),
          onRetry: _planning.load,
        );
      case SprintPlanningStatus.ready:
        final people = _planningPeople.of(
          planning.users,
          headState.facets.users,
        );
        return BoardDimmed(
          dimmed: planning.refreshing,
          child: SprintPlanningSurface(
            topInset: top,
            planning: planning,
            // The sprint the board runs first, then the planned ones.
            sprints: [
              ...planning.sprints.where((s) => s.id == activeSprintId),
              ..._plannedSprints(planning, activeSprintId),
            ],
            activeSprintId: activeSprintId,
            backlogPageSize: _planning.backlogPageSize,
            names: people.names,
            avatars: people.avatars,
            pronouns: people.pronouns,
            selected: _selected,
            onPage: _planning.showBacklogPage,
            onLoadMore: _planning.loadMore,
            onToggleSelect: _toggleSelected,
            onClearSelection: () => setState(_selected.clear),
            onOpenIssue: widget.onOpenIssue,
            onEstimate: _estimate,
            onMoveToSprint: _moveIssueToSprint,
            onBulkMove: _bulkMove,
            quickCreateSeed: _quickCreateSeed,
            onCreated: _onPlannedCreated,
            onStartSprint: _startSprint,
            onCompleteSprint: _completeSprint,
          ),
        );
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.pageGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.inkFaint),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}
