import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/features/board/load_when_shown.dart';

/// A list beneath a board reads nothing until it is shown again (HIN-114),
/// whichever way the board above it goes away. The board overview and a
/// project's boards both read through this.
void main() {
  late int loads;
  late GoRouter router;

  Future<void> pumpAt(WidgetTester tester, String location) async {
    loads = 0;
    router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/list',
          builder: (_, _) => _List(onLoad: () => loads++),
          routes: [
            GoRoute(path: 'board', builder: (_, _) => const Text('board')),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  _ListState list(WidgetTester tester) =>
      tester.state<_ListState>(find.byType(_List, skipOffstage: false));

  testWidgets('reads nothing beneath a board, and once a go returns to it', (
    tester,
  ) async {
    await pumpAt(tester, '/list/board');
    expect(loads, 0);

    // The way the shell's back button leaves a board it cannot pop.
    router.go('/list');
    await tester.pumpAndSettle();
    expect(loads, 1);
  });

  testWidgets('a change while covered is read once the board is popped', (
    tester,
  ) async {
    await pumpAt(tester, '/list');
    expect(loads, 1);

    router.go('/list/board');
    await tester.pumpAndSettle();
    list(tester).markStale();
    await tester.pump();
    expect(loads, 1);

    router.pop();
    await tester.pumpAndSettle();
    expect(loads, 2);
  });

  testWidgets('a change while shown is read at once, and only once', (
    tester,
  ) async {
    await pumpAt(tester, '/list');

    list(tester).markStale();
    await tester.pumpAndSettle();

    expect(loads, 2);
  });
}

class _List extends StatefulWidget {
  const _List({required this.onLoad});

  final VoidCallback onLoad;

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> with LoadWhenShown<_List> {
  @override
  Future<void> loadShown() async => widget.onLoad();

  @override
  Widget build(BuildContext context) => const Text('list');
}
