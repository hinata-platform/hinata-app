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
import '../../board/wall/board_reads.dart';

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

/// A Scrum board's planning as its surface draws it.
///
/// The sprints and the query only ever change together with the cards of a
/// read that arrived, so they always describe the cards on screen.
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

  /// The search and filter the planning on screen was read with.
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
    Map<String, SprintContainer>? containers,
    List<Issue>? backlog,
    int? backlogTotal,
    int? backlogPage,
    bool? refreshing,
    Map<String, DirectoryUser>? users,
    String? errorKey,
  }) => SprintPlanningState(
    status: status ?? this.status,
    sprints: sprints,
    containers: containers ?? this.containers,
    backlog: backlog ?? this.backlog,
    backlogTotal: backlogTotal ?? this.backlogTotal,
    backlogPage: backlogPage ?? this.backlogPage,
    query: query,
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
/// changes in place at once; only the sprints it touched are read again. A
/// change the server refuses is taken back in place before anything is read.
class SprintPlanningCubit extends Cubit<SprintPlanningState>
    with BoardReads<SprintPlanningState> {
  SprintPlanningCubit({
    required BoardRepository boards,
    required IssueRepository issues,
    required SprintRepository sprints,
    required this.boardId,
    this.sprintPageSize = kSprintPageSize,
    this.backlogPageSize = kBacklogPageSize,
    this.searchDelay = kBoardSearchDelay,
    this.filterDelay = kBoardFilterDelay,
    this.refreshDelay = kBoardRefreshDelay,
    this.parallelWrites = 4,
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

  /// How many changes a move of many cards sends at once.
  final int parallelWrites;

  @override
  final Duration searchDelay;

  @override
  final Duration filterDelay;

  @override
  final Duration refreshDelay;

  @override
  BoardQuery get shownQuery => state.query;

  /// Counts the backlog pages asked for, so only the last one asked shows.
  int _backlogRead = 0;

  /// Reads the sprints, each one's cards as deep as they are loaded, and the
  /// backlog page on screen. A new search or filter starts every sprint and
  /// the backlog from their first page.
  Future<void> load() async {
    final generation = startRead();
    final query = requestedQuery;
    final held = state;
    final first = held.status != SprintPlanningStatus.ready;
    final same = query == held.query;
    final backlogPage = same ? held.backlogPage : 0;
    emit(
      held.copyWith(
        status: first ? SprintPlanningStatus.loading : null,
        refreshing: !first,
      ),
    );
    try {
      final sprints = await _sprints.sprints(boardId);
      final sizes = [
        for (final sprint in sprints)
          same ? _depthOf(held, sprint.id) : sprintPageSize,
      ];
      final reads = await Future.wait([
        for (var i = 0; i < sprints.length; i++)
          _boards.cards(
            boardId,
            sprintId: sprints[i].id,
            size: sizes[i],
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
      if (!isCurrent(generation)) return;
      final fresh = {
        for (final read in reads)
          for (final card in read.items) card.id,
      };
      final containers = {
        for (var i = 0; i < sprints.length; i++)
          sprints[i].id: SprintContainer(
            items: deepened(
              same ? held.containerOf(sprints[i].id).items : const [],
              reads[i],
              sizes[i],
              fresh,
            ),
            total: reads[i].total,
            summary: reads[i].summary ?? const [],
          ),
      };
      final kept = [
        for (final container in containers.values)
          for (final card in container.items)
            if (!fresh.contains(card.id)) card,
      ];
      final backlog = reads.last;
      emit(
        SprintPlanningState(
          status: SprintPlanningStatus.ready,
          sprints: sprints,
          containers: containers,
          backlog: backlog.items,
          backlogTotal: backlog.total,
          backlogPage: backlogPage,
          query: query,
          users: sameOr(held.users, {
            ...namedBy(
              kept,
              held.users,
              (card) => [card.assigneeId, ...card.assigneeIds],
            ),
            for (final read in reads)
              for (final user in read.users) user.id: user,
          }),
        ),
      );
    } on ApiFailure catch (failure) {
      _failed(generation, first, failure.message);
    } catch (_) {
      _failed(generation, first, 'errors.unexpected');
    }
  }

  void _failed(int generation, bool first, String errorKey) {
    if (!isCurrent(generation)) return;
    readFailed();
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
  void refreshSoon() => scheduleRefresh(() => unawaited(load()));

  /// Narrows the planning to [query] once the typing or ticking has paused,
  /// from the backlog's first page. The planning lists every issue type,
  /// whatever shape [query] was given.
  void narrow(BoardQuery query) => scheduleNarrow(
    query.copyWith(shape: BoardCardShape.planning),
    () => unawaited(load()),
  );

  /// Reads the next page of the sprint [sprintId].
  Future<void> loadMore(String sprintId) async {
    final container = state.containers[sprintId];
    if (container == null ||
        !container.hasMore ||
        container.loadingMore ||
        state.refreshing) {
      return;
    }
    final generation = this.generation;
    emit(_withContainer(sprintId, container.copyWith(loadingMore: true)));
    try {
      final page = await _boards.cards(
        boardId,
        sprintId: sprintId,
        page: container.items.length ~/ sprintPageSize,
        size: sprintPageSize,
        query: state.query,
      );
      if (!isCurrent(generation)) return;
      final current = state.containerOf(sprintId);
      final appended = appendPage(current.items, page);
      emit(
        _withContainer(
          sprintId,
          current.copyWith(
            items: appended.items,
            total: appended.total,
            loadingMore: false,
          ),
        ).copyWith(
          users: mergeById(state.users, page.users, (user) => user.id),
        ),
      );
    } catch (error) {
      if (!isCurrent(generation)) return;
      emit(
        _withContainer(
          sprintId,
          state.containerOf(sprintId).copyWith(loadingMore: false),
        ).copyWith(errorKey: _keyOf(error)),
      );
    }
  }

  /// Shows the backlog's page [page] once it has arrived. The page on screen
  /// stays until then, and stays when the other does not come.
  Future<void> showBacklogPage(int page) async {
    final generation = this.generation;
    final read = ++_backlogRead;
    try {
      final result = await _boards.cards(
        boardId,
        backlog: true,
        page: page,
        size: backlogPageSize,
        query: state.query,
      );
      if (!isCurrent(generation) || read != _backlogRead) return;
      emit(
        state.copyWith(
          backlog: result.items,
          backlogTotal: result.total,
          backlogPage: page,
          users: mergeById(state.users, result.users, (user) => user.id),
        ),
      );
    } catch (error) {
      if (!isCurrent(generation) || read != _backlogRead) return;
      emit(state.copyWith(errorKey: _keyOf(error)));
    }
  }

  /// Moves [issue] into the sprint [sprintId], or into the backlog for null:
  /// in place at once, on the server after. Both ends are read again, since
  /// entering a sprint may change a card's state and a sprint's head counts by
  /// state. Returns the refusal's message key, or null.
  Future<String?> moveToSprint(Issue issue, String? sprintId) async {
    if (issue.sprintId == sprintId) return null;
    final before = state;
    emit(_moved([issue], sprintId));
    try {
      await _issues.updateIssue(issue.id, {'sprintId': sprintId ?? ''});
      if (isClosed) return null;
      await rereadSprints({issue.sprintId, sprintId});
      return null;
    } catch (error) {
      return _refused(before, _keyOf(error));
    }
  }

  /// Moves every card among [ids] into [sprintId], or into the backlog for
  /// null, the loaded ones in place at once, a few at a time on the server. A
  /// card picked on a backlog page no longer on screen moves as well; where it
  /// came from is not known here, so the planning is then read again as a
  /// whole.
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
    final before = state;
    emit(_moved(moving, sprintId));
    try {
      final all = [for (final card in moving) card.id, ...unseen];
      for (var start = 0; start < all.length; start += parallelWrites) {
        await Future.wait([
          for (final id in all.skip(start).take(parallelWrites))
            _issues.updateIssue(id, {'sprintId': sprintId ?? ''}),
        ]);
      }
      if (isClosed) return null;
      if (unseen.isEmpty) {
        await rereadSprints({
          for (final card in moving) card.sprintId,
          sprintId,
        });
      } else {
        await load();
      }
      return null;
    } catch (error) {
      return _refused(before, _keyOf(error));
    }
  }

  /// Sets [issue]'s story points, null to clear them: in place at once, and
  /// the sprint's head read again after.
  Future<String?> estimate(Issue issue, int? points) async {
    final before = state;
    emit(_replaced(issue.copyWith(storyPoints: points)));
    try {
      await _issues.updateIssue(
        issue.id,
        points == null ? {'clearStoryPoints': true} : {'storyPoints': points},
      );
      if (isClosed) return null;
      if (issue.sprintId != null) await rereadSprints({issue.sprintId});
      return null;
    } catch (error) {
      return _refused(before, _keyOf(error));
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

  /// Reads again the sprints among [places] as deep as they are loaded, with
  /// their heads, and the backlog page on screen when null is among them: for
  /// a change that touched only those, where a read of the whole planning
  /// would be spent on sprints that did not change.
  Future<void> rereadSprints(Set<String?> places) async {
    final generation = this.generation;
    final held = state;
    final sprintIds = [
      for (final id in places)
        if (id != null && held.containers.containsKey(id)) id,
    ];
    final withBacklog = places.contains(null);
    if (sprintIds.isEmpty && !withBacklog) return;
    final sizes = [for (final id in sprintIds) _depthOf(held, id)];
    try {
      final reads = await Future.wait([
        for (var i = 0; i < sprintIds.length; i++)
          _boards.cards(
            boardId,
            sprintId: sprintIds[i],
            size: sizes[i],
            summary: true,
            query: held.query,
          ),
        if (withBacklog)
          _boards.cards(
            boardId,
            backlog: true,
            page: held.backlogPage,
            size: backlogPageSize,
            query: held.query,
          ),
      ]);
      if (!isCurrent(generation)) return;
      final fresh = {
        for (final read in reads)
          for (final card in read.items) card.id,
      };
      final containers = {...state.containers};
      for (var i = 0; i < sprintIds.length; i++) {
        containers[sprintIds[i]] = SprintContainer(
          items: deepened(
            state.containerOf(sprintIds[i]).items,
            reads[i],
            sizes[i],
            fresh,
          ),
          total: reads[i].total,
          summary: reads[i].summary ?? const [],
        );
      }
      // Another backlog page may have been shown meanwhile.
      final backlog = withBacklog && state.backlogPage == held.backlogPage
          ? reads.last
          : null;
      emit(
        state.copyWith(
          containers: containers,
          backlog: backlog?.items,
          backlogTotal: backlog?.total,
          users: mergeById(state.users, [
            for (final read in reads) ...read.users,
          ], (user) => user.id),
        ),
      );
    } catch (_) {
      // The change is made; the next read of the planning shows its effects.
    }
  }

  /// Takes back a change the server refused. What was on screen before it
  /// comes back at once, with the reason, so the planning never shows a change
  /// that was not made, not even when it cannot be read again right now. What
  /// the server holds is read after.
  Future<String> _refused(SprintPlanningState before, String errorKey) async {
    if (isClosed) return errorKey;
    emit(before.copyWith(refreshing: state.refreshing, errorKey: errorKey));
    await load();
    return errorKey;
  }

  static String _keyOf(Object error) =>
      error is ApiFailure ? error.message : 'errors.unexpected';

  // ── the planning's arithmetic ────────────────────────────────────────────

  int _depthOf(SprintPlanningState held, String sprintId) => math.min(
    math.max(held.containerOf(sprintId).items.length, sprintPageSize),
    kBoardMaxPageSize,
  );

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
}
