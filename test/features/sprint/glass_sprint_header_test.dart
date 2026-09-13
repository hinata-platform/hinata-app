/// The active sprint's header lays itself out in the width it gets.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/widgets/hive_widgets.dart' show HiveProgress;
import 'package:hinata/features/sprint/widgets/glass_sprint_header.dart';

void main() {
  final today = DateTime.now();
  final sprint = Sprint(
    id: 's1',
    name: 'Sprint 24',
    goal: 'Board views v2 and the honey-amber redesign',
    startDate: today.subtract(const Duration(days: 11)),
    endDate: today.add(const Duration(days: 3)),
  );

  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view
      ..physicalSize = Size(width, 400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [GlassSprintHeader(sprint: sprint)],
          ),
        ),
      ),
    );
  }

  testWidgets('a window between phone and desktop does not run past its edge', (
    tester,
  ) async {
    // The width of a desktop window dragged narrow: the desktop's layout class,
    // and too little room for the card and its progress side by side.
    await pumpAt(tester, 700);

    expect(tester.takeException(), isNull);
  });

  testWidgets('with little room the progress moves under the name', (
    tester,
  ) async {
    await pumpAt(tester, 620);

    expect(
      tester.getTopLeft(find.byType(HiveProgress)).dy,
      greaterThan(tester.getBottomLeft(find.text('Sprint 24')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('with room the progress sits beside the card', (tester) async {
    await pumpAt(tester, 1400);

    expect(
      tester.getTopLeft(find.byType(HiveProgress)).dx,
      greaterThan(tester.getTopRight(find.text('Sprint 24')).dx),
    );
  });
}
