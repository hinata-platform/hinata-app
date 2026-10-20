import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../api/api_client.dart';

/// One page of results from a server-paginated endpoint.
typedef PageResult<T> = ({List<T> items, int total});

/// Fetches page [page] (0-based) holding up to [size] items.
typedef PageFetcher<T> = Future<PageResult<T>> Function(int page, int size);

/// Immutable state for an infinite-scrolling, server-paginated list.
///
/// [items] accumulates across pages; [total] is the backend's full count so the
/// view knows whether more pages remain ([hasMore]). [isLoading] covers the
/// initial load / pull-to-refresh; [isLoadingMore] covers appending a page.
class PagedState<T> extends Equatable {
  const PagedState({
    this.items = const [],
    this.total = 0,
    this.page = -1,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.errorKey,
  });

  final List<T> items;
  final int total;

  /// Highest page index loaded so far (-1 before the first successful load).
  final int page;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorKey;

  bool get hasData => page >= 0;
  bool get hasMore => items.length < total;

  PagedState<T> copyWith({
    List<T>? items,
    int? total,
    int? page,
    bool? isLoading,
    bool? isLoadingMore,
    String? errorKey,
  }) => PagedState<T>(
    items: items ?? this.items,
    total: total ?? this.total,
    page: page ?? this.page,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    // errorKey is always replaced (pass null to clear).
    errorKey: errorKey,
  );

  @override
  List<Object?> get props => [
    items,
    total,
    page,
    isLoading,
    isLoadingMore,
    errorKey,
  ];
}

/// Drives an infinite-scrolling list backed by a paginated endpoint.
///
/// Call [load] for the initial fetch / pull-to-refresh (resets to page 0) and
/// [loadMore] when the user scrolls near the end. Both are guarded against
/// overlapping requests, and [loadMore] is a no-op once every page is loaded.
///
/// Optionally pass [keyOf] to de-duplicate items across pages — useful when the
/// backend orders by a mutable field (e.g. `updatedAt`) so a row can shift
/// between pages while paging.
class PagedCubit<T> extends Cubit<PagedState<T>> {
  PagedCubit(this._fetch, {this.pageSize = 50, this.keyOf})
    : super(PagedState<T>());

  final PageFetcher<T> _fetch;
  final int pageSize;
  final Object Function(T)? keyOf;

  /// Monotonic generation token. [load] bumps it so a slower in-flight request
  /// (e.g. a [loadMore] mid-refresh) can detect it was superseded and drop its
  /// result instead of corrupting the newer state.
  int _token = 0;

  /// Initial load or pull-to-refresh: resets to page 0 and supersedes any
  /// in-flight [loadMore].
  Future<void> load() async {
    final token = ++_token;
    emit(state.copyWith(isLoading: true));
    try {
      final result = await _fetch(0, pageSize);
      if (token != _token) return;
      emit(PagedState<T>(items: result.items, total: result.total, page: 0));
    } on ApiFailure catch (failure) {
      if (token != _token) return;
      emit(state.copyWith(isLoading: false, errorKey: failure.message));
    } catch (_) {
      if (token != _token) return;
      emit(state.copyWith(isLoading: false, errorKey: 'errors.unexpected'));
    }
  }

  /// Reads the rows already held again, in one request, instead of starting
  /// over at page 0.
  ///
  /// [load] after a change elsewhere costs a reader who scrolled four pages
  /// down everything below the first: the list shrinks to one page, the
  /// scroll offset lands past its end and the next pages are asked for again.
  /// This asks for as many rows as are held (whole pages, at most
  /// [maxRows], the server's page cap) and swaps them in where they stand.
  /// A failure keeps what is on screen; nothing is lost by it.
  Future<void> refreshLoaded({int maxRows = 100}) async {
    if (!state.hasData) return load();
    final token = ++_token;
    final pages = (state.items.length + pageSize - 1) ~/ pageSize;
    final size = (pages * pageSize).clamp(pageSize, maxRows);
    try {
      final result = await _fetch(0, size);
      if (token != _token) return;
      emit(
        PagedState<T>(
          items: result.items,
          total: result.total,
          page: result.items.isEmpty
              ? 0
              : (result.items.length - 1) ~/ pageSize,
        ),
      );
    } catch (_) {
      // What is on screen stands.
    }
  }

  /// Loads the next page and appends it. No-op while another load is running or
  /// when no more pages remain. A failed append silently stops the spinner,
  /// keeping the pages already loaded so the user can retry by scrolling again.
  Future<void> loadMore() async {
    if (state.isLoading ||
        state.isLoadingMore ||
        !state.hasData ||
        !state.hasMore) {
      return;
    }
    final token = _token;
    // Derived from the rows actually held, not from a counter that walks up on
    // its own. Pages are offsets, so a row removed locally shifts every
    // boundary below it: counting up from the last page fetched would then ask
    // for an offset past the rows the reader has, and whatever slid into the
    // gap would be requested by nobody. Asking for the page the held rows end
    // inside re-reads that boundary; [keyOf] discards the overlap.
    final next = state.items.length ~/ pageSize;
    emit(state.copyWith(isLoadingMore: true));
    try {
      final result = await _fetch(next, pageSize);
      // A refresh started while we were fetching — discard this stale page.
      if (token != _token) return;
      final merged = _append(state.items, result.items);
      if (result.items.isNotEmpty && merged.length == state.items.length) {
        // A whole page of rows the list already holds. That happens when the
        // ordering shifts under the reader, and without a stop here `hasMore`
        // would stay true forever — every scroll at the bottom asking again for
        // a page that adds nothing. Take the count as the truth instead.
        emit(
          state.copyWith(
            total: merged.length,
            page: next,
            isLoadingMore: false,
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          items: merged,
          total: result.total,
          page: next,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      if (token != _token) return;
      emit(state.copyWith(isLoadingMore: false));
    }
  }

  /// Replaces one loaded item in place, without going back to page 0.
  ///
  /// A correction to a row the reader is looking at should not cost them the
  /// pages they have already scrolled through: [load] starts over, which on a
  /// long list throws away everything below the fold, drops the scroll position
  /// and — because the list is suddenly short again — immediately asks for the
  /// next page. Needs [keyOf]; without it there is no way to say which item.
  void replaceItem(T item) {
    final key = keyOf;
    if (key == null) return;
    final id = key(item);
    emit(
      state.copyWith(
        items: [
          for (final existing in state.items)
            if (key(existing) == id) item else existing,
        ],
      ),
    );
  }

  /// [replaceItem] for several at once, in one emit: a bulk edit answers with
  /// every row it changed. Items not loaded here are ignored.
  void replaceItems(Iterable<T> items) {
    final key = keyOf;
    if (key == null) return;
    final byKey = {for (final item in items) key(item): item};
    if (byKey.isEmpty) return;
    emit(
      state.copyWith(
        items: [
          for (final existing in state.items) byKey[key(existing)] ?? existing,
        ],
      ),
    );
  }

  /// Drops one loaded item and counts one fewer, for the same reason.
  ///
  /// Safe to do mid-list because [loadMore] asks for the page the held rows end
  /// inside rather than counting pages up — see the note there.
  void removeItem(Object id) {
    final key = keyOf;
    if (key == null) return;
    final kept = [
      for (final existing in state.items)
        if (key(existing) != id) existing,
    ];
    if (kept.length == state.items.length) return;
    emit(state.copyWith(items: kept, total: state.total - 1));
  }

  /// Drops every loaded item [test] matches, in one emit, and counts that many
  /// fewer: a bulk change that takes forty rows out of a view repaints once,
  /// not forty times.
  void removeWhere(bool Function(T item) test) {
    final kept = [
      for (final existing in state.items)
        if (!test(existing)) existing,
    ];
    final removed = state.items.length - kept.length;
    if (removed == 0) return;
    emit(
      state.copyWith(
        items: kept,
        total: (state.total - removed).clamp(0, state.total),
      ),
    );
  }

  /// Puts rows back where [removeWhere] took them from: each [entries] index is
  /// the row's position in the list before it went. In one emit, counting that
  /// many more; a row that is somehow back already is left alone.
  void reinsert(List<({int index, T item})> entries) {
    final key = keyOf;
    final items = [...state.items];
    final present = key == null ? <Object>{} : {for (final i in items) key(i)};
    var added = 0;
    for (final entry in [...entries]..sort((a, b) => a.index - b.index)) {
      if (key != null && present.contains(key(entry.item))) continue;
      items.insert(entry.index.clamp(0, items.length), entry.item);
      added++;
    }
    if (added == 0) return;
    emit(state.copyWith(items: items, total: state.total + added));
  }

  List<T> _append(List<T> current, List<T> incoming) {
    if (keyOf == null) return [...current, ...incoming];
    final seen = {for (final item in current) keyOf!(item)};
    return [
      ...current,
      for (final item in incoming)
        if (seen.add(keyOf!(item))) item,
    ];
  }
}
