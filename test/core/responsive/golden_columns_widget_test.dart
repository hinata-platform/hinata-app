import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/responsive/golden_columns.dart';

/// Where a card sits is decided by what the page declares and by how many
/// columns fit — and by nothing else. These tests are the guard on that: the
/// page used to measure its cards and re-arrange itself around the real
/// heights, which meant a card moved when its data arrived, and sat somewhere
/// else for the next project. Every case below would pass again the moment
/// somebody puts that back.
void main() {
  Widget host(
    Map<String, double> heights, {
    double width = 1200,
    Set<String> leads = const {},
  }) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: width,
          child: GoldenColumns<String>(
            groups: [
              for (final name in heights.keys)
                GoldenGroup([name], weight: 1, lead: leads.contains(name)),
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

  List<double> lefts(WidgetTester tester, Iterable<String> names) => [
    for (final name in names) left(tester, name),
  ];

  // The default test surface is 800 wide, where every page is one column.
  void wideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the columns do not depend on how tall the cards are', (
    tester,
  ) async {
    wideSurface(tester);
    await tester.pumpWidget(host({'a': 900, 'b': 100, 'c': 100}));
    await tester.pump(const Duration(seconds: 1));
    final tall = lefts(tester, ['a', 'b', 'c']);

    await tester.pumpWidget(host({'a': 100, 'b': 100, 'c': 900}));
    await tester.pump(const Duration(seconds: 1));

    expect(lefts(tester, ['a', 'b', 'c']), tall);
  });

  testWidgets('a card that grows while the page loads stays where it is', (
    tester,
  ) async {
    wideSurface(tester);
    await tester.pumpWidget(host({'a': 100, 'b': 100, 'c': 100}));
    final before = lefts(tester, ['a', 'b', 'c']);

    // Its data landed: the card is now nine times as tall as it was.
    await tester.pumpWidget(host({'a': 100, 'b': 100, 'c': 900}));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    expect(lefts(tester, ['a', 'b', 'c']), before);
  });

  testWidgets('the first frame is the arrangement the page keeps', (
    tester,
  ) async {
    wideSurface(tester);
    await tester.pumpWidget(host({'a': 900, 'b': 100, 'c': 100}));
    final first = lefts(tester, ['a', 'b', 'c']);

    // Nothing arrives, nothing is touched — and nothing moves, so there is no
    // second arrangement for the eye to follow.
    await tester.pump(const Duration(seconds: 15));

    expect(lefts(tester, ['a', 'b', 'c']), first);
  });

  testWidgets('a lead card opens the first column however light it is', (
    tester,
  ) async {
    wideSurface(tester);
    await tester.pumpWidget(host({'a': 900, 'b': 900, 'c': 10}, leads: {'c'}));

    final corner = tester.getTopLeft(find.byKey(const ValueKey('c')));
    // Leftmost column, and the first card in it — the one position on a page
    // somebody is allowed to rely on.
    expect(corner.dx, lefts(tester, ['a', 'b', 'c']).reduce(math.min));
    expect(corner.dy, lessThan(20));
  });

  testWidgets('a card keeps its state when the window changes the columns', (
    tester,
  ) async {
    wideSurface(tester);
    await tester.pumpWidget(host({'a': 100, 'b': 100, 'c': 100}));
    final wide = left(tester, 'c');

    await tester.pumpWidget(host({'a': 100, 'b': 100, 'c': 100}, width: 600));
    await tester.pump();

    // One column now: everything stacks at the same edge.
    expect(left(tester, 'a'), left(tester, 'b'));
    expect(left(tester, 'b'), left(tester, 'c'));

    // And back, to exactly where it was.
    await tester.pumpWidget(host({'a': 100, 'b': 100, 'c': 100}));
    await tester.pump();
    expect(left(tester, 'c'), wide);
  });

  testWidgets('a narrow page stacks the cards in one column', (tester) async {
    wideSurface(tester);
    await tester.pumpWidget(host({'a': 900, 'b': 100, 'c': 100}, width: 600));
    await tester.pump(const Duration(seconds: 1));

    expect(left(tester, 'a'), left(tester, 'b'));
    expect(left(tester, 'b'), left(tester, 'c'));
  });
}
