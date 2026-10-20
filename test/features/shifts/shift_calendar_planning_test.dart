import 'dart:async';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kDoubleTapMinTime, kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/shift_models.dart';
import 'package:hinata/core/widgets/time_grid/time_grid.dart';
import 'package:hinata/core/widgets/time_grid/time_month_grid.dart';
import 'package:hinata/features/shifts/bloc/shift_actions_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_calendar_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_changes.dart';
import 'package:hinata/features/shifts/bloc/shift_editor_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_event_editor_cubit.dart';
import 'package:hinata/features/shifts/shift_zones.dart';
import 'package:hinata/features/shifts/view/shift_calendar_view.dart';
import 'package:hinata/features/shifts/widgets/shift_editor.dart';
import 'package:hinata/features/shifts/widgets/shift_event_editor.dart';

import 'shift_fakes.dart';

/// The calendar as a place to plan (HIN-166): sweeping a span, the "+" in
/// the week, the day and the month, and which event a new shift goes into.
void main() {
  late FakeShiftRepository repo;

  setUp(() => repo = FakeShiftRepository());

  /// An event of a project the caller plans, in the device's own zone so
  /// the editors need no zone database.
  ShiftEventSummary event(
    String id, {
    required DateTime start,
    required DateTime end,
    String projectId = 'p1',
    bool canPlan = true,
    bool cancelled = false,
    String? seriesId,
    String title = 'Messe',
  }) => ShiftEventSummary(
    id: id,
    projectId: projectId,
    title: title,
    startsAt: start,
    endsAt: end,
    startsLocal: start,
    endsLocal: end,
    canPlan: canPlan,
    cancelled: cancelled,
    seriesId: seriesId,
    recurrenceLabel: seriesId == null ? null : 'wöchentlich',
  );

  final fair = event(
    'e1',
    start: DateTime(2026, 10, 24, 8),
    end: DateTime(2026, 10, 24, 20),
  );
  final dinner = event(
    'e2',
    title: 'Vereinsabend',
    start: DateTime(2026, 10, 24, 18),
    end: DateTime(2026, 10, 24, 23),
  );

  /// The calendar's heads for [events], with project and span (HIN-166).
  Map<String, ShiftEventHead> heads(List<ShiftEventSummary> events) => {
    for (final e in events)
      e.id: ShiftEventHead(
        id: e.id,
        title: e.title,
        location: e.location,
        timezone: e.timezone,
        cancelled: e.cancelled,
        seriesId: e.seriesId,
        recurrenceLabel: e.recurrenceLabel,
        projectId: e.projectId,
        startsAt: e.startsAt,
        endsAt: e.endsAt,
        startsLocal: e.startsLocal,
        endsLocal: e.endsLocal,
      ),
  };

  group('ShiftCreateTarget', () {
    ShiftCreateTarget resolve(
      List<ShiftEventSummary> held, {
      DateTime? start,
      DateTime? end,
      Set<String> plannable = const {'p1', 'p2'},
      String? projectId,
      bool wholeDay = false,
    }) => ShiftCreateTarget.resolve(
      start: start ?? DateTime(2026, 10, 24, 10),
      end: end ?? DateTime(2026, 10, 24, 12),
      held: held,
      plannable: plannable,
      projectId: projectId,
      wholeDay: wholeDay,
    );

    test('none, one, several', () {
      expect(resolve(const []).none, isTrue);
      expect(resolve([fair, dinner]).only, fair);
      final both = resolve(
        [dinner, fair],
        start: DateTime(2026, 10, 24, 18),
        end: DateTime(2026, 10, 24, 19),
      );
      expect(both.events, [fair, dinner]);
      expect(both.only, isNull);
    });

    test('a span partly outside its event still offers it, uncut', () {
      final target = resolve(
        [fair],
        start: DateTime(2026, 10, 24, 19),
        end: DateTime(2026, 10, 24, 22),
      );
      expect(target.only, fair);
      expect(target.spanFor(fair), (
        start: DateTime(2026, 10, 24, 19),
        end: DateTime(2026, 10, 24, 22),
      ));
    });

    test('the project filter narrows, and an event nobody here plans is '
        'never offered', () {
      final other = event(
        'e3',
        projectId: 'p2',
        start: DateTime(2026, 10, 24, 9),
        end: DateTime(2026, 10, 24, 11),
      );
      expect(resolve([fair, other], projectId: 'p2').only, other);
      // The server says the caller does not plan it.
      final foreign = event(
        'e4',
        canPlan: false,
        start: DateTime(2026, 10, 24, 9),
        end: DateTime(2026, 10, 24, 11),
      );
      expect(resolve([foreign]).none, isTrue);
      // Its project is not among the planned ones.
      expect(resolve([other], plannable: const {'p1'}).none, isTrue);
      final cancelled = event(
        'e5',
        cancelled: true,
        start: DateTime(2026, 10, 24, 9),
        end: DateTime(2026, 10, 24, 11),
      );
      expect(resolve([cancelled]).none, isTrue);
    });

    test('by the day, an hour that misses the event moves into it', () {
      final target = resolve(
        [dinner],
        start: DateTime(2026, 10, 24, 10),
        end: DateTime(2026, 10, 24, 11),
        wholeDay: true,
      );
      expect(target.only, dinner);
      expect(target.spanFor(dinner), (
        start: DateTime(2026, 10, 24, 18),
        end: DateTime(2026, 10, 24, 19),
      ));
    });
  });

  group('ShiftCalendarCubit planning', () {
    late StreamController<ShiftChange> bus;

    setUp(() {
      bus = StreamController<ShiftChange>.broadcast();
      addTearDown(bus.close);
    });

    ShiftCalendarCubit calendar({String? projectId}) => ShiftCalendarCubit(
      repo,
      focused: DateTime(2026, 10, 24),
      projectId: projectId,
      changes: bus.stream,
    );

    test(
      'a planner reads the months and nothing else; events come with them',
      () async {
        final helper = calendar();
        addTearDown(helper.close);
        await helper.start();
        await Future<void>.delayed(Duration.zero);
        expect(helper.state.canCreate, isFalse);

        repo.calls.clear();
        repo.calendarAll = ShiftCalendar(
          events: heads([fair]),
          plannableProjectIds: const {'p1'},
        );
        final planner = calendar();
        addTearDown(planner.close);
        await planner.start();
        await Future<void>.delayed(Duration.zero);
        expect(repo.calls, [
          'calendar:202609:all',
          'calendar:202610:all',
          'calendar:202611:all',
        ]);
        expect(planner.state.canCreate, isTrue);

        // Finding the event asks for nothing.
        final before = repo.calls.length;
        final target = planner.createTarget(
          DateTime(2026, 10, 24, 10),
          DateTime(2026, 10, 24, 11),
        );
        expect(target.only, fair);
        expect(repo.calls.length, before);
      },
    );

    test(
      'a filter on a project the caller does not plan offers nothing',
      () async {
        repo.calendarAll = ShiftCalendar(
          events: heads([fair]),
          plannableProjectIds: const {'p1'},
        );
        final cubit = calendar(projectId: 'p2');
        addTearDown(cubit.close);
        await cubit.start();
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state.canCreate, isFalse);
        expect(
          cubit
              .createTarget(
                DateTime(2026, 10, 24, 10),
                DateTime(2026, 10, 24, 11),
              )
              .none,
          isTrue,
        );
      },
    );

    test(
      'a new shift goes in from the answer, without reading the month',
      () async {
        repo.calendarAll = ShiftCalendar(
          events: heads([fair]),
          plannableProjectIds: const {'p1'},
        );
        final cubit = calendar();
        addTearDown(cubit.close);
        await cubit.start();
        await Future<void>.delayed(Duration.zero);
        repo.calls.clear();

        final created = sampleShift(
          id: 'new',
          title: 'Aufbau',
          start: DateTime(2026, 10, 24, 9),
        );
        bus.add(ShiftChange(shiftId: 'new', shift: created));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(cubit.shiftsOn(DateTime(2026, 10, 24)).map((s) => s.id), [
          'new',
        ]);
        // Its event is named from the planner's events.
        expect(cubit.eventOf(created)?.title, 'Messe');
        expect(repo.calls.where((c) => c.startsWith('calendar:')), isEmpty);
      },
    );

    test(
      'a week opens an hour before its first shift, else at eight',
      () async {
        repo.calendarMonths[202610] = ShiftCalendar(
          shifts: [
            sampleShift(id: 'a', start: DateTime(2026, 10, 21, 13)),
            sampleShift(id: 'b', start: DateTime(2026, 10, 23, 6, 30)),
          ],
          events: const {'e1': sampleEvent},
        );
        final cubit = calendar();
        addTearDown(cubit.close);
        final week = [for (var i = 0; i < 7; i++) DateTime(2026, 10, 19 + i)];
        expect(cubit.holds(week), isFalse);
        await cubit.start();
        expect(cubit.holds(week), isTrue);
        expect(cubit.scrollHourFor(week), 5);
        final next = [for (var i = 0; i < 7; i++) DateTime(2026, 10, 26 + i)];
        expect(cubit.scrollHourFor(next), 8);
      },
    );
  });

  test('a head reads its project and span; the marks who plans', () {
    final head = ShiftEventHead.fromJson(const {
      'id': 'e1',
      'title': 'Messe',
      'projectId': 'p1',
      'startsAt': '2026-10-24T06:00:00Z',
      'endsAt': '2026-10-24T18:00:00Z',
      'startsLocal': '2026-10-24T08:00:00',
      'endsLocal': '2026-10-24T20:00:00',
      'timezone': 'Europe/Berlin',
    });
    expect(head.startsLocal, DateTime(2026, 10, 24, 8));
    final summary = head.toSummary(canPlan: true)!;
    expect(summary.projectId, 'p1');
    expect(summary.startsAt, DateTime.utc(2026, 10, 24, 6).toLocal());
    expect(ShiftEventHead.fromJson(head.toJson()), head);
    // And back: an event the calendar learnt from an editor keeps its span.
    expect(summary.toHead(), head);
    expect(
      ShiftEventHead.fromJson(const {
        'id': 'old',
        'title': 'x',
      }).toSummary(canPlan: true),
      isNull,
    );
    final marks = ShiftCalendarMarks.fromJson(const {
      'days': [
        {'date': '2026-10-24', 'open': 2},
      ],
      'plannableProjectIds': ['p1'],
    });
    expect(marks.days.single.open, 2);
    expect(marks.plannableProjectIds, {'p1'});
  });

  test(
    'the month learns who plans from its marks, asking nothing else',
    () async {
      repo.plannable = const {'p1'};
      final cubit = ShiftCalendarCubit(
        repo,
        focused: DateTime(2026, 10, 24),
        span: ShiftCalendarSpan.month,
      );
      addTearDown(cubit.close);
      await cubit.start();
      expect(repo.calls, [
        'marks:202609:all',
        'marks:202610:all',
        'marks:202611:all',
      ]);
      expect(cubit.state.canCreate, isTrue);
    },
  );

  group('ShiftEditorCubit', () {
    test(
      'a span opens with exactly its time; a batch says each new shift',
      () async {
        final bus = <ShiftChange>[];
        final sub = ShiftChanges.instance.changes.listen(bus.add);
        addTearDown(sub.cancel);
        final cubit = ShiftEditorCubit(
          repo,
          event: fair,
          day: DateTime(2026, 10, 24),
          start: DateTime(2026, 10, 24, 14, 15),
          end: DateTime(2026, 10, 24, 16, 45),
        );
        addTearDown(cubit.close);
        expect(cubit.state.day, DateTime(2026, 10, 24));
        expect(cubit.state.fromMinutes, 14 * 60 + 15);
        expect(cubit.state.toMinutes, 16 * 60 + 45);
        expect(cubit.state.requiredHelpers, 1);

        repo.createdShifts = [
          sampleShift(id: 'x'),
          sampleShift(id: 'y', start: DateTime(2026, 10, 25, 14)),
        ];
        cubit.setTitle('Kasse');
        expect(await cubit.save(), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(bus.map((c) => c.shiftId), ['x', 'y']);
      },
    );

    test('outside the event it says so instead of cutting', () async {
      final cubit = ShiftEditorCubit(
        repo,
        event: fair,
        start: DateTime(2026, 10, 24, 19),
        end: DateTime(2026, 10, 24, 22),
      );
      addTearDown(cubit.close);
      expect(cubit.state.toMinutes, 22 * 60);
      expect(cubit.problem, ShiftEditorProblem.outsideEvent);
    });
  });

  test('the event editor opens on a swept span', () {
    final cubit = ShiftEventEditorCubit(
      repo,
      projectId: 'p1',
      start: DateTime(2026, 10, 24, 9),
      end: DateTime(2026, 10, 24, 12, 30),
    );
    addTearDown(cubit.close);
    expect(cubit.state.start, DateTime(2026, 10, 24, 9));
    expect(cubit.state.end, DateTime(2026, 10, 24, 12, 30));
    expect(cubit.state.projectId, 'p1');
  });

  group('Calendar', () {
    late ShiftActionsCubit actions;

    setUp(() {
      actions = ShiftActionsCubit(repo);
      addTearDown(actions.close);
    });

    // The device's zone is asked of the platform once; asked here, outside
    // the fake clock, the editors find it answered.
    setUpAll(() => ShiftZones.deviceZone());

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<ShiftCalendarCubit> pumpCalendar(
      WidgetTester tester, {
      double width = 1280,
      double scale = 1,
      bool planner = true,
      List<ShiftEventSummary>? events,
      String? projectId,
      ShiftCalendarSpan span = ShiftCalendarSpan.week,
    }) async {
      repo
        ..calendarAll = ShiftCalendar(
          shifts: [
            sampleShift(
              id: 'old',
              title: 'Empfang',
              start: DateTime(2026, 10, 22, 9),
            ),
          ],
          events: {
            'e1': sampleEvent,
            ...heads(events ?? [fair]),
          },
          plannableProjectIds: planner ? const {'p1'} : const {},
        )
        ..plannable = planner ? const {'p1'} : const {};
      final cubit = ShiftCalendarCubit(
        repo,
        focused: DateTime(2026, 10, 24),
        span: span,
        projectId: projectId,
      );
      addTearDown(cubit.close);
      await cubit.start();
      await pumpShiftsUi(
        tester,
        BlocProvider.value(
          value: cubit,
          child: ShiftCalendarView(
            now: DateTime(2026, 10, 20, 9, 20),
            deviceZone: 'Europe/Berlin',
          ),
        ),
        repository: repo,
        width: width,
        height: 900,
        scale: scale,
        blocs: [BlocProvider<ShiftActionsCubit>.value(value: actions)],
      );
      await settle(tester);
      return cubit;
    }

    TimeGrid grid(WidgetTester tester) =>
        tester.widget<TimeGrid>(find.byType(TimeGrid).first);

    ShiftEditorCubit editor(WidgetTester tester) => BlocProvider.of(
      tester.element(find.byType(ShiftEditorBody)),
      listen: false,
    );

    testWidgets('a sweep opens the shift editor on exactly that time and '
        'its event; once saved the block is there without a reload', (
      tester,
    ) async {
      await pumpCalendar(tester);
      grid(tester).onCreate!((
        start: DateTime(2026, 10, 24, 10, 15),
        end: DateTime(2026, 10, 24, 12),
      ));
      await settle(tester);
      expect(find.byType(ShiftEditorBody), findsOneWidget);
      final form = editor(tester);
      expect(form.event, fair);
      expect(form.state.day, DateTime(2026, 10, 24));
      expect(form.state.fromMinutes, 10 * 60 + 15);
      expect(form.state.toMinutes, 12 * 60);

      repo.calls.clear();
      repo.createdShifts = [
        sampleShift(
          id: 'new',
          title: 'Aufbau',
          start: DateTime(2026, 10, 24, 10, 15),
          length: const Duration(minutes: 105),
        ),
      ];
      await tester.enterText(find.byType(TextField).first, 'Aufbau');
      await tester.tap(find.text('Speichern'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      expect(find.byType(ShiftEditorBody), findsNothing);
      expect(find.text('Aufbau · fehlt 1'), findsOneWidget);
      expect(repo.calls, ['createShifts:e1:1']);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a mouse sweep plans for a planner and does nothing for a '
        'helper', (tester) async {
      Future<void> sweep() async {
        final canvas = tester.getRect(find.byType(TimeGrid).first);
        final gesture = await tester.startGesture(
          Offset(canvas.left + kTimeGridGutter + 400, canvas.top + 260),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(0, 80));
        await tester.pump();
        await gesture.up();
        await settle(tester);
      }

      await pumpCalendar(tester, planner: false);
      expect(grid(tester).onCreate, isNull);
      await sweep();
      expect(find.byType(ShiftEditorBody), findsNothing);
      expect(find.byTooltip('Hinzufügen'), findsNothing);

      await pumpCalendar(tester, events: const []);
      await sweep();
      // No event there: the choice offers a new one with this time.
      expect(find.text('Neues Event mit dieser Zeit'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await settle(tester);
    });

    testWidgets('a double click asks for an hour', (tester) async {
      await pumpCalendar(
        tester,
        events: [
          event(
            'all',
            start: DateTime(2026, 10, 19),
            end: DateTime(2026, 10, 26),
          ),
        ],
      );
      final canvas = tester.getRect(find.byType(TimeGrid).first);
      final at = Offset(canvas.left + kTimeGridGutter + 400, canvas.top + 300);
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await tester.pump(kDoubleTapTimeout);
      await settle(tester);
      final form = editor(tester);
      expect(form.state.toMinutes - form.state.fromMinutes, 60);
    });

    testWidgets('several events: the choice names each; one picked opens it', (
      tester,
    ) async {
      await pumpCalendar(tester, events: [fair, dinner]);
      grid(tester).onCreate!((
        start: DateTime(2026, 10, 24, 18),
        end: DateTime(2026, 10, 24, 19),
      ));
      await settle(tester);
      expect(find.text('Messe'), findsOneWidget);
      expect(find.text('Vereinsabend'), findsOneWidget);
      await tester.tap(find.text('Vereinsabend'));
      await settle(tester);
      expect(editor(tester).event, dinner);
      expect(editor(tester).state.fromMinutes, 18 * 60);
    });

    testWidgets('no event: a new one with this time, then its first shift', (
      tester,
    ) async {
      await pumpCalendar(tester, events: const [], projectId: 'p1');
      grid(tester).onCreate!((
        start: DateTime(2026, 10, 24, 9),
        end: DateTime(2026, 10, 24, 11),
      ));
      await settle(tester);
      await tester.tap(find.text('Neues Event mit dieser Zeit'));
      await settle(tester);
      final form = BlocProvider.of<ShiftEventEditorCubit>(
        tester.element(find.byType(ShiftEventEditorBody)),
        listen: false,
      );
      expect(form.state.start, DateTime(2026, 10, 24, 9));
      expect(form.state.end, DateTime(2026, 10, 24, 11));
      expect(form.state.projectId, 'p1');

      final created = event(
        'fresh',
        title: 'Tag der offenen Tür',
        start: DateTime(2026, 10, 24, 9),
        end: DateTime(2026, 10, 24, 11),
      );
      repo.createdEvent = ShiftEventDetail(summary: created);
      form.setTitle('Tag der offenen Tür');
      await tester.tap(find.text('Anlegen'));
      await settle(tester);
      await settle(tester);
      expect(find.byType(ShiftEditorBody), findsOneWidget);
      expect(editor(tester).event, created);
      expect(editor(tester).state.fromMinutes, 9 * 60);
      expect(editor(tester).state.toMinutes, 11 * 60);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('an occurrence of a series asks which ones on save', (
      tester,
    ) async {
      final weekly = event(
        'e9',
        seriesId: 'r1',
        start: DateTime(2026, 10, 24, 8),
        end: DateTime(2026, 10, 24, 20),
      );
      await pumpCalendar(tester, events: [weekly]);
      grid(tester).onCreate!((
        start: DateTime(2026, 10, 24, 10),
        end: DateTime(2026, 10, 24, 11),
      ));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, 'Kasse');
      await tester.tap(find.text('Speichern'));
      await settle(tester);
      expect(find.text('Nur dieses'), findsOneWidget);
      expect(find.text('Alle künftigen'), findsOneWidget);
    });

    testWidgets('the "+" opens its menu at the pill on a wide window and as a '
        'sheet on a phone; a shift from it goes at the next full hour', (
      tester,
    ) async {
      await pumpCalendar(
        tester,
        events: [
          event(
            'day',
            start: DateTime(2026, 10, 24, 6),
            end: DateTime(2026, 10, 24, 22),
          ),
        ],
      );
      await tester.tap(find.byTooltip('Hinzufügen'));
      await settle(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Neues Event'), findsOneWidget);
      await tester.tap(find.text('Schicht anlegen'));
      await settle(tester);
      // The day in focus, at ten: the next full hour after 9:20.
      expect(editor(tester).state.day, DateTime(2026, 10, 24));
      expect(editor(tester).state.fromMinutes, 10 * 60);
      expect(editor(tester).state.toMinutes, 11 * 60);
      Navigator.of(tester.element(find.byType(ShiftEditorBody))).pop();
      await settle(tester);

      // Narrower than a popover has room for: a sheet.
      await pumpCalendar(tester, width: 700);
      await tester.tap(find.byTooltip('Hinzufügen'));
      await settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Schicht anlegen'), findsOneWidget);

      Navigator.of(tester.element(find.text('Schicht anlegen'))).pop();
      await settle(tester);

      // On a phone the "+" sits in the row with the date, and its menu is a
      // sheet too.
      await pumpCalendar(tester, width: 390);
      await tester.tap(find.byTooltip('Hinzufügen'));
      await settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Neues Event'), findsOneWidget);
    });

    testWidgets('the month offers its "+" to planners on a wide window', (
      tester,
    ) async {
      await pumpCalendar(tester, span: ShiftCalendarSpan.month);
      var month = tester.widget<TimeMonthScroller>(
        find.byType(TimeMonthScroller),
      );
      expect(month.onAddOnDay, isNotNull);
      expect(month.onDayMenu, isNotNull);
      expect(
        month.addLabel!(DateTime(2026, 10, 24)),
        'Schicht am Samstag, 24. Oktober 2026 anlegen',
      );

      await pumpCalendar(tester, span: ShiftCalendarSpan.month, width: 390);
      month = tester.widget<TimeMonthScroller>(find.byType(TimeMonthScroller));
      expect(month.onAddOnDay, isNull);

      await pumpCalendar(tester, span: ShiftCalendarSpan.month, planner: false);
      month = tester.widget<TimeMonthScroller>(find.byType(TimeMonthScroller));
      expect(month.onAddOnDay, isNull);
      expect(month.onDayMenu, isNull);
    });

    testWidgets('a planner\'s calendar fits 320 to 1440 at 200 %', (
      tester,
    ) async {
      for (final width in [320.0, 390.0, 1440.0]) {
        for (final scale in [1.0, 2.0]) {
          await pumpCalendar(tester, width: width, scale: scale);
          expect(tester.takeException(), isNull, reason: '$width x$scale');
          expect(find.byTooltip('Hinzufügen'), findsOneWidget);
        }
      }
    });
  });
}
