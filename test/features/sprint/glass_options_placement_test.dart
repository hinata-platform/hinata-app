/// Where a single-choice picker opens: never as a sheet from the bottom edge
/// of a wide window.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/sprint/modals/glass_modal.dart';

void main() {
  Future<void> open(WidgetTester tester, Size size, {Rect? anchor}) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showGlassOptions<String>(
                  context,
                  title: 'Gemessen an',
                  anchorRect: anchor,
                  options: const [(value: 'a', child: Text('Erlös'))],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('wide and anchored, it hangs off the control', (tester) async {
    await open(
      tester,
      const Size(1200, 800),
      anchor: const Rect.fromLTWH(500, 100, 200, 44),
    );
    expect(find.text('Erlös'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    // Close to the control, nowhere near the bottom edge.
    expect(tester.getTopLeft(find.text('Erlös')).dy, lessThan(400));
  });

  testWidgets('wide without an anchor, a card in the middle, not a sheet', (
    tester,
  ) async {
    await open(tester, const Size(1200, 800));
    expect(find.text('Erlös'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('on a phone it stays a sheet', (tester) async {
    await open(tester, const Size(390, 844));
    expect(find.byType(BottomSheet), findsOneWidget);
  });
}
