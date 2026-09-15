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
import 'board_reads.dart';

/// Where a board's wall stands.
enum BoardWallStatus { loading, ready, failure }

/// A board's wall as a screen draws it: the columns with the cards loaded so
/// far and the number each column holds, and what those cards refer to.
///
/// The board, its sprints, the sprint picked and the query only ever change
/// together with the cards of a read that arrived, so they always describe the
/// cards on screen.
class BoardWallState extends Equatable {
  const BoardWallState({
    this.status = BoardWallStatus.loading,
    this.board,
    this.sprints = const [],
    this.sprintId,
    this.pickedSprintId,
    this.columns = const [],
    this.query = BoardQuery.all,
    this.refreshing = false,
    this.loadingMore = const {},
    this.failedColumns = const {},
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

  /// The sprint picked for the wall on screen; null leaves it to the board's
  /// active one. A ticket written on a picked sprint's wall joins that sprint.
  final String? pickedSprintId;
  final List<BoardColumnView> columns;

  /// The search and filter the cards on the wall were read with.
  final BoardQuery query;

  /// A new read is under way while the last cards stay on the wall, so a
  /// search typed letter by letter never blanks the board.
  final bool refreshing;

  /// Names of the columns reading their next page.
  final Set<String> loadingMore;

  /// Names of the columns whose last page did not come. They read on only when
  /// asked to again.
  final Set<String> failedColumns;

  /// The people the loaded cards name, by id.
  final Map<String, DirectoryUser> users;

  /// The epics and parents the loaded cards name, by id.
  final Map<String, Issue> refs;

  /// Set for exactly one state after a read or a move failed, so the host can
  /// raise a toast; the next state clears it.
  final String? errorKey;

  /// Every loaded card, column after column.
  List<Issue> get cards => [for (final column in columns) ...column.issues];

  /// The column called [name], if the wall has one.
  BoardColumnView? column(String name) {
    for (final column in columns) {
      if (column.name == name) return column;
    }
    return null;
  }

  BoardWallState copyWith({
    BoardWallStatus? status,
    List<BoardColumnView>? columns,
    bool? refreshing,
    Set<String>? loadingMore,
    Set<String>? failedColumns,
    Map<String, DirectoryUser>? users,
    Map<String, Issue>? refs,
    String? errorKey,
  }) => BoardWallState(
    status: status ?? this.status,
    board: board,
    sprints: sprints,
    sprintId: sprintId,
    pickedSprintId: pickedSprintId,
    columns: columns ?? this.columns,
    query: query,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    failedColumns: failedColumns ?? this.failedColumns,
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
    pickedSprintId,
    columns,
    query,
    refreshing,
    loadingMore,
    failedColumns,
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
class BoardWallCubit extends Cubit<BoardWallState>
    with BoardReadGenerations<BoardWallState>, BoardReads<BoardWallState> {
  BoardWallCubit({
    required BoardRepository boards,
    required IssueRepository issues,
    required this.boardId,
    String? sprintId,
    this.pageSize = kBoardPageSize,
    this.searchDelay = kBoardSearchDelay,
    this.filterDelay = kBoardFilterDelay,
    this.refreshDelay = kBoardRefreshDelay,
  }) : _boards = boards,
       _issues = issues,
       _pickedSprintId = sprintId,
       super(const BoardWallState());

  final BoardRepository _boards;
  final IssueRepository _issues;
  final String boardId;
  final int pageSize;

  @override
  final Duration searchDelay;

  @override
  final Duration filterDelay;

  @override
  final Duration refreshDelay;

  @override
  BoardQuery get shownQuery => state.query;

  /// The sprint asked for; null leaves it to the board's active one.
  String? _pickedSprintId;

  /// Reads the wall, every column from its first page. The first read shows
  /// the loader; later ones keep the cards on the wall until the new ones are
  /// there.
  Future<void> load() => _read(keepDepth: false);

  /// Reads the wall again and keeps every column as deep as it was scrolled.
  ///
  /// A column read past its first page reads again from its start in a request
  /// of its own, up to the most a page holds, and keeps its cards beyond that;
  /// every other column costs nothing more than the wall. A new search, filter
  /// or sprint starts every column over.
  Future<void> refresh() => _read(keepDepth: true);

  /// Like [refresh], a moment later, so a burst of changes elsewhere in the app
  /// is one read of the wall rather than one per change.
  void refreshSoon() => scheduleRefresh(() => unawaited(refresh()));

  /// Shows the sprint [sprintId], or the board's active sprint for null.
  Future<void> showSprint(String? sprintId) {
    _pickedSprintId = sprintId;
    return load();
  }

  /// Narrows the wall to [query] once the typing or ticking has paused.
  /// Returns whether a read of it is coming.
  bool narrow(BoardQuery query) =>
      scheduleNarrow(query, () => unawaited(load()));

  /// Brings the wall up to date as it comes back on screen: narrowed to
  /// [query] when the search or filter changed while it was away, else read
  /// again as deep as it was scrolled when it is [stale].
  void catchUp(BoardQuery query, {required bool stale}) {
    if (!narrow(query) && stale) unawaited(refresh());
  }

  Future<void> _read({required bool keepDepth}) async {
    final generation = startRead();
    final query = requestedQuery;
    final picked = _pickedSprintId;
    final held = state;
    final first = held.board == null;
    final sameWall = query == held.query && picked == held.pickedSprintId;
    final depths = <String, int>{
      if (keepDepth && sameWall)
        for (final column in held.columns)
          if (column.issues.length > pageSize)
            column.name: math.min(column.issues.length, kBoardMaxPageSize),
    };
    emit(
      held.copyWith(
        status: first ? BoardWallStatus.loading : null,
        refreshing: !first,
        // Pages under way belong to the wall this read replaces.
        loadingMore: const {},
      ),
    );
    // Asked for beside the wall, against the sprint on screen. Should the wall
    // come back as another sprint's, they are set aside.
    final deeper = {
      for (final entry in depths.entries)
        entry.key: _boards
            .cards(
              boardId,
              column: entry.key,
              sprintId: held.sprintId,
              size: entry.value,
              query: query,
            )
            .then<BoardCardPage?>((page) => page, onError: (Object _) => null),
    };
    try {
      final wall = await _boards.wall(
        boardId,
        sprintId: picked,
        size: pageSize,
        query: query,
      );
      final pages = <String, BoardCardPage>{
        for (final entry in deeper.entries) entry.key: ?await entry.value,
      };
      if (!isCurrent(generation)) return;
      emit(
        _arrived(
          held,
          wall,
          query: query,
          picked: picked,
          deeper: wall.sprintId == held.sprintId ? pages : const {},
          depths: depths,
        ),
      );
    } on ApiFailure catch (failure) {
      _failed(generation, first, failure.message);
    } catch (_) {
      _failed(generation, first, 'errors.unexpected');
    }
  }

  /// The wall that arrived, each column read deeper put in place of its first
  /// page. The people and references come from this read alone, apart from
  /// those the cards kept beyond a fresh page still name.
  BoardWallState _arrived(
    BoardWallState held,
    BoardWallPage wall, {
    required BoardQuery query,
    required String? picked,
    required Map<String, BoardCardPage> deeper,
    required Map<String, int> depths,
  }) {
    final fresh = {
      for (final column in wall.columns)
        for (final card in column.issues) card.id,
      for (final page in deeper.values)
        for (final card in page.items) card.id,
    };
    final columns = [
      for (final column in wall.columns)
        if (deeper[column.name] case final page?)
          column.copyWith(
            issues: deepened(
              held.column(column.name)?.issues ?? const [],
              page,
              depths[column.name]!,
              fresh,
            ),
            total: page.total,
          )
        else
          column,
    ];
    final kept = [
      for (final column in columns)
        for (final card in column.issues)
          if (!fresh.contains(card.id)) card,
    ];
    return BoardWallState(
      status: BoardWallStatus.ready,
      board: wall.board,
      sprints: wall.sprints,
      sprintId: wall.sprintId,
      pickedSprintId: picked,
      columns: columns,
      query: query,
      users: sameOr(held.users, {
        ...namedBy(
          kept,
          held.users,
          (card) => [card.assigneeId, ...card.assigneeIds],
        ),
        for (final user in wall.users) user.id: user,
        for (final page in deeper.values)
          for (final user in page.users) user.id: user,
      }),
      refs: sameOr(held.refs, {
        ...namedBy(kept, held.refs, (card) => [card.epicId, card.parentId]),
        for (final ref in wall.refs) ref.id: ref,
        for (final page in deeper.values)
          for (final ref in page.refs) ref.id: ref,
      }),
    );
  }

  void _failed(int generation, bool first, String errorKey) {
    if (!isCurrent(generation)) return;
    readFailed();
    emit(
      state.copyWith(
        status: first ? BoardWallStatus.failure : BoardWallStatus.ready,
        refreshing: false,
        errorKey: errorKey,
      ),
    );
  }

  /// Reads the next page of the column called [name], if it has one and is not
  /// reading already. A page that does not come marks the column failed, and
  /// it reads on when asked to again.
  Future<void> loadMore(String name) async {
    final column = state.column(name);
    if (column == null ||
        !column.hasMore ||
        state.status != BoardWallStatus.ready ||
        state.refreshing ||
        state.loadingMore.contains(name)) {
      return;
    }
    final generation = this.generation;
    emit(
      state.copyWith(
        loadingMore: {...state.loadingMore, name},
        failedColumns: {...state.failedColumns}..remove(name),
      ),
    );
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
      if (!isCurrent(generation)) return;
      final current = state.column(name);
      if (current == null) return;
      final appended = appendPage(current.issues, page);
      emit(
        state.copyWith(
          columns: _withColumn(
            current.copyWith(issues: appended.items, total: appended.total),
          ),
          loadingMore: {...state.loadingMore}..remove(name),
          users: mergeById(state.users, page.users, (user) => user.id),
          refs: mergeById(state.refs, page.refs, (ref) => ref.id),
        ),
      );
    } catch (_) {
      if (!isCurrent(generation)) return;
      emit(
        state.copyWith(
          loadingMore: {...state.loadingMore}..remove(name),
          failedColumns: {...state.failedColumns, name},
        ),
      );
    }
  }

  /// Moves [card] into the column called [to] in the workflow state
  /// [targetState]: on the wall at once, on the server after. When the server
  /// refuses, the card goes back and the message key of the refusal is
  /// returned; null otherwise.
  Future<String?> move(Issue card, String to, String targetState) async {
    final from = _columnOf(card.id);
    if (from == null || from.name == to || state.column(to) == null) {
      return null;
    }
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
      // A search or a filter may no longer hold the card where it landed, and
      // a read under way may answer from before the move. Grouping alone
      // narrows nothing.
      if (state.query.narrows || state.refreshing) refreshSoon();
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

  // ── the wall's arithmetic ────────────────────────────────────────────────

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
}
