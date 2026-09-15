import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/events/issue_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/board_page_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_filter_bar.dart' show WideToolbar;
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart' show SegmentItem;
import '../board/board_drag.dart';
import '../board/board_filter.dart';
import '../board/board_filter_popup.dart';
import '../board/board_header.dart';
import '../board/board_people_strip.dart';
import '../board/board_swimlanes.dart';
import '../board/issue_quick_create.dart';
import '../board/wall/board_wall_cubit.dart';
import '../shell/page_chrome.dart';
import 'modals/complete_sprint_dialog.dart';
import 'modals/glass_modal.dart' show GlassToastKind, showGlassToast;
import 'modals/create_sprint_dialog.dart';
import 'modals/estimate_dialog.dart';
import 'modals/start_sprint_dialog.dart';
import 'planning/sprint_planning_cubit.dart';
import 'sprint_active_surface.dart';
import 'sprint_insights_surface.dart';
import 'sprint_planning_surface.dart';
import '../../core/repositories/board_repository.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/sprint_repository.dart';

/// The Scrum board: Planning · Active sprint · Insights, switched by a
/// segmented control.
///
/// The planning is read by its own [SprintPlanningCubit]: the open sprints a
/// page at a time with their heads counted on the server, and the backlog a
/// page at a time. The active sprint is the board screen's wall, which shows
/// the sprint the board runs. The search and the filter in the head narrow
/// both on the server, and a change shows at once where it was made.
class ScrumBoardView extends StatefulWidget {
  const ScrumBoardView({
    super.key,
    required this.view,
    required this.projectNames,
    this.projectsById = const {},
    required this.onOpenIssue,
    this.fullWidth = false,
  });

  final BoardView view;
  final Map<String, String> projectNames;

  /// The board's spanned projects — needed to resolve which state of a merged
  /// column belongs to a dropped card's own project on a cross-project board.
  final Map<String, Project> projectsById;
  final void Function(Issue) onOpenIssue;

  /// Whether the board breaks out of the reading width. The board screen
  /// decides it from the columns, for both kinds of board alike.
  final bool fullWidth;

  @override
  State<ScrumBoardView> createState() => _ScrumBoardViewState();
}

enum _Tab { planning, active, insights }

class _ScrumBoardViewState extends State<ScrumBoardView> {
  AgileBoard get _board => widget.view.board;

  /// The board screen's wall, which shows the sprint the board runs.
  late final BoardWallCubit _wall;
  late final SprintPlanningCubit _planning;
  late final BoardRepository _boardApi;
  late final SprintRepository _sprintApi;

  // Store-screenshot builds open straight on the Active-sprint board (the kanban
  // columns) rather than Planning, so the marketing shot shows the live board.
  _Tab _tab = const bool.fromEnvironment('SCREENSHOT_MODE')
      ? _Tab.active
      : _Tab.planning;

  // Shared people/criteria filter for the Planning + Active surfaces.
  BoardFilter _filter = BoardFilter.empty;

  // The search over the planning and the active sprint, typed into the head.
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// Whether a phone's docked row shows the search field instead of the tools.
  bool _searching = false;

  // Swimlane grouping for the active-sprint board.
  BoardGrouping _grouping = BoardGrouping.none;

  /// What the filter and the row of faces can offer, over every card of the
  /// board rather than the loaded ones.
  BoardFacets _facets = BoardFacets.empty;
  bool _facetsStale = true;

  // Planning selection / drag.
  final Set<String> _selected = {};

  // Insights report (lazy, for the active sprint).
  SprintReport? _report;
  bool _reportLoading = false;
  String? _reportError;

  /// Reads the planning again when an issue changes anywhere: an edit made in
  /// the issue detail (a new sub-task, a sub-task ticked off, a title change)
  /// would otherwise leave the sprint cards stale. The board screen does the
  /// same for its wall.
  StreamSubscription<void>? _issueSub;

  @override
  void initState() {
    super.initState();
    _wall = context.read<BoardWallCubit>();
    _boardApi = context.read<BoardRepository>();
    _sprintApi = context.read<SprintRepository>();
    _planning = SprintPlanningCubit(
      boards: _boardApi,
      issues: context.read<IssueRepository>(),
      sprints: _sprintApi,
      boardId: _board.id,
    );
    _issueSub = IssueEvents.instance.changes.listen((_) => _changedElsewhere());
    unawaited(_planning.load());
  }

  @override
  void dispose() {
    _issueSub?.cancel();
    _searchController.dispose();
    _planning.close();
    super.dispose();
  }

  void _changedElsewhere() {
    _planning.refreshSoon();
    _facetsStale = true;
    _invalidateReport();
  }

  // ── derived ─────────────────────────────────────────────────────────────

  /// The sprint the board runs, as its wall shows it.
  Sprint? _activeSprint(BoardWallState wall) {
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

  BoardPeople _people(BoardWallState wall, SprintPlanningState planning) =>
      boardPeople([
        ..._facets.users,
        ...planning.users.values,
        ...wall.users.values,
      ]);

  /// Epics across the board's projects — drive grouping headers + the filter.
  List<Issue> _epics(BoardWallState wall) =>
      boardEpics(_facets.epics, wall.refs.values);

  // ── loading ─────────────────────────────────────────────────────────────

  bool _planningChanged(
    SprintPlanningState previous,
    SprintPlanningState next,
  ) =>
      previous.status != next.status ||
      previous.refreshing != next.refreshing ||
      previous.errorKey != next.errorKey;

  void _onPlanning(BuildContext context, SprintPlanningState planning) {
    final ready = planning.status == SprintPlanningStatus.ready;
    if (ready && !planning.refreshing && _facetsStale) {
      unawaited(_loadFacets());
    }
    // A planning that never arrived says so in its place instead.
    final errorKey = planning.errorKey;
    if (ready && errorKey != null) {
      _toastKey(errorKey, kind: GlassToastKind.error);
    }
  }

  Future<void> _loadFacets() async {
    _facetsStale = false;
    try {
      final facets = await _boardApi.facets(_board.id);
      if (!mounted) return;
      setState(() => _facets = facets);
    } on ApiFailure {
      // The filter keeps the options it had; the next read tries again.
      _facetsStale = true;
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

  /// Drops the cached insights report (refreshing it if it's currently shown)
  /// so it never lags behind a change that affects the numbers.
  void _invalidateReport() {
    if (_tab == _Tab.insights) {
      unawaited(_loadReport());
    } else {
      _report = null;
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
  /// of any sprint when [anySprint]: the wall reads again when the board runs
  /// one of them, and the insights count again. A refusal needs neither; the
  /// planning has read the server again and says why.
  void _afterPlanningChange({
    Iterable<String?> sprintIds = const [],
    bool anySprint = false,
  }) {
    final active = _activeSprint(_wall.state)?.id;
    if (active != null && (anySprint || sprintIds.contains(active))) {
      _wall.refreshSoon();
    }
    _invalidateReport();
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
    final target = boardDropState(issue, column.states, widget.projectsById);
    if (target == null || target == issue.state) return;
    // Let the card settle in visibly at its new home — the tail end of the
    // drag, not a separate effect.
    boardDrag.land(issue.id);
    if (await _wall.move(issue, column.name, target) != null || !mounted) {
      return;
    }
    // The sprint's head counts by state, and the filter may offer a new one.
    _facetsStale = true;
    _planning.refreshSoon();
    _invalidateReport();
  }

  void _toggleSelected(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  /// The board's projects in board order — what an inline composer on this
  /// surface may create into. More than one only on a merged board, where the
  /// composer shows a project control rather than picking the first silently.
  List<Project> get _boardProjects => [
    for (final id in _board.projectIds)
      if (widget.projectsById[id] != null) widget.projectsById[id]!,
  ];

  /// Seeds a section's inline composer. [sprintId] targets the sprint the
  /// ticket is written into (null = the backlog); [stateFor] carries the column
  /// state on the active board, where a composer sits under a column.
  IssueQuickCreateSeed _quickCreateSeed(
    String? sprintId, {
    String? Function(Project project)? stateFor,
  }) => IssueQuickCreateSeed(
    projects: _boardProjects,
    stateFor: stateFor,
    sprintId: sprintId,
  );

  /// A ticket written into a sprint or the backlog of the planning.
  void _onPlannedCreated(Issue created) {
    _facetsStale = true;
    unawaited(_planning.load());
    _afterPlanningChange(sprintIds: [created.sprintId]);
  }

  /// A ticket written under a column of the active sprint.
  void _onActiveCreated(Issue created) {
    _facetsStale = true;
    unawaited(_wall.refresh());
    _planning.refreshSoon();
    _invalidateReport();
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
        boardId: _board.id,
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
    } on ApiFailure catch (failure) {
      _toastKey(failure.message, kind: GlassToastKind.error);
      return null;
    }
  }

  Future<void> _startSprint(Sprint sprint) async {
    final summary = await _wholeSprint(sprint);
    if (summary == null || !mounted) return;
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
      // The wall shows the started sprint once it has read the board again.
      await Future.wait([_wall.refresh(), _planning.load()]);
      if (mounted) setState(() => _tab = _Tab.active);
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
      await Future.wait([_wall.refresh(), _planning.load()]);
      if (mounted) setState(() => _tab = _Tab.planning);
    } on ApiFailure catch (failure) {
      _toastKey(failure.message, kind: GlassToastKind.error);
    }
  }

  // ── head ────────────────────────────────────────────────────────────────

  /// The cards the wall wants: sub-tasks become cards of their own only when
  /// the wall is grouped by them.
  BoardCardShape get _wallShape => _grouping == BoardGrouping.subtask
      ? BoardCardShape.subtasks
      : BoardCardShape.wall;

  /// Hands the search and the filter to the server, for the planning and for
  /// the wall of the active sprint alike.
  void _narrow() {
    final query = _filter.toQuery(text: _query);
    _planning.narrow(query);
    _wall.narrow(query.withShape(_wallShape));
  }

  /// The server searches; the cards on screen stay until the answer is there.
  void _onQuery(String value) {
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

  Future<void> _openFilter(Rect? anchor) async {
    if (_facetsStale) await _loadFacets();
    if (!mounted) return;
    final wall = _wall.state;
    final planning = _planning.state;
    final people = _people(wall, planning);
    final epics = _epics(wall);
    await openBoardFilter(
      context,
      anchor: anchor,
      filter: _filter,
      options: BoardFilterOptions.fromFacets(
        _facets,
        boardSprints: planning.sprints,
        projectLabels: [
          for (final project in widget.projectsById.values)
            ...project.labelNames,
        ],
        epicIds: epics.map((e) => e.id),
      ),
      names: people.names,
      avatars: people.avatars,
      pronouns: people.pronouns,
      sprintNames: {for (final s in planning.sprints) s.id: s.name},
      epicNames: {for (final e in epics) e.id: '${e.readableId}  ${e.title}'},
      onChanged: (f) {
        setState(() => _filter = f);
        _narrow();
      },
    );
  }

  void _switchTab(_Tab tab) {
    setState(() => _tab = tab);
    if (tab == _Tab.insights && _report == null) unawaited(_loadReport());
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

  /// Grouping applies to the active sprint's board only.
  Widget _groupBy({required bool compact}) => BoardGroupByButton(
    value: _grouping,
    compact: compact,
    options: boardGroupingsFor(crossProject: _board.projectIds.length > 1),
    onChanged: _onGrouping,
  );

  Widget _filterPill({bool showLabel = false}) => BoardFilterPill(
    count: _filter.activeCount,
    showLabel: showLabel,
    onTap: (anchor) => unawaited(_openFilter(anchor)),
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

  /// The phone's one docked row: the three views, the search and the tools.
  Widget _dock(BoardPeople people) => BoardHeaderDock(
    switcher: _tabSwitch(compact: true),
    canSearch: _filterable,
    searching: _searching,
    searchController: _searchController,
    onSearchChanged: _onQuery,
    onSearchOpen: () => setState(() => _searching = true),
    onSearchClose: () => setState(() => _searching = false),
    tools: [
      if (_tab == _Tab.active) _groupBy(compact: true),
      if (_filterable) _filterPill(),
      if (_filterable && _facets.assigneeIds.isNotEmpty) _peopleStrip(people),
    ],
  );

  /// The same tools on a wide window: the views on the leading edge, the rest
  /// against the trailing one, wrapping to the room the window leaves them.
  Widget _wideToolbar(BoardPeople people) {
    // Faces only where there is plenty of room; a narrower window has the
    // filter's assignee section for them.
    final showPeople =
        context.isExpanded && _filterable && _facets.assigneeIds.isNotEmpty;
    return WideToolbar(
      leading: [_tabSwitch(compact: false)],
      trailing: [
        if (_filterable)
          BoardSearchField(controller: _searchController, onChanged: _onQuery),
        if (showPeople) BoardPeopleSlot(child: _peopleStrip(people)),
        if (_tab == _Tab.active) _groupBy(compact: false),
        if (_filterable) _filterPill(showLabel: true),
      ],
    );
  }

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final wall = context.watch<BoardWallCubit>().state;
    return BlocConsumer<SprintPlanningCubit, SprintPlanningState>(
      bloc: _planning,
      listenWhen: _planningChanged,
      listener: _onPlanning,
      builder: (context, planning) => _page(wall, planning),
    );
  }

  Widget _page(BoardWallState wall, SprintPlanningState planning) {
    final compact = context.isCompact;
    final people = _people(wall, planning);
    return PageChrome(
      title: _board.name,
      titleLeading: true,
      fullWidth: widget.fullWidth,
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
      bottom: compact ? _dock(people) : null,
      bottomHeight: compact ? kBoardDockHeight : 0,
      child: compact
          // On a phone the tools are in the bar, and the surface leaves the
          // bar's height clear itself so its content scrolls up under the blur.
          ? _surface(wall, planning, people, top: context.topGutter + 8)
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
                  child: _wideToolbar(people),
                ),
                Expanded(child: _surface(wall, planning, people, top: 0)),
              ],
            ),
    );
  }

  Widget _surface(
    BoardWallState wall,
    SprintPlanningState planning,
    BoardPeople people, {
    required double top,
  }) {
    final active = _activeSprint(wall);
    switch (_tab) {
      case _Tab.planning:
        return _planningSurface(planning, active?.id, people, top: top);
      case _Tab.active:
        if (active == null) {
          return _EmptyState(
            icon: LucideIcons.zap,
            title: context.t('sprint.noActive'),
            subtitle: context.t('sprint.noActiveSub'),
          );
        }
        return _dimmedWhile(
          wall.refreshing,
          SprintActiveSurface(
            topInset: top,
            sprint: active,
            columns: wall.columns,
            loadingMore: wall.loadingMore,
            onLoadMore: _wall.loadMore,
            grouping: _grouping,
            // Only lanes look cards' parents up.
            issuesById: _grouping == BoardGrouping.none
                ? const {}
                : {...wall.refs, for (final card in wall.cards) card.id: card},
            epics: _epics(wall),
            names: people.names,
            avatars: people.avatars,
            pronouns: people.pronouns,
            projectNames: widget.projectNames,
            projectsById: widget.projectsById,
            onOpenIssue: widget.onOpenIssue,
            onMove: _moveIssueState,
            quickCreateSeed: (stateFor) =>
                _quickCreateSeed(active.id, stateFor: stateFor),
            onCreated: _onActiveCreated,
          ),
        );
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
          names: people.names,
          onRetry: _loadReport,
        );
    }
  }

  Widget _planningSurface(
    SprintPlanningState planning,
    String? activeSprintId,
    BoardPeople people, {
    required double top,
  }) {
    switch (planning.status) {
      case SprintPlanningStatus.loading:
        return const Center(child: HiveLoader());
      case SprintPlanningStatus.failure:
        return _ErrorRetry(
          message: context.t(planning.errorKey ?? 'errors.unexpected'),
          onRetry: _planning.load,
        );
      case SprintPlanningStatus.ready:
        return _dimmedWhile(
          planning.refreshing,
          SprintPlanningSurface(
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
            query: _query,
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

  /// A search or a filter being read dims the cards it may replace, rather
  /// than blanking them.
  Widget _dimmedWhile(bool refreshing, Widget child) => AnimatedOpacity(
    opacity: refreshing ? 0.6 : 1,
    duration: const Duration(milliseconds: 160),
    child: child,
  );
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

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: Text(context.t('common.retry')),
          ),
        ],
      ),
    );
  }
}
