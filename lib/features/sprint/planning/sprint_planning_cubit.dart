import 'dart:async';
import 'dart:math' as math;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/board_page_models.dart';
import '../../../core/models/core_models.dart';
import '../../../core/models/work_models.dart';
import '../../../core/repositories/board_repository.dart';
import '../../../core/repositories/issue_repository.dart';
import '../../../core/repositories/sprint_repository.dart';

/// Where a Scrum board's planning stands.
enum SprintPlanningStatus { loading, ready, failure }

/// One sprint of the planning: the cards loaded so far, how many the sprint
/// holds, and all of its cards by state, which its head adds up into buckets,
/// capacity and the numbers of the start and complete dialogs.
class SprintContainer extends Equatable {
  const SprintContainer({
    this.items = const [],
    this.total = 0,
    this.summary = const [],
    this.loadingMore = false,
  });

  final List<Issue> items;
  final int total;
  final List<BoardStateSummary> summary;
  final bool loadingMore;

  bool get hasMore => items.length < total;

  /// Story points of every card in the sprint, loaded or not.
  int get points => summary.points;

  SprintContainer copyWith({
    List<Issue>? items,
    int? total,
    List<BoardStateSummary>? summary,
    bool? loadingMore,
  }) => SprintContainer(
    items: items ?? this.items,
    total: total ?? this.total,
    summary: summary ?? this.summary,
    loadingMore: loadingMore ?? this.loadingMore,
  );

  @override
  List<Object?> get props => [items, total, summary, loadingMore];
}

class SprintPlanningState extends Equatable {
  const SprintPlanningState({
    this.status = SprintPlanningStatus.loading,
    this.sprints = const [],
    this.containers = const {},
    this.backlog = const [],
    this.backlogTotal = 0,
    this.backlogPage = 0,
    this.query = everything,
    this.refreshing = false,
    this.users = const {},
    this.errorKey,
  });

  final SprintPlanningStatus status;

  /// The board's sprints that are not completed.
  final List<Sprint> sprints;

  /// Each of [sprints] by id.
  final Map<String, SprintContainer> containers;

  /// The backlog page on screen, and how many cards the backlog holds.
  final List<Issue> backlog;
  final int backlogTotal;
  final int backlogPage;

  /// The search and filter the planning was read with.
  final BoardQuery query;

  /// A new read is under way while the last cards stay in place.
  final bool refreshing;

  /// The people the loaded cards name, by id.
  final Map<String, DirectoryUser> users;

  /// Set for exactly one state after a read or a change failed.
  final String? errorKey;

  /// The planning's query while no search or filter narrows it: every card,
  /// of every type.
  static const everything = BoardQuery(shape: BoardCardShape.planning);

  /// Whether a search or a filter narrows what the planning shows.
  bool get narrowed => query != everything;

  SprintContainer containerOf(String sprintId) =>
      containers[sprintId] ?? const SprintContainer();

  /// Every loaded card: the sprints' and the backlog page's.
  List<Issue> get cards => [
    for (final container in containers.values) ...container.items,
    ...backlog,
  ];

  SprintPlanningState copyWith({
    SprintPlanningStatus? status,
    List<Sprint>? sprints,
    Map<String, SprintContainer>? containers,
    List<Issue>? backlog,
    int? backlogTotal,
    int? backlogPage,
    BoardQuery? query,
    bool? refreshing,
    Map<String, DirectoryUser>? users,
    String? errorKey,
  }) => SprintPlanningState(
    status: status ?? this.status,
    sprints: sprints ?? this.sprints,
    containers: containers ?? this.containers,
    backlog: backlog ?? this.backlog,
    backlogTotal: backlogTotal ?? this.backlogTotal,
    backlogPage: backlogPage ?? this.backlogPage,
    query: query ?? this.query,
    refreshing: refreshing ?? this.refreshing,
    users: users ?? this.users,
    // Always replaced: an error belongs to the one state that reports it.
    errorKey: errorKey,
  );

  @override
  List<Object?> get props => [
    status,
    sprints,
    containers,
    backlog,
    backlogTotal,
    backlogPage,
    query,
    refreshing,
    users,
    errorKey,
  ];
}

/// Reads a Scrum board's planning from the server: every open sprint with its
/// first page of cards and its summary by state, and the backlog a page at a
/// time.
///
/// It replaces a planning that loaded every issue of every sprint, then the
/// backlog, then every issue of the board's projects once more. The server
/// searches and filters here as on the wall, a sprint reads more when it is
/// asked to, and a card that is moved, pulled into a sprint or estimated
/// changes in place at once; only the sprints it touched are read again.
class SprintPlanningCubit extends Cubit<SprintPlanningState> {
  SprintPlanningCubit({
    required BoardRepository boards,
    required IssueRepository issues,
    required SprintRepository sprints,
    required this.boardId,
    this.sprintPageSize = 50,
    this.backlogPageSize = 12,
    this.searchDelay = const Duration(milliseconds: 300),
    this.refreshDelay = const Duration(milliseconds: 250),
  }) : _boards = boards,
       _issues = issues,
       _sprints = sprints,
       super(const SprintPlanningState());

  final BoardRepository _boards;
  final IssueRepository _issues;
  final SprintRepository _sprints;
  final String boardId;
  final int sprintPageSize;
  final int backlogPageSize;
  final Duration searchDelay;
  final Duration refreshDelay;

  int _generation = 0;
  BoardQuery? _pendingQuery;
  Timer? _searchTimer;
  Timer? _refreshTimer;

  /// Reads the sprints, each one's cards as deep as they are loaded, and the
  /// backlog page on screen.
  Future<void> load() async {
    _searchTimer?.cancel();
    _refreshTimer?.cancel();
    final query = _pendingQuery ?? state.query;
    final newQuery = _pendingQuery != null;
    _pendingQuery = null;
    final generation = ++_generation;
    final first = state.status != SprintPlanningStatus.ready;
    emit(
      state.copyWith(
        status: first ? SprintPlanningStatus.loading : null,
        refreshing: !first,
        query: query,
      ),
    );
    try {
      final sprints = await _sprints.sprints(boardId);
      final backlogPage = newQuery ? 0 : state.backlogPage;
      final reads = await Future.wait([
        for (final sprint in sprints)
          _boards.cards(
            boardId,
            sprintId: sprint.id,
            size: _depthOf(sprint.id),
            summary: true,
            query: query,
          ),
        _boards.cards(
          boardId,
          backlog: true,
          page: backlogPage,
          size: backlogPageSize,
          query: query,
        ),
      ]);
      if (isClosed || generation != _generation) return;
      final backlog = reads.last;
      emit(
        SprintPlanningState(
          status: SprintPlanningStatus.ready,
          sprints: sprints,
          containers: {
            for (var i = 0; i < sprints.length; i++)
              sprints[i].id: SprintContainer(
                items: reads[i].items,
                total: reads[i].total,
                summary: reads[i].summary ?? const [],
              ),
          },
          backlog: backlog.items,
          backlogTotal: backlog.total,
          backlogPage: backlogPage,
          query: query,
          users: _people(state.users, reads),
        ),
      );
    } on ApiFailure catch (failure) {
      _failed(generation, first, failure.message);
    } catch (_) {
      _failed(generation, first, 'errors.unexpected');
    }
  }

  void _failed(int generation, bool first, String errorKey) {
    if (isClosed || generation != _generation) return;
    emit(
      state.copyWith(
        status: first
            ? SprintPlanningStatus.failure
            : SprintPlanningStatus.ready,
        refreshing: false,
        errorKey: errorKey,
      ),
    );
  }

  /// Reads everything again a moment later, so a burst of changes elsewhere is
  /// one read.
  void refreshSoon() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(refreshDelay, () => unawaited(load()));
  }

  /// Narrows the planning to [query], from the backlog's first page. A change
  /// of the search text alone waits [searchDelay] for the next letter. The
  /// planning lists every issue type, whatever shape [query] was given.
  void narrow(BoardQuery query) {
    query = query.withShape(BoardCardShape.planning);
    final current = _pendingQuery ?? state.query;
    if (query == current) return;
    _pendingQuery = query;
    _searchTimer?.cancel();
    if (query.withText('') == current.withText('')) {
      _searchTimer = Timer(searchDelay, () => unawaited(load()));
    } else {
      unawaited(load());
    }
  }

  /// Reads the next page of the sprint [sprintId].
  Future<void> loadMore(String sprintId) async {
    final container = state.containers[sprintId];
    if (container == null ||
        !container.hasMore ||
        container.loadingMore ||
        state.refreshing) {
      return;
    }
    final generation = _generation;
    emit(_withContainer(sprintId, container.copyWith(loadingMore: true)));
    try {
      final page = await _boards.cards(
        boardId,
        sprintId: sprintId,
        page: container.items.length ~/ sprintPageSize,
        size: sprintPageSize,
        query: state.query,
      );
      if (isClosed || generation != _generation) return;
      final current = state.containerOf(sprintId);
      final merged = _append(current.items, page.items);
      final stuck =
          page.items.isNotEmpty && merged.length == current.items.length;
      emit(
        _withContainer(
          sprintId,
          current.copyWith(
            items: merged,
            total: stuck ? merged.length : page.total,
            loadingMore: false,
          ),
        ).copyWith(users: _people(state.users, [page])),
      );
    } catch (_) {
      if (isClosed || generation != _generation) return;
      emit(
        _withContainer(
          sprintId,
          state.containerOf(sprintId).copyWith(loadingMore: false),
        ),
      );
    }
  }

  /// Shows the backlog's page [page].
  Future<void> showBacklogPage(int page) async {
    final generation = _generation;
    emit(state.copyWith(backlogPage: page));
    try {
      final result = await _boards.cards(
        boardId,
        backlog: true,
        page: page,
        size: backlogPageSize,
        query: state.query,
      );
      if (isClosed || generation != _generation || state.backlogPage != page) {
        return;
      }
      emit(
        state.copyWith(
          backlog: result.items,
          backlogTotal: result.total,
          users: _people(state.users, [result]),
        ),
      );
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      emit(state.copyWith(errorKey: failure.message));
    }
  }

  /// Moves [issue] into the sprint [sprintId], or into the backlog for null:
  /// in place at once, on the server after. Both ends are read again, since
  /// entering a sprint may change a card's state and a sprint's head counts by
  /// state. Returns the refusal's message key, or null.
  Future<String?> moveToSprint(Issue issue, String? sprintId) async {
    if (issue.sprintId == sprintId) return null;
    final from = issue.sprintId;
    emit(_moved([issue], sprintId));
    try {
      await _issues.updateIssue(issue.id, {'sprintId': sprintId ?? ''});
      if (isClosed) return null;
      await _reread({from, sprintId});
      return null;
    } on ApiFailure catch (failure) {
      return _refused(failure.message);
    }
  }

  /// Moves every card among [ids] into [sprintId], or into the backlog for
  /// null, the loaded ones in place at once. A card picked on a backlog page
  /// no longer on screen moves as well; where it came from is not known here,
  /// so the planning is then read again as a whole.
  Future<String?> moveAll(Iterable<String> ids, String? sprintId) async {
    final wanted = ids.toSet();
    final loaded = {
      for (final card in state.cards)
        if (wanted.contains(card.id)) card.id: card,
    };
    final moving = [
      for (final card in loaded.values)
        if (card.sprintId != sprintId) card,
    ];
    final unseen = wanted.difference(loaded.keys.toSet());
    if (moving.isEmpty && unseen.isEmpty) return null;
    emit(_moved(moving, sprintId));
    try {
      await Future.wait([
        for (final id in [for (final card in moving) card.id, ...unseen])
          _issues.updateIssue(id, {'sprintId': sprintId ?? ''}),
      ]);
      if (isClosed) return null;
      if (unseen.isEmpty) {
        await _reread({for (final card in moving) card.sprintId, sprintId});
      } else {
        await load();
      }
      return null;
    } on ApiFailure catch (failure) {
      return _refused(failure.message);
    }
  }

  /// Sets [issue]'s story points, null to clear them: in place at once, and
  /// the sprint's head read again after.
  Future<String?> estimate(Issue issue, int? points) async {
    emit(_replaced(issue.copyWith(storyPoints: points)));
    try {
      await _issues.updateIssue(
        issue.id,
        points == null ? {'clearStoryPoints': true} : {'storyPoints': points},
      );
      if (isClosed) return null;
      if (issue.sprintId != null) await _reread({issue.sprintId});
      return null;
    } on ApiFailure catch (failure) {
      return _refused(failure.message);
    }
  }

  /// Every card of the sprint [sprintId] by state, whatever the planning is
  /// narrowed to: what starting or completing the sprint acts on. The sprint's
  /// head counts exactly that while nothing narrows it, so only a narrowed
  /// planning asks the server.
  Future<List<BoardStateSummary>> summaryOf(String sprintId) async {
    if (!state.narrowed) return state.containerOf(sprintId).summary;
    final whole = await _boards.cards(
      boardId,
      sprintId: sprintId,
      size: 0,
      summary: true,
      query: SprintPlanningState.everything,
    );
    return whole.summary ?? const [];
  }

  Future<String?> _refused(String errorKey) async {
    if (isClosed) return errorKey;
    emit(state.copyWith(errorKey: errorKey));
    // What the server holds decides; reading it again undoes the change made
    // up front.
    await load();
    return errorKey;
  }

  @override
  Future<void> close() {
    _searchTimer?.cancel();
    _refreshTimer?.cancel();
    return super.close();
  }

  // ── the planning's arithmetic ────────────────────────────────────────────

  int _depthOf(String sprintId) => math.min(
    math.max(state.containerOf(sprintId).items.length, sprintPageSize),
    kBoardMaxPageSize,
  );

  /// Reads again the sprints among [places] as deep as they are loaded, and
  /// the backlog page when null is among them.
  Future<void> _reread(Set<String?> places) async {
    final generation = _generation;
    final sprintIds = [
      for (final id in places)
        if (id != null && state.containers.containsKey(id)) id,
    ];
    final withBacklog = places.contains(null);
    try {
      final reads = await Future.wait([
        for (final id in sprintIds)
          _boards.cards(
            boardId,
            sprintId: id,
            size: _depthOf(id),
            summary: true,
            query: state.query,
          ),
        if (withBacklog)
          _boards.cards(
            boardId,
            backlog: true,
            page: state.backlogPage,
            size: backlogPageSize,
            query: state.query,
          ),
      ]);
      if (isClosed || generation != _generation) return;
      final containers = {...state.containers};
      for (var i = 0; i < sprintIds.length; i++) {
        containers[sprintIds[i]] = SprintContainer(
          items: reads[i].items,
          total: reads[i].total,
          summary: reads[i].summary ?? const [],
        );
      }
      emit(
        state.copyWith(
          containers: containers,
          backlog: withBacklog ? reads.last.items : null,
          backlogTotal: withBacklog ? reads.last.total : null,
          users: _people(state.users, reads),
        ),
      );
    } catch (_) {
      // The change is made; the next read of the planning shows its effects.
    }
  }

  SprintPlanningState _withContainer(
    String sprintId,
    SprintContainer container,
  ) => state.copyWith(containers: {...state.containers, sprintId: container});

  /// [cards] taken out of wherever they are and put on top of [sprintId], or
  /// of the backlog for null, with every total following along.
  SprintPlanningState _moved(List<Issue> cards, String? sprintId) {
    final ids = {for (final card in cards) card.id};
    final containers = <String, SprintContainer>{};
    for (final entry in state.containers.entries) {
      final kept = [
        for (final card in entry.value.items)
          if (!ids.contains(card.id)) card,
      ];
      final left = entry.value.items.length - kept.length;
      containers[entry.key] = entry.value.copyWith(
        items: kept,
        total: math.max(entry.value.total - left, 0),
      );
    }
    var backlog = [
      for (final card in state.backlog)
        if (!ids.contains(card.id)) card,
    ];
    var backlogTotal = math.max(
      state.backlogTotal - (state.backlog.length - backlog.length),
      0,
    );
    final arriving = [
      for (final card in cards) card.copyWith(sprintId: sprintId),
    ];
    if (sprintId == null) {
      backlog = [...arriving, ...backlog];
      backlogTotal += arriving.length;
    } else if (containers[sprintId] case final target?) {
      containers[sprintId] = target.copyWith(
        items: [...arriving, ...target.items],
        total: target.total + arriving.length,
      );
    }
    return state.copyWith(
      containers: containers,
      backlog: backlog,
      backlogTotal: backlogTotal,
    );
  }

  SprintPlanningState _replaced(Issue updated) => state.copyWith(
    containers: {
      for (final entry in state.containers.entries)
        entry.key: entry.value.copyWith(
          items: [
            for (final card in entry.value.items)
              card.id == updated.id ? updated : card,
          ],
        ),
    },
    backlog: [
      for (final card in state.backlog) card.id == updated.id ? updated : card,
    ],
  );

  static List<Issue> _append(List<Issue> held, List<Issue> incoming) {
    final seen = {for (final issue in held) issue.id};
    return [
      ...held,
      for (final issue in incoming)
        if (seen.add(issue.id)) issue,
    ];
  }

  static Map<String, DirectoryUser> _people(
    Map<String, DirectoryUser> held,
    List<BoardCardPage> pages,
  ) => {
    ...held,
    for (final page in pages)
      for (final user in page.users) user.id: user,
  };
}
