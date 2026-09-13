/// A page's tools on a wide window, in the room the window actually leaves
/// them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/glass_filter_bar.dart';

void main() {
  const views = Key('views');
  const search = Key('search');
  const filter = Key('filter');

  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view
      ..physicalSize = Size(width, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WideToolbar(
                leading: [SizedBox(key: views, width: 380, height: 42)],
                trailing: [
                  SizedBox(key: search, width: 260, height: 42),
                  SizedBox(width: 170, height: 36),
                  SizedBox(key: filter, width: 110, height: 36),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('keeps one line while everything fits', (tester) async {
    await pumpAt(tester, 1200);

    expect(
      tester.getCenter(find.byKey(filter)).dy,
      moreOrLessEquals(tester.getCenter(find.byKey(views)).dy),
    );
    expect(tester.getTopRight(find.byKey(filter)).dx, 1200);
  });

  testWidgets('moves the trailing tools to a line of their own, uncut', (
    tester,
  ) async {
    // A window dragged narrower passes through this width, and a single
    // scrolling line clipped a board's search field and its filter here.
    await pumpAt(tester, 800);

    expect(
      tester.getTopLeft(find.byKey(search)).dy,
      greaterThan(tester.getBottomLeft(find.byKey(views)).dy),
    );
    expect(tester.getTopRight(find.byKey(filter)).dx, lessThanOrEqualTo(800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wraps the tools among themselves when their line is short', (
    tester,
  ) async {
    await pumpAt(tester, 480);

    expect(
      tester.getTopLeft(find.byKey(filter)).dy,
      greaterThan(tester.getTopLeft(find.byKey(search)).dy),
    );
    expect(tester.takeException(), isNull);
  });
}
