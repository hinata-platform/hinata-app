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

/// Where a board's wall stands.
enum BoardWallStatus { loading, ready, failure }

/// A board's wall as a screen draws it: the columns with the cards loaded so
/// far and the number each column holds, and what those cards refer to.
class BoardWallState extends Equatable {
  const BoardWallState({
    this.status = BoardWallStatus.loading,
    this.board,
    this.sprints = const [],
    this.sprintId,
    this.columns = const [],
    this.query = BoardQuery.all,
    this.refreshing = false,
    this.loadingMore = const {},
    this.users = const {},
    this.refs = const {},
    this.errorKey,
  });

  final BoardWallStatus status;

  /// Null until the first wall has arrived.
  final AgileBoard? board;
  final List<Sprint> sprints;

  /// The sprint the wall shows: the one picked, else the board's active one.
  final String? sprintId;
  final List<BoardColumnView> columns;

  /// The search and filter the cards on the wall were read with.
  final BoardQuery query;

  /// A new read is under way while the last cards stay on the wall, so a
  /// search typed letter by letter never blanks the board.
  final bool refreshing;

  /// Names of the columns reading their next page.
  final Set<String> loadingMore;

  /// The people the loaded cards name, by id.
  final Map<String, DirectoryUser> users;

  /// The epics and parents the loaded cards name, by id.
  final Map<String, Issue> refs;

  /// Set for exactly one state after a read or a move failed, so the host can
  /// raise a toast; the next state clears it.
  final String? errorKey;

  /// The wall in the shape the board's surfaces take.
  BoardView? get view => board == null
      ? null
      : BoardView(board: board!, sprints: sprints, columns: columns);

  /// Every loaded card, column after column.
  List<Issue> get cards => [for (final column in columns) ...column.issues];

  BoardWallState copyWith({
    BoardWallStatus? status,
    AgileBoard? board,
    List<Sprint>? sprints,
    String? sprintId,
    List<BoardColumnView>? columns,
    BoardQuery? query,
    bool? refreshing,
    Set<String>? loadingMore,
    Map<String, DirectoryUser>? users,
    Map<String, Issue>? refs,
    String? errorKey,
  }) => BoardWallState(
    status: status ?? this.status,
    board: board ?? this.board,
    sprints: sprints ?? this.sprints,
    sprintId: sprintId ?? this.sprintId,
    columns: columns ?? this.columns,
    query: query ?? this.query,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    users: users ?? this.users,
    refs: refs ?? this.refs,
    // Always replaced: an error belongs to the one state that reports it.
    errorKey: errorKey,
  );

  @override
  List<Object?> get props => [
    status,
    board,
    sprints,
    sprintId,
    columns,
    query,
    refreshing,
    loadingMore,
    users,
    refs,
    errorKey,
  ];
}

/// Reads a board's wall from the server page by page and keeps it in step with
/// what happens to its cards.
///
/// The wall used to be every issue of the board's projects, loaded at once and
/// searched on the client. Here the server narrows: [narrow] hands it the
/// search and the filter, each column arrives with its total and its first
/// page, and [loadMore] reads a column's next page when someone scrolls to its
/// end. A card that is moved moves on the wall at once and goes back if the
/// server refuses.
class BoardWallCubit extends Cubit<BoardWallState> {
  BoardWallCubit({
    required BoardRepository boards,
    required IssueRepository issues,
    required this.boardId,
    String? sprintId,
    this.pageSize = kBoardPageSize,
    this.searchDelay = const Duration(milliseconds: 300),
    this.refreshDelay = const Duration(milliseconds: 250),
  }) : _boards = boards,
       _issues = issues,
       _requestedSprintId = sprintId,
       super(const BoardWallState());

  final BoardRepository _boards;
  final IssueRepository _issues;
  final String boardId;
  final int pageSize;

  /// How long a search waits for the next letter before it asks the server.
  final Duration searchDelay;

  /// How long [refreshSoon] gathers changes before it reads the wall again.
  final Duration refreshDelay;

  /// The sprint picked on the wall; null leaves it to the board's active one.
  String? _requestedSprintId;

  /// Bumped by every read of the whole wall, so an answer that arrives after a
  /// newer read started is dropped rather than shown.
  int _generation = 0;

  /// A narrowing that has not been read yet, while a search waits for letters.
  BoardQuery? _pendingQuery;
  Timer? _searchTimer;
  Timer? _refreshTimer;

  /// Reads the wall. The first read shows the loader; later ones keep the
  /// cards on the wall until the new ones are there. [depth] reads that many
  /// cards per column instead of one page, so a refresh keeps what someone
  /// already scrolled through.
  Future<void> load({int? depth}) async {
    _searchTimer?.cancel();
    _refreshTimer?.cancel();
    final query = _pendingQuery ?? state.query;
    _pendingQuery = null;
    final generation = ++_generation;
    final first = state.board == null;
    emit(
      state.copyWith(
        status: first ? BoardWallStatus.loading : state.status,
        refreshing: !first,
        query: query,
      ),
    );
    try {
      final wall = await _boards.wall(
        boardId,
        sprintId: _requestedSprintId,
        size: math.min(
          math.max(depth ?? pageSize, pageSize),
          kBoardMaxPageSize,
        ),
        query: query,
      );
      if (isClosed || generation != _generation) return;
      emit(
        BoardWallState(
          status: BoardWallStatus.ready,
          board: wall.board,
          sprints: wall.sprints,
          sprintId: wall.sprintId,
          columns: wall.columns,
          query: query,
          users: _byId(state.users, wall.users, (user) => user.id),
          refs: _byId(state.refs, wall.refs, (ref) => ref.id),
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
        status: first ? BoardWallStatus.failure : BoardWallStatus.ready,
        refreshing: false,
        errorKey: errorKey,
      ),
    );
  }

  /// Reads the wall again, as deep as its columns are loaded.
  Future<void> refresh() => load(depth: _loadedDepth);

  /// Like [refresh], a moment later, so a burst of changes elsewhere in the app
  /// is one read of the wall rather than one per change.
  void refreshSoon() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(refreshDelay, () => unawaited(refresh()));
  }

  /// Shows the sprint [sprintId], or the board's active sprint for null.
  Future<void> showSprint(String? sprintId) {
    _requestedSprintId = sprintId;
    return load();
  }

  /// Narrows the wall to [query]. A change of the search text alone waits
  /// [searchDelay] for the next letter, so a word typed out is one request;
  /// any other change reads at once.
  void narrow(BoardQuery query) {
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

  /// Reads the next page of the column called [name], if it has one and is not
  /// reading already.
  Future<void> loadMore(String name) async {
    final column = _column(name);
    if (column == null ||
        !column.hasMore ||
        state.status != BoardWallStatus.ready ||
        state.refreshing ||
        state.loadingMore.contains(name)) {
      return;
    }
    final generation = _generation;
    emit(state.copyWith(loadingMore: {...state.loadingMore, name}));
    try {
      final page = await _boards.cards(
        boardId,
        column: name,
        sprintId: state.sprintId,
        // The page the loaded cards end in rather than a counter: a card moved
        // away shifts every boundary behind it, and the ids drop the overlap.
        page: column.issues.length ~/ pageSize,
        size: pageSize,
        query: state.query,
      );
      if (isClosed || generation != _generation) return;
      final current = _column(name);
      if (current == null) return;
      final merged = _append(current.issues, page.items);
      // A whole page the column holds already means the order moved under the
      // reader. The count held is then the truth, or the column would ask for
      // the same page every time it is scrolled to its end.
      final stuck =
          page.items.isNotEmpty && merged.length == current.issues.length;
      emit(
        state.copyWith(
          columns: _withColumn(
            current.copyWith(
              issues: merged,
              total: stuck ? merged.length : page.total,
            ),
          ),
          loadingMore: {...state.loadingMore}..remove(name),
          users: _byId(state.users, page.users, (user) => user.id),
          refs: _byId(state.refs, page.refs, (ref) => ref.id),
        ),
      );
    } catch (_) {
      if (isClosed || generation != _generation) return;
      // The pages already loaded stay; scrolling to the end again retries.
      emit(state.copyWith(loadingMore: {...state.loadingMore}..remove(name)));
    }
  }

  /// Moves [card] into the column called [to] in the workflow state
  /// [targetState]: on the wall at once, on the server after. When the server
  /// refuses, the card goes back and the message key of the refusal is
  /// returned; null otherwise.
  Future<String?> move(Issue card, String to, String targetState) async {
    final from = _columnOf(card.id);
    if (from == null || from.name == to || _column(to) == null) return null;
    emit(
      state.copyWith(
        columns: _moved(
          card.id,
          card.copyWith(state: targetState),
          from.name,
          to,
        ),
      ),
    );
    try {
      await _issues.updateIssue(card.id, {'state': targetState});
      if (isClosed) return null;
      // A search or a filter may no longer keep the card where it landed.
      if (state.query != BoardQuery.all) unawaited(refresh());
      return null;
    } on ApiFailure catch (failure) {
      _moveBack(card, from.name, to, failure.message);
      return failure.message;
    } catch (_) {
      _moveBack(card, from.name, to, 'errors.unexpected');
      return 'errors.unexpected';
    }
  }

  void _moveBack(Issue card, String from, String to, String errorKey) {
    if (isClosed || _columnOf(card.id)?.name != to) return;
    emit(
      state.copyWith(
        columns: _moved(card.id, card, to, from),
        errorKey: errorKey,
      ),
    );
  }

  @override
  Future<void> close() {
    _searchTimer?.cancel();
    _refreshTimer?.cancel();
    return super.close();
  }

  // ── the wall's arithmetic ────────────────────────────────────────────────

  int get _loadedDepth => state.columns.fold(
    pageSize,
    (depth, column) => math.max(depth, column.issues.length),
  );

  BoardColumnView? _column(String name) {
    for (final column in state.columns) {
      if (column.name == name) return column;
    }
    return null;
  }

  BoardColumnView? _columnOf(String cardId) {
    for (final column in state.columns) {
      if (column.issues.any((issue) => issue.id == cardId)) return column;
    }
    return null;
  }

  List<BoardColumnView> _withColumn(BoardColumnView replacement) => [
    for (final column in state.columns)
      column.name == replacement.name ? replacement : column,
  ];

  /// The columns with the card [cardId] taken out of [from] and [card] put
  /// into [to] at its place in board order, both totals following along.
  List<BoardColumnView> _moved(
    String cardId,
    Issue card,
    String from,
    String to,
  ) => [
    for (final column in state.columns)
      if (column.name == from)
        column.copyWith(
          issues: [
            for (final issue in column.issues)
              if (issue.id != cardId) issue,
          ],
          total: math.max(column.count - 1, 0),
        )
      else if (column.name == to)
        column.copyWith(
          issues: _inBoardOrder(column.issues, card),
          total: column.count + 1,
        )
      else
        column,
  ];

  /// [card] placed among [issues] by rank, then id, the order the server reads
  /// in. A card that sorts past the loaded ones goes to the end of them, so a
  /// card that was just dropped is always where it can be seen.
  static List<Issue> _inBoardOrder(List<Issue> issues, Issue card) {
    final at = issues.indexWhere(
      (issue) =>
          issue.rank > card.rank ||
          (issue.rank == card.rank && issue.id.compareTo(card.id) > 0),
    );
    return at < 0 ? [...issues, card] : ([...issues]..insert(at, card));
  }

  static List<Issue> _append(List<Issue> held, List<Issue> incoming) {
    final seen = {for (final issue in held) issue.id};
    return [
      ...held,
      for (final issue in incoming)
        if (seen.add(issue.id)) issue,
    ];
  }

  static Map<String, T> _byId<T>(
    Map<String, T> held,
    List<T> incoming,
    String Function(T) idOf,
  ) => {...held, for (final item in incoming) idOf(item): item};
}
