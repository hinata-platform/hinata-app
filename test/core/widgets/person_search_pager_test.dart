import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/widgets/person_search_pager.dart';

/// The paging behind every people search: debounced, a page at a time, each
/// person once, a late answer never over a newer one.
void main() {
  DirectoryUser user(int i) =>
      DirectoryUser(id: 'u$i', username: 'u$i', displayName: 'User $i');

  late List<({String query, int page})> calls;
  late Map<String, Completer<({List<DirectoryUser> items, int total})>> pending;

  PersonSearchPager pager({bool searchEmpty = true}) => PersonSearchPager(
    (query, {required page, required size}) {
      calls.add((query: query, page: page));
      final done = Completer<({List<DirectoryUser> items, int total})>();
      pending['$query/$page'] = done;
      return done.future;
    },
    pageSize: 2,
    searchEmpty: searchEmpty,
  );

  setUp(() {
    calls = [];
    pending = {};
  });

  testWidgets('a typed query is asked once the typing pauses', (tester) async {
    final p = pager();
    p.setQuery('a');
    p.setQuery('ab');
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls.single.query, 'ab');
    pending['ab/0']!.complete((items: [user(1), user(2)], total: 3));
    await tester.pump();
    expect(p.results.map((u) => u.id), ['u1', 'u2']);
    expect(p.hasMore, isTrue);
    p.dispose();
  });

  testWidgets('the next page appends each person once and then stops', (
    tester,
  ) async {
    final p = pager();
    p.refresh();
    pending['/0']!.complete((items: [user(1), user(2)], total: 3));
    await tester.pump();
    p.loadMore();
    pending['/1']!.complete((items: [user(2), user(3)], total: 3));
    await tester.pump();
    expect(p.results.map((u) => u.id), ['u1', 'u2', 'u3']);
    p.loadMore();
    expect(calls, hasLength(2));
    p.dispose();
  });

  testWidgets('a late answer never replaces a newer one', (tester) async {
    final p = pager();
    p.refresh();
    p.setQuery('x');
    await tester.pump(const Duration(milliseconds: 300));
    pending['x/0']!.complete((items: [user(9)], total: 1));
    await tester.pump();
    pending['/0']!.complete((items: [user(1)], total: 1));
    await tester.pump();
    expect(p.results.map((u) => u.id), ['u9']);
    p.dispose();
  });

  testWidgets('an empty query clears instead of searching when asked to', (
    tester,
  ) async {
    final p = pager(searchEmpty: false);
    p.setQuery('');
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, isEmpty);
    expect(p.results, isEmpty);
    expect(p.loading, isFalse);
    p.dispose();
  });

  testWidgets('a failure is kept as its message', (tester) async {
    final p = pager();
    p.refresh();
    pending['/0']!.completeError(ApiFailure('error.x'));
    await tester.pump();
    expect(p.error, 'error.x');
    expect(p.loading, isFalse);
    p.dispose();
  });
}
