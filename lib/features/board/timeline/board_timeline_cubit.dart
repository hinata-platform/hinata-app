import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/board_page_models.dart';
import '../../../core/models/work_models.dart';
import '../../../core/repositories/board_repository.dart';
import '../wall/board_reads.dart';

/// Where a board's timeline stands.
enum BoardTimelineStatus { idle, loading, ready, failure }

/// A board's timeline as its chart draws it: the cards with a date, then those
/// without, each read a page at a time, and the links between the loaded ones.
///
/// The sprint and the query only ever change together with the cards of a read
/// that arrived, so they always describe the cards on screen.
class BoardTimelineState extends Equatable {
  const BoardTimelineState({
    this.status = BoardTimelineStatus.idle,
    this.dated = const [],
    this.datedTotal = 0,
    this.undated = const [],
    this.undatedTotal = 0,
    this.links = const [],
    this.sprintId,
    this.query = const BoardQuery(shape: BoardCardShape.timeline),
    this.refreshing = false,
    this.loadingMore = false,
    this.errorKey,
  });

  final BoardTimelineStatus status;
  final List<Issue> dated;
  final int datedTotal;
  final List<Issue> undated;
  final int undatedTotal;

  /// The links between the loaded cards, for the chart's connectors.
  final List<GanttLink> links;
  final String? sprintId;
  final BoardQuery query;

  /// A new read is under way while the last cards stay on the chart.
  final bool refreshing;
  final bool loadingMore;

  /// Set for exactly one state after a read failed.
  final String? errorKey;

  /// The loaded cards, those with a date first.
  List<Issue> get issues => [...dated, ...undated];

  bool get hasMore =>
      dated.length < datedTotal || undated.length < undatedTotal;

  BoardTimelineState copyWith({
    BoardTimelineStatus? status,
    List<Issue>? dated,
    int? datedTotal,
    List<Issue>? undated,
    int? undatedTotal,
    List<GanttLink>? links,
    bool? refreshing,
    bool? loadingMore,
    String? errorKey,
  }) => BoardTimelineState(
    status: status ?? this.status,
    dated: dated ?? this.dated,
    datedTotal: datedTotal ?? this.datedTotal,
    undated: undated ?? this.undated,
    undatedTotal: undatedTotal ?? this.undatedTotal,
    links: links ?? this.links,
    sprintId: sprintId,
    query: query,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    // Always replaced: an error belongs to the one state that reports it.
    errorKey: errorKey,
  );

  @override
  List<Object?> get props => [
    status,
    dated,
    datedTotal,
    undated,
    undatedTotal,
    links,
    sprintId,
    query,
    refreshing,
    loadingMore,
    errorKey,
  ];
}

typedef _TimelineRequest = ({String? sprintId, BoardQuery query});

/// Reads a board's timeline from the server a page at a time, and the links
/// between the cards it has loaded.
///
/// It reads only while the timeline is on screen, and a change elsewhere reads
/// it again as deep as it was scrolled: each list from its start, up to the
/// most a page holds, keeping the cards beyond. The links are those between
/// the loaded cards alone, never every issue of the board's projects, and are
/// read again only for other cards or after a read of the whole timeline.
class BoardTimelineCubit extends Cubit<BoardTimelineState>
    with BoardReadGenerations<BoardTimelineState> {
  BoardTimelineCubit({
    required BoardRepository boards,
    required this.boardId,
    this.pageSize = kBoardMaxPageSize,
    this.refreshDelay = kBoardRefreshDelay,
  }) : _boards = boards,
       super(const BoardTimelineState());

  final BoardRepository _boards;
  final String boardId;
  final int pageSize;

  @override
  final Duration refreshDelay;

  _TimelineRequest? _requested;
  bool _outdated = false;

  /// Counts the reads of links, so only the last one asked for shows.
  int _linksRead = 0;

  /// The cards the links on the chart were read for.
  List<String> _linked = const [];

  /// Shows the timeline of the sprint [sprintId], or of the whole board for
  /// null, narrowed to [query]: read from its first pages, unless it is the
  /// timeline on screen or on its way already.
  Future<void> show({required String? sprintId, required BoardQuery query}) {
    final requested = (
      sprintId: sprintId,
      query: query.copyWith(shape: BoardCardShape.timeline),
    );
    if (requested == _requested && !lastReadFailed) {
      return _outdated ? _read(keepDepth: true) : Future.value();
    }
    _requested = requested;
    return _read(keepDepth: false);
  }

  /// Notes a change to the board's cards while the timeline is not on screen:
  /// the next [show] of the same timeline reads it again, as deep as it was
  /// scrolled.
  void changed() => _outdated = true;

  /// Reads the timeline on screen again, as deep as it was scrolled.
  Future<void> refresh() =>
      _requested == null ? Future.value() : _read(keepDepth: true);

  /// Like [refresh], a moment later, so a burst of changes is one read.
  void refreshSoon() {
    if (_requested == null) return;
    scheduleRefresh(() => unawaited(refresh()));
  }

  /// Reads the next page: of the cards with a date while there are more of
  /// them, then of those without.
  Future<void> loadMore() async {
    if (state.status != BoardTimelineStatus.ready ||
        state.refreshing ||
        state.loadingMore ||
        !state.hasMore) {
      return;
    }
    final generation = this.generation;
    final dated = state.dated.length < state.datedTotal;
    final held = dated ? state.dated : state.undated;
    emit(state.copyWith(loadingMore: true));
    try {
      final page = await _boards.cards(
        boardId,
        sprintId: state.sprintId,
        dated: dated,
        page: held.length ~/ pageSize,
        size: pageSize,
        query: state.query,
      );
      if (!isCurrent(generation)) return;
      final appended = appendPage(dated ? state.dated : state.undated, page);
      emit(
        dated
            ? state.copyWith(
                dated: appended.items,
                datedTotal: appended.total,
                loadingMore: false,
              )
            : state.copyWith(
                undated: appended.items,
                undatedTotal: appended.total,
                loadingMore: false,
              ),
      );
      await _readLinks(generation, unlessRead: true);
    } catch (_) {
      if (!isCurrent(generation)) return;
      emit(state.copyWith(loadingMore: false));
    }
  }

  Future<void> _read({required bool keepDepth}) async {
    _outdated = false;
    final generation = startRead();
    final requested = _requested!;
    final held = state;
    final ready = held.status == BoardTimelineStatus.ready;
    final same =
        keepDepth &&
        ready &&
        requested.sprintId == held.sprintId &&
        requested.query == held.query;
    emit(
      held.copyWith(
        status: ready ? null : BoardTimelineStatus.loading,
        refreshing: ready,
        loadingMore: false,
      ),
    );
    try {
      final reads = await Future.wait([
        for (final dated in const [true, false])
          _boards.cards(
            boardId,
            sprintId: requested.sprintId,
            dated: dated,
            size: pageSize,
            query: requested.query,
          ),
      ]);
      if (!isCurrent(generation)) return;
      final fresh = {
        for (final read in reads)
          for (final card in read.items) card.id,
      };
      emit(
        BoardTimelineState(
          status: BoardTimelineStatus.ready,
          dated: same
              ? deepened(held.dated, reads[0], pageSize, fresh)
              : reads[0].items,
          datedTotal: reads[0].total,
          undated: same
              ? deepened(held.undated, reads[1], pageSize, fresh)
              : reads[1].items,
          undatedTotal: reads[1].total,
          // The connectors drawn so far stay until the new ones are there.
          links: same ? held.links : const [],
          sprintId: requested.sprintId,
          query: requested.query,
        ),
      );
      await _readLinks(generation);
    } on ApiFailure catch (failure) {
      _failed(generation, failure.message);
    } catch (_) {
      _failed(generation, 'errors.unexpected');
    }
  }

  void _failed(int generation, String errorKey) {
    if (!isCurrent(generation)) return;
    readFailed();
    emit(
      state.copyWith(
        status: state.status == BoardTimelineStatus.ready
            ? BoardTimelineStatus.ready
            : BoardTimelineStatus.failure,
        refreshing: false,
        errorKey: errorKey,
      ),
    );
  }

  /// Reads the links between the cards on screen, the first
  /// [kBoardMaxLinkCards] of them. The connectors are an overlay on a chart
  /// that renders without them, so links that do not come leave those drawn.
  /// With [unlessRead] the links are not read again for the cards they were
  /// read for: a page that brought no card, or only cards past the first
  /// [kBoardMaxLinkCards], joins nothing new.
  Future<void> _readLinks(int generation, {bool unlessRead = false}) async {
    final ids = [
      for (final card in state.issues.take(kBoardMaxLinkCards)) card.id,
    ];
    if (ids.isEmpty || unlessRead && sameIds(ids, _linked)) return;
    final read = ++_linksRead;
    try {
      final links = await _boards.links(boardId, ids);
      if (!isCurrent(generation) || read != _linksRead) return;
      _linked = ids;
      emit(state.copyWith(links: links));
    } catch (_) {
      // See above: the chart keeps what it draws.
    }
  }
}
