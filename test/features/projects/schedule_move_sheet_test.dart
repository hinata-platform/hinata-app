import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/project_template_models.dart';
import 'package:hinata/features/projects/schedule_move_sheet.dart';

/// The sheet that stands between a date field and a hundred rewritten
/// deadlines.
///
/// What it has to get right is what it says about the deadlines it is *not*
/// touching. A number that appears without explanation — twelve move, fifteen
/// exist — reads as a bug; named, it is the promise the feature rests on.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  ScheduleMove move(String title, int day) => ScheduleMove(
    issueId: title,
    readableId: 'BFQ-$day',
    title: title,
    field: 'DUE',
    from: DateTime(2026, 10, day),
    to: DateTime(2026, 10, day + 7),
  );

  Widget host({
    required SchedulePreview preview,
    void Function(bool)? onResult,
    double width = 900,
  }) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: ElevatedButton(
              onPressed: () async {
                final confirmed = await showScheduleMoveSheet(
                  context,
                  preview: preview,
                  newEventDate: DateTime(2026, 11, 19),
                );
                onResult?.call(confirmed);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('it names the first deadlines and counts the rest', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        preview: SchedulePreview(
          eventDate: DateTime(2026, 11, 12),
          newEventDate: DateTime(2026, 11, 19),
          shiftDays: 7,
          moved: 12,
          named: 6,
          moves: [for (var i = 1; i <= 6; i++) move('Task $i', i)],
        ),
      ),
    );
    await open(tester);

    expect(find.text('Task 1'), findsOneWidget);
    expect(find.text('Task 6'), findsOneWidget);
    // Six named, twelve moving: the other six are counted, not listed.
    expect(find.text('projects.schedule.andMore'), findsOneWidget);
  });

  testWidgets('with nothing left over it does not say "and more"', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        preview: SchedulePreview(
          moved: 2,
          named: 2,
          moves: [move('Task 1', 1), move('Task 2', 2)],
        ),
      ),
    );
    await open(tester);

    expect(find.text('projects.schedule.andMore'), findsNothing);
  });

  testWidgets('the deadlines somebody typed are named, not just subtracted', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        preview: SchedulePreview(moved: 2, named: 1, manual: 3, moves: [
          move('Task 1', 1),
        ]),
      ),
    );
    await open(tester);

    expect(find.text('projects.schedule.staying'), findsOneWidget);
  });

  testWidgets('with none set by hand that line stays away', (tester) async {
    await tester.pumpWidget(
      host(preview: SchedulePreview(moved: 1, named: 1, moves: [move('T', 1)])),
    );
    await open(tester);

    expect(find.text('projects.schedule.staying'), findsNothing);
  });

  testWidgets('cancelling writes nothing', (tester) async {
    bool? confirmed;
    await tester.pumpWidget(
      host(
        preview: SchedulePreview(moved: 1, named: 1, moves: [move('T', 1)]),
        onResult: (value) => confirmed = value,
      ),
    );
    await open(tester);
    await tester.tap(find.text('common.cancel'));
    await tester.pumpAndSettle();

    expect(confirmed, isFalse);
  });

  testWidgets('confirming says so', (tester) async {
    bool? confirmed;
    await tester.pumpWidget(
      host(
        preview: SchedulePreview(moved: 1, named: 1, moves: [move('T', 1)]),
        onResult: (value) => confirmed = value,
      ),
    );
    await open(tester);
    await tester.tap(find.text('projects.schedule.confirm'));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
  });

  testWidgets('an empty preview still renders, saying nothing moves', (
    tester,
  ) async {
    // The screen never opens this sheet with nothing to show — it only opens
    // when hasChanges — but a sheet that threw on an empty list would turn a
    // race into a crash.
    await tester.pumpWidget(host(preview: const SchedulePreview()));
    await open(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('projects.schedule.moving'), findsOneWidget);
  });

  for (final width in <double>[360, 700, 1200]) {
    testWidgets('lays out without overflow at ${width}px', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        host(
          width: width,
          preview: SchedulePreview(
            eventDate: DateTime(2026, 11, 12),
            newEventDate: DateTime(2026, 11, 19),
            shiftDays: 7,
            moved: 40,
            named: 6,
            manual: 3,
            pending: 2,
            moves: [
              for (var i = 1; i <= 6; i++)
                move('A deadline with a fairly long title $i', i),
            ],
          ),
        ),
      );
      await open(tester);

      expect(tester.takeException(), isNull);
    });
  }
}
