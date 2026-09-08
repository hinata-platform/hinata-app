import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';

/// The two things a paged list has to survive: the reader changing a row that
/// is already loaded, and a server whose ordering moves under it. Both are
/// about what happens to the *rows nobody asked for again*.
void main() {
  PagedCubit<String> cubitOver(
    List<String> server, {
    int pageSize = 2,
    List<int>? asked,
  }) => PagedCubit<String>(
    (page, size) async {
      asked?.add(page);
      final start = page * size;
      return (
        items: start >= server.length
            ? const <String>[]
            : server.sublist(
                start,
                start + size > server.length ? server.length : start + size,
              ),
        total: server.length,
      );
    },
    pageSize: pageSize,
    keyOf: (item) => item,
  );

  test('replaceItem swaps one row and leaves the paging alone', () async {
    final cubit = cubitOver(['a', 'b', 'c', 'd']);
    await cubit.load();
    await cubit.loadMore();

    cubit.replaceItem('b');
    expect(cubit.state.items, ['a', 'b', 'c', 'd']);
    expect(cubit.state.page, 1);
    expect(cubit.state.total, 4);
  });

  test('a delete does not let the next page skip a row', () async {
    // Pages are offsets, so removing a row shifts every boundary below it. The
    // reader holds a+b; deleting b makes what was page 1 start one row early,
    // and without stepping the cursor back "c" would be the row nobody ever
    // asks for again.
    final server = ['a', 'b', 'c', 'd', 'e', 'f'];
    final asked = <int>[];
    final cubit = cubitOver(server, asked: asked);
    await cubit.load();
    expect(cubit.state.items, ['a', 'b']);

    server.remove('b');
    cubit.removeItem('b');
    expect(cubit.state.items, ['a']);
    expect(cubit.state.total, 5);

    await cubit.loadMore();
    expect(cubit.state.items, [
      'a',
      'c',
    ], reason: 'the boundary page is re-read and the overlap de-duplicated');

    await cubit.loadMore();
    await cubit.loadMore();
    expect(cubit.state.items, [
      'a',
      'c',
      'd',
      'e',
      'f',
    ], reason: 'nothing was skipped over');
    expect(cubit.state.hasMore, isFalse);
  });

  test('a page of rows already held ends the list instead of looping', () async {
    // A server that keeps answering with the same rows — an ordering that
    // shifted under the reader. `hasMore` compares length to total, so without
    // a stop every scroll at the bottom would ask again, forever.
    var calls = 0;
    final cubit = PagedCubit<String>(
      (page, size) async {
        calls++;
        return (items: const ['a', 'b'], total: 10);
      },
      pageSize: 2,
      keyOf: (item) => item,
    );

    await cubit.load();
    await cubit.loadMore();

    expect(cubit.state.items, ['a', 'b']);
    expect(cubit.state.total, 2, reason: 'the count is what was actually seen');
    expect(cubit.state.hasMore, isFalse);

    await cubit.loadMore();
    expect(calls, 2, reason: 'the list is done asking');
  });
}
