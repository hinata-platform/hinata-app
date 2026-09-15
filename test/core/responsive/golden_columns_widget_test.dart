import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/responsive/golden_columns.dart';

/// The weights are where a page starts; the cards' real heights decide where
/// they end, and after that the arrangement holds still.
void main() {
  Widget host(Map<String, double> heights, {double width = 1200}) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: GoldenColumns<String>(
                // The estimates say all three stand alike.
                groups: [
                  for (final name in heights.keys)
                    GoldenGroup([name], weight: 1),
                ],
                card: (name) =>
                    SizedBox(key: ValueKey(name), height: heights[name]),
              ),
            ),
          ),
        ),
      );

  double left(WidgetTester tester, String name) =>
      tester.getTopLeft(find.byKey(ValueKey(name))).dx;

  // The default test surface is 800 wide, where every page is one column.
  void wideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('once measured, the columns follow the real heights', (
    tester,
  ) async {
    wideSurface(tester);
    await tester.pumpWidget(host({'a': 900, 'b': 100, 'c': 100}));

    // By the estimates the tall card shares its column with a short one.
    expect(left(tester, 'c'), left(tester, 'a'));

    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Measured, the tall card stands alone and the two short ones share.
    expect(left(tester, 'c'), left(tester, 'b'));
    expect(left(tester, 'a'), isNot(left(tester, 'b')));
  });

  testWidgets('a card that grows after the page settled does not move', (
    tester,
  ) async {
    wideSurface(tester);
    await tester.pumpWidget(host({'a': 900, 'b': 100, 'c': 100}));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final before = left(tester, 'c');

    await tester.pumpWidget(host({'a': 100, 'b': 100, 'c': 900}));
    await tester.pump(const Duration(seconds: 1));

    expect(left(tester, 'c'), before);
  });

  testWidgets('a narrow page stacks the cards in one column', (tester) async {
    wideSurface(tester);
    await tester.pumpWidget(host({'a': 900, 'b': 100, 'c': 100}, width: 600));
    await tester.pump(const Duration(seconds: 1));

    expect(left(tester, 'a'), left(tester, 'b'));
    expect(left(tester, 'b'), left(tester, 'c'));
  });
}
