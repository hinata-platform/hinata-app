import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/router/board_routes.dart';
import 'package:hinata/features/board/board_links.dart';
import 'package:hinata/features/board/board_screen.dart';
import 'package:hinata/features/board/boards_screen.dart';
import 'package:hinata/features/board/project_boards_screen.dart';

/// HIN-114: a board has an address of its own. Opening one writes it into the
/// location, a reload of that location comes back to the board, and back leads
/// to the list it was opened from.
///
/// The screens are not mounted, because they need the repositories. What the
/// routes decide is which screens stand where, and that is recorded here.
void main() {
  late List<Widget> built;
  late GoRouter router;

  setUp(() => built = []);

  Future<void> pumpAt(WidgetTester tester, String location) async {
    router = GoRouter(
      initialLocation: location,
      routes: boardRoutes((state, child) {
        built.add(child);
        return NoTransitionPage<void>(
          key: state.pageKey,
          child: Text(state.uri.path),
        );
      }),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  Future<void> go(WidgetTester tester, String location) async {
    router.go(location);
    await tester.pumpAndSettle();
  }

  Future<void> pop(WidgetTester tester) async {
    router.pop();
    await tester.pumpAndSettle();
  }

  testWidgets('a board opened from the overview is in the address', (
    tester,
  ) async {
    await pumpAt(tester, boardsLocation);

    await go(tester, boardLocation('b1'));

    expect(router.state.uri.path, '/board/b1');
    expect(router.canPop(), isTrue);
    await pop(tester);
    expect(router.state.uri.path, '/board');
  });

  testWidgets('a reload comes back to the board, with the overview beneath', (
    tester,
  ) async {
    await pumpAt(tester, '/board/b1');

    expect(router.state.uri.path, '/board/b1');
    expect(router.canPop(), isTrue);
    expect(built.whereType<BoardScreen>(), isNotEmpty);
    expect(built.whereType<KanbanBoardScreen>().last.boardId, 'b1');
  });

  testWidgets('the old address forwards to the board', (tester) async {
    await pumpAt(tester, '/boards/b1');

    expect(router.state.uri.path, '/board/b1');
  });

  testWidgets('a board opened from a project leads back to its boards', (
    tester,
  ) async {
    await pumpAt(tester, '/projects/p1/boards');

    await go(tester, projectBoardLocation('p1', 'b1'));

    expect(router.state.uri.path, '/projects/p1/boards/b1');
    expect(built.whereType<ProjectBoardsScreen>().last.projectId, 'p1');
    expect(
      built.whereType<KanbanBoardScreen>().last.key,
      const ValueKey('board-b1'),
    );
    await pop(tester);
    expect(router.state.uri.path, '/projects/p1/boards');
  });

  testWidgets('keys each board screen by its id', (tester) async {
    await pumpAt(tester, '/board/b1');

    await go(tester, boardLocation('b2'));

    // The page key is the same for both, so only the widget key keeps the first
    // board's state from showing under the second board's address.
    final boards = built.whereType<KanbanBoardScreen>();
    expect(boards.first.key, const ValueKey('board-b1'));
    expect(boards.last.key, const ValueKey('board-b2'));
  });

  testWidgets('an id stays a board, whatever it spells', (tester) async {
    await pumpAt(tester, '/boards/..%2F..%2Fadmin%2Fusers');

    expect(router.state.pathParameters['id'], '../../admin/users');
    expect(
      built.whereType<KanbanBoardScreen>().last.boardId,
      '../../admin/users',
    );
  });

  group('board links', () {
    test('name the board, encoded', () {
      expect(boardLocation('b1'), '/board/b1');
      expect(boardLocation('a/b'), '/board/a%2Fb');
      expect(projectBoardLocation('p 1', 'b1'), '/projects/p%201/boards/b1');
    });

    test('fall back to a list without a usable id', () {
      expect(boardLocation(''), boardsLocation);
      expect(boardLocation('..'), boardsLocation);
      expect(boardLocation('.'), boardsLocation);
      expect(projectBoardLocation('p1', '..'), '/projects/p1/boards');
      expect(projectBoardLocation('..', 'b1'), '/board/b1');
    });
  });
}
