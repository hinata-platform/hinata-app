import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/shell/swipe_back.dart';

/// The page under the edge swipe keeps its place in the tree while it is
/// dragged: it used to be re-parented the moment a drag began, which moved
/// the navigator's GlobalKey mid-layout and took the app down.
void main() {
  testWidgets('a drag from the edge moves the page without re-mounting it', (
    tester,
  ) async {
    var mounts = 0;
    var moves = 0;
    var backs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SwipeBackGesture(
          enabled: () => true,
          onBack: () => backs++,
          child: _Page(
            key: GlobalKey(),
            onMount: () => mounts++,
            onMove: () => moves++,
          ),
        ),
      ),
    );
    expect(mounts, 1);

    final gesture = await tester.startGesture(const Offset(10, 300));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
    // Not moved to another parent either: a GlobalKey would survive that,
    // but in the app the move happened inside a layout pass.
    expect(moves, 0);
    expect(mounts, 1);

    await gesture.moveBy(const Offset(300, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(mounts, 1);
    expect(moves, 0);
    expect(backs, 1);
  });
}

class _Page extends StatefulWidget {
  const _Page({super.key, required this.onMount, required this.onMove});

  final VoidCallback onMount;
  final VoidCallback onMove;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void deactivate() {
    widget.onMove();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
