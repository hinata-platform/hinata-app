import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/core_models.dart';

/// One page of people for [query].
typedef PersonPage =
    Future<({List<DirectoryUser> items, int total})> Function(
      String query, {
      required int page,
      required int size,
    });

/// The paging behind every people search: the query, debounced; the pages,
/// each person once; and the rule that a late answer never lands over a newer
/// one. The people picker and the share dialog both read it, so the two
/// cannot drift apart.
class PersonSearchPager extends ChangeNotifier {
  PersonSearchPager(
    this._search, {
    this.pageSize = 25,
    this.debounce = const Duration(milliseconds: 180),
    this.searchEmpty = true,
  });

  final PersonPage _search;
  final int pageSize;
  final Duration debounce;

  /// Whether an empty query lists everybody (the picker) or nobody (the share
  /// dialog, which shows its own sections until something is typed).
  final bool searchEmpty;

  final List<DirectoryUser> _results = [];

  /// Ids already in [results]: somebody can shift across a page boundary while
  /// paging, and the same face twice reads as a bug.
  final Set<String> _seen = {};

  Timer? _timer;
  String _query = '';
  int _page = 0;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;

  /// Set once the server hands back a short page, so a total that never quite
  /// matches what is on screen cannot keep asking for a page that is not there.
  bool _exhausted = false;
  String? _error;

  /// Monotonic request token: an answer for an older request is dropped.
  int _seq = 0;
  bool _disposed = false;

  List<DirectoryUser> get results => List.unmodifiable(_results);
  String get query => _query;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;
  bool get hasMore => !_exhausted && _results.length < _total;

  /// Takes a new query and searches once typing pauses.
  void setQuery(String value) {
    _query = value.trim();
    _timer?.cancel();
    if (_query.isEmpty && !searchEmpty) {
      _seq++;
      _results.clear();
      _seen.clear();
      _loading = false;
      _loadingMore = false;
      _error = null;
      _notify();
      return;
    }
    _timer = Timer(debounce, refresh);
  }

  /// Searches [query] from its first page now.
  Future<void> refresh() => _run(reset: true);

  /// Appends the next page, if there is one and nothing is in flight.
  Future<void> loadMore() async {
    if (_loading || _loadingMore || !hasMore) return;
    await _run(reset: false);
  }

  Future<void> _run({required bool reset}) async {
    if (reset) _timer?.cancel();
    final seq = ++_seq;
    final page = reset ? 0 : _page + 1;
    if (reset) {
      _loading = true;
    } else {
      _loadingMore = true;
    }
    _error = null;
    _notify();
    try {
      final result = await _search(_query, page: page, size: pageSize);
      if (_disposed || seq != _seq) return;
      if (reset) {
        _results.clear();
        _seen.clear();
      }
      for (final user in result.items) {
        if (_seen.add(user.id)) _results.add(user);
      }
      _page = page;
      _total = result.total;
      _exhausted = result.items.length < pageSize;
    } on ApiFailure catch (failure) {
      if (_disposed || seq != _seq) return;
      _error = failure.message;
    }
    _loading = false;
    _loadingMore = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
