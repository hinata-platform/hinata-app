/// The planning reads a sprint on by itself once the end of its rows comes
/// within reach, the way the issue list does, and never a sprint whose end is
/// still far off.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/widgets/read_on_trigger.dart';
import 'package:hinata/features/board/issue_quick_create.dart';
import 'package:hinata/features/sprint/planning/sprint_planning_cubit.dart';
import 'package:hinata/features/sprint/sprint_planning_surface.dart';

const _first = Sprint(id: 's1', name: 'Sprint 1');
const _second = Sprint(id: 's2', name: 'Sprint 2');

/// A sprint with [loaded] of its [total] cards on screen.
SprintContainer _sprint(String id, {required int loaded, required int total}) =>
    SprintContainer(
      items: [
        for (var i = 0; i < loaded; i++)
          Issue(
            id: '$id-$i',
            projectId: 'p1',
            readableId: 'HIN-$i',
            title: 'Row $i',
            state: 'Open',
          ),
      ],
      total: total,
    );

void main() {
  /// Lays the planning out with the two sprints and returns the ids of the
  /// sprints it asks to read on, in the order it asks.
  Future<List<String>> pump(
    WidgetTester tester, {
    required SprintContainer first,
    required SprintContainer second,
    bool refreshing = false,
  }) async {
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final asked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        // Widget tests render raw i18n keys, which are wider than any real
        // label and overflow a sprint head's capacity cell for test reasons
        // alone. Scale the type down so the layout, not the key, is measured.
        builder: (context, view) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(0.5)),
          child: view!,
        ),
        home: Scaffold(
          body: SprintPlanningSurface(
            planning: SprintPlanningState(
              status: SprintPlanningStatus.ready,
              sprints: const [_first, _second],
              containers: {'s1': first, 's2': second},
              refreshing: refreshing,
            ),
            sprints: const [_first, _second],
            activeSprintId: null,
            backlogPageSize: 25,
            names: const {},
            avatars: const {},
            selected: const {},
            onPage: (_) {},
            onLoadMore: asked.add,
            onToggleSelect: (_) {},
            onClearSelection: () {},
            onOpenIssue: (_) {},
            onEstimate: (_) {},
            onMoveToSprint: (_, _) {},
            onBulkMove: (_) {},
            quickCreateSeed: (sprintId) =>
                IssueQuickCreateSeed(sprintId: sprintId),
            onCreated: (_) {},
            onStartSprint: (_) {},
            onCompleteSprint: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    return asked;
  }

  ScrollPosition planningOf(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  testWidgets(
    'a sprint whose rows end on screen reads on right away, one far below does not',
    (tester) async {
      final asked = await pump(
        tester,
        first: _sprint('s1', loaded: 3, total: 10),
        second: _sprint('s2', loaded: 80, total: 160),
      );

      expect(asked, ['s1']);
    },
  );

  testWidgets('a sprint reads on once its end is scrolled within reach', (
    tester,
  ) async {
    final asked = await pump(
      tester,
      first: _sprint('s1', loaded: 80, total: 160),
      second: _sprint('s2', loaded: 3, total: 3),
    );
    expect(asked, isEmpty);

    // Step down the first sprint, never past what the planning holds, until
    // the end of its rows comes within reach.
    final position = planningOf(tester);
    for (
      var step = 0;
      step < 40 && find.byType(ReadOnTrigger).evaluate().isEmpty;
      step++
    ) {
      position.jumpTo(position.pixels + 300);
      await tester.pump();
    }
    await tester.pump();

    expect(find.byType(ReadOnTrigger), findsOneWidget);
    expect(asked, ['s1']);
  });

  testWidgets(
    'a sprint that holds no more, or while the planning is read again, asks for nothing',
    (tester) async {
      final asked = await pump(
        tester,
        first: _sprint('s1', loaded: 3, total: 3),
        second: _sprint('s2', loaded: 3, total: 10),
        refreshing: true,
      );

      expect(asked, isEmpty);
      expect(find.byType(ReadOnTrigger), findsNothing);
    },
  );

  testWidgets(
    'a sprint whose page did not come asks again once the planning is scrolled',
    (tester) async {
      final asked = await pump(
        tester,
        first: _sprint('s1', loaded: 3, total: 10),
        second: _sprint('s2', loaded: 40, total: 40),
      );
      expect(asked, ['s1']);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -80));
      await tester.pump();

      expect(asked, ['s1', 's1']);
    },
  );
}
