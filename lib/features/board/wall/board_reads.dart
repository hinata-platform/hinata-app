import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../core/models/board_page_models.dart';
import '../../../core/models/work_models.dart';

/// How long a search waits for the next letter before it asks the server.
const Duration kBoardSearchDelay = Duration(milliseconds: 300);

/// How long any other narrowing waits for the next change, so a few chips
/// ticked in a row are one read.
const Duration kBoardFilterDelay = Duration(milliseconds: 150);

/// How long a refresh gathers changes made elsewhere before it reads again.
const Duration kBoardRefreshDelay = Duration(milliseconds: 250);

/// [page] appended to the cards [held] already, each card once.
///
/// A page that brings nothing new ends the reading: an empty one, as past the
/// reach of a page or after cards moved away, and one of cards held already, as
/// when the order moved under the reader. The count held is then the truth, or
/// the list would ask for the same page every time it is scrolled to its end.
({List<Issue> items, int total}) appendPage(
  List<Issue> held,
  BoardCardPage page,
) {
  final seen = {for (final issue in held) issue.id};
  final items = [
    ...held,
    for (final issue in page.items)
      if (seen.add(issue.id)) issue,
  ];
  return (
    items: items,
    total: items.length == held.length ? held.length : page.total,
  );
}

/// A list read again from its start as deep as it went, up to the most a page
/// may hold: the fresh [page] of [size] cards, then the cards [held] beyond
/// that reach.
///
/// Those are kept rather than dropped, so a refresh never takes cards away from
/// under someone who scrolled that far. The ones a fresh read holds anywhere
/// ([fresh], and the page itself) are left out, so a card that moved is not
/// shown twice. A page shorter than [size] is the end of the list, with nothing
/// beyond it to keep.
List<Issue> deepened(
  List<Issue> held,
  BoardCardPage page,
  int size,
  Set<String> fresh,
) {
  if (page.items.length < size) return page.items;
  final seen = {...fresh, for (final issue in page.items) issue.id};
  return [
    ...page.items,
    for (final issue in held.skip(size))
      if (seen.add(issue.id)) issue,
  ];
}

/// [incoming] merged into [held] by id. [held] itself comes back when nothing
/// in [incoming] is new or changed, so a page of people known already is no
/// change to whoever compares the map.
Map<String, T> mergeById<T>(
  Map<String, T> held,
  Iterable<T> incoming,
  String Function(T) idOf,
) {
  Map<String, T>? merged;
  for (final item in incoming) {
    final id = idOf(item);
    if (held[id] == item) continue;
    (merged ??= {...held})[id] = item;
  }
  return merged ?? held;
}

/// The entries of [held] that [cards] name through [idsOf]: what cards kept
/// from an earlier read still need of the people or references read with them.
Map<String, T> namedBy<T>(
  Iterable<Issue> cards,
  Map<String, T> held,
  Iterable<String?> Function(Issue card) idsOf,
) => {
  for (final card in cards)
    for (final id in idsOf(card).whereType<String>()) id: ?held[id],
};

/// Whether [a] and [b] hold the same ids in the same order.
bool sameIds(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// [fresh], or [held] where both hold the same entries: a read that brought
/// nobody new is no change to whoever compares the map.
Map<String, T> sameOr<T>(Map<String, T> held, Map<String, T> fresh) {
  if (held.length != fresh.length) return fresh;
  for (final entry in fresh.entries) {
    if (held[entry.key] != entry.value) return fresh;
  }
  return held;
}

/// What every reader of a board shares: generations that keep the answer to an
/// older read off the screen, a note of whether the latest read came, and a
/// refresh that gathers a burst of changes into one read.
mixin BoardReadGenerations<S> on Cubit<S> {
  /// How long [scheduleRefresh] gathers changes before it reads.
  Duration get refreshDelay;

  bool _lastReadFailed = false;
  int _generation = 0;
  Timer? _refreshTimer;

  /// The generation of the latest read of everything. A read of a part, such
  /// as a column's next page, keeps it and drops its answer once it moved on.
  int get generation => _generation;

  /// Whether the latest read did not come, so asking for what it read again
  /// reads it again rather than counting as no change.
  bool get lastReadFailed => _lastReadFailed;

  /// Starts a read of everything. A refresh waiting to be read is part of it,
  /// and every answer to an earlier read is stale from here. Returns its
  /// generation.
  int startRead() {
    _refreshTimer?.cancel();
    _lastReadFailed = false;
    return ++_generation;
  }

  /// Notes that the latest read did not come.
  void readFailed() => _lastReadFailed = true;

  /// Whether an answer to a read of [generation] may still be shown.
  bool isCurrent(int generation) => !isClosed && generation == _generation;

  /// Has [refresh] read again after [refreshDelay], once for a burst of calls.
  void scheduleRefresh(void Function() refresh) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(refreshDelay, refresh);
  }

  @override
  Future<void> close() {
    _refreshTimer?.cancel();
    return super.close();
  }
}

/// What the wall's and the planning's readers share besides: a narrowing that
/// waits for the next change before it reads.
///
/// The query a read asks for ([requestedQuery]) is kept apart from the one the
/// cards on screen were read with ([shownQuery]), which only a read that
/// succeeds hands over. A failed search then leaves the cards and their query
/// together, and the next read asks for the search again.
mixin BoardReads<S> on BoardReadGenerations<S> {
  /// How long a change of the search text alone waits for the next letter.
  Duration get searchDelay;

  /// How long any other narrowing waits for the next change.
  Duration get filterDelay;

  /// The query the cards on screen were read with.
  BoardQuery get shownQuery;

  BoardQuery? _requested;
  Timer? _narrowTimer;

  /// The query the next read asks for: the last one narrowed to, whether it
  /// has been read yet or not.
  BoardQuery get requestedQuery => _requested ?? shownQuery;

  /// Starts a read of everything, whatever waited to be narrowed to included.
  @override
  int startRead() {
    _narrowTimer?.cancel();
    return super.startRead();
  }

  /// Asks for [query] and has [read] read it once the typing or ticking has
  /// paused: a change of the search text alone waits [searchDelay], any other
  /// change [filterDelay]. Returns whether a read is coming: the query asked
  /// for already, and read, changes nothing.
  bool scheduleNarrow(BoardQuery query, void Function() read) {
    final current = requestedQuery;
    if (query == current && !lastReadFailed) return false;
    _requested = query;
    _narrowTimer?.cancel();
    final textOnly = query.copyWith(text: '') == current.copyWith(text: '');
    _narrowTimer = Timer(textOnly ? searchDelay : filterDelay, read);
    return true;
  }

  @override
  Future<void> close() {
    _narrowTimer?.cancel();
    return super.close();
  }
}
