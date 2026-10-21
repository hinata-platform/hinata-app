import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/glass_filter_bar.dart' show GlassFilterPill;
import 'package:hinata/core/widgets/time_grid/time_week_strip.dart';
import 'package:hinata/features/shell/page_chrome.dart';
import 'package:hinata/core/models/shift_models.dart';
import 'package:hinata/core/widgets/time_grid/time_day_dots.dart';
import 'package:hinata/core/widgets/time_grid/time_grid.dart';
import 'package:hinata/features/account/shift_feed_cubit.dart';
import 'package:hinata/features/account/shift_feed_section.dart';
import 'package:hinata/features/shifts/bloc/shift_actions_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_calendar_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_editor_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_event_editor_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_planning_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_sheet_cubit.dart';
import 'package:hinata/features/shifts/view/shift_calendar_view.dart';
import 'package:hinata/features/shifts/view/shift_event_screen.dart';
import 'package:hinata/features/shifts/widgets/shift_editor.dart';
import 'package:hinata/features/shifts/widgets/shift_event_editor.dart';
import 'package:hinata/features/shifts/widgets/shift_sheet.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'shift_fakes.dart';

/// The planner's surfaces (HIN-160) and the feed section (HIN-47), drawn.
void main() {
  late FakeShiftRepository repo;
  late ShiftActionsCubit actions;
  late ShiftPlanningCubit planning;

  setUp(() {
    repo = FakeShiftRepository();
    actions = ShiftActionsCubit(repo);
    planning = ShiftPlanningCubit(repo);
    addTearDown(actions.close);
    addTearDown(planning.close);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  final mine = sampleShift(
    id: 'mine',
    title: 'Kasse',
    assigned: 1,
    required: 2,
    mine: true,
    myStatus: ShiftAssignmentStatus.confirmed,
    myAssignmentId: 'a1',
    start: DateTime(2026, 10, 24, 10),
  );
  final open = sampleShift(
    id: 'open',
    title: 'Aufbau',
    assigned: 0,
    required: 2,
    start: DateTime(2026, 10, 22, 10),
  );
  final fine = sampleShift(
    id: 'fine',
    title: 'Empfang',
    assigned: 2,
    required: 2,
    start: DateTime(2026, 10, 21, 13),
  );

  ShiftCalendar month({Set<String> plannable = const {}}) => ShiftCalendar(
    shifts: [mine, open, fine],
    events: const {'e1': sampleEvent},
    plannableProjectIds: plannable,
  );

  group('Calendar', () {
    Future<ShiftCalendarCubit> pumpCalendar(
      WidgetTester tester, {
      double width = 1280,
      double scale = 1,
      Set<String> plannable = const {},
      ShiftCalendarSpan span = ShiftCalendarSpan.week,
    }) async {
      repo
        ..calendarMonths[202610] = month(plannable: plannable)
        ..marksMonths[202610] = [
          ShiftDayMarks(date: DateTime(2026, 10, 22), mine: 1),
          ShiftDayMarks(date: DateTime(2026, 10, 24), open: 1, understaffed: 2),
        ];
      final cubit = ShiftCalendarCubit(
        repo,
        focused: DateTime(2026, 10, 24),
        span: span,
      );
      addTearDown(cubit.close);
      await cubit.start();
      await pumpShiftsUi(
        tester,
        BlocProvider.value(
          value: cubit,
          child: ShiftCalendarView(
            now: DateTime(2026, 10, 20, 9),
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

    testWidgets('own, open and other shifts read apart by glyph and words', (
      tester,
    ) async {
      await pumpCalendar(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Kasse · fehlt 1'), findsOneWidget);
      expect(find.text('Aufbau · fehlen 2'), findsOneWidget);
      expect(find.text('Empfang'), findsOneWidget);
      // Own: a check, and the warning too, since it is short as well. Open:
      // the warning alone.
      expect(find.byIcon(LucideIcons.check), findsOneWidget);
      expect(find.byIcon(LucideIcons.triangleAlert), findsWidgets);
      expect(find.text('19. Okt. bis 25. Okt.'), findsNothing);
    });

    testWidgets('a helper sees the hours read-only, a planner can move', (
      tester,
    ) async {
      await pumpCalendar(tester);
      expect(tester.widget<TimeGrid>(find.byType(TimeGrid)).onMoved, isNull);
      expect(tester.widget<TimeGrid>(find.byType(TimeGrid)).onCreate, isNull);

      await pumpCalendar(tester, plannable: {'p1'});
      expect(tester.widget<TimeGrid>(find.byType(TimeGrid)).onMoved, isNotNull);
      // Since HIN-166 a planner also plans by sweeping the canvas.
      expect(
        tester.widget<TimeGrid>(find.byType(TimeGrid)).onCreate,
        isNotNull,
      );
    });

    testWidgets('the filter keeps only the short ones, without asking again', (
      tester,
    ) async {
      final cubit = await pumpCalendar(tester);
      final before = repo.calls.length;
      // Named or a glyph, whichever the width affords.
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is GlassFilterPill && w.label == 'Nur unterbesetzt',
        ),
      );
      await settle(tester);
      expect(find.text('Empfang'), findsNothing);
      expect(find.text('Aufbau · fehlen 2'), findsOneWidget);
      expect(repo.calls.length, before);
      expect(cubit.state.understaffedOnly, isTrue);
    });

    testWidgets('a phone shows one day under the strip with its marks', (
      tester,
    ) async {
      for (final scale in [1.0, 2.0]) {
        await pumpCalendar(tester, width: 320, scale: scale);
        expect(tester.takeException(), isNull, reason: 'x$scale');
        expect(find.text('Kasse · fehlt 1'), findsOneWidget);
        // The bar (drawn by the shell) carries the month as title and the
        // week strip with its marks; the page keeps only the hours and the
        // day written out above them.
        final chrome = tester.widget<PageChrome>(find.byType(PageChrome).first);
        expect(chrome.title, 'Oktober');
        expect(chrome.titleLeading, isTrue);
        expect(chrome.onTitleTap, isNotNull);
        final strip = (chrome.bottom! as Padding).child! as TimeWeekStrip;
        expect(strip.dotsOn, isNotNull);
        expect(find.byType(TimeWeekStrip), findsNothing);
        expect(find.text('Samstag, 24. Oktober 2026'), findsOneWidget);
      }
    });

    testWidgets('wide: the span switcher and the filter sit on one line', (
      tester,
    ) async {
      // Wide enough that the test font, a square per letter, still names all.
      final cubit = await pumpCalendar(tester, width: 1900);
      expect(find.text('Woche'), findsOneWidget);
      expect(find.text('Monat'), findsOneWidget);
      // One line: the arrows, the switcher and the filter share a row.
      final arrow = tester.getCenter(find.byTooltip('Vorige Woche'));
      final month = tester.getCenter(find.text('Monat'));
      final filter = tester.getCenter(find.text('Nur unterbesetzt'));
      expect((arrow.dy - month.dy).abs(), lessThan(4));
      expect((arrow.dy - filter.dy).abs(), lessThan(4));
      // The filters against the trailing edge, not after the window's name.
      expect(month.dx, greaterThan(1900 * 0.75));
      await tester.tap(find.text('Monat'));
      await settle(tester);
      expect(cubit.state.span, ShiftCalendarSpan.month);
      await tester.tap(find.text('Nur unterbesetzt'));
      await settle(tester);
      expect(cubit.state.understaffedOnly, isTrue);
    });

    testWidgets('narrower, the filters fall back to glyphs before anything '
        'scrolls or clips', (tester) async {
      final cubit = await pumpCalendar(tester, width: 820);
      expect(tester.takeException(), isNull);
      // Named as tooltips and to a screen reader, no longer written out.
      expect(find.text('Nur unterbesetzt'), findsNothing);
      expect(find.byTooltip('Nur unterbesetzt'), findsOneWidget);
      expect(find.byTooltip('Alle Projekte'), findsOneWidget);
      // A screen reader meets one button with the name, the state and the tap.
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Nur unterbesetzt')),
        matchesSemantics(
          label: 'Nur unterbesetzt',
          isButton: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
      await tester.tap(find.byTooltip('Nur unterbesetzt'));
      await settle(tester);
      expect(cubit.state.understaffedOnly, isTrue);
      // Glyphs rather than a scrolling row: the fallback that scrolls is for
      // a text scale no naming fits.
      expect(
        find.byWidgetPredicate((w) => w is SingleChildScrollView && w.reverse),
        findsNothing,
      );
      // 640 and 700 are the narrowest wide windows (compact ends at ~610).
      for (final width in [640.0, 700.0, 1000.0]) {
        await pumpCalendar(tester, width: width);
        expect(tester.takeException(), isNull, reason: 'at $width');
      }
    });

    testWidgets('wide: the month title follows the scroll and "next" steps '
        'from there', (tester) async {
      final cubit = await pumpCalendar(
        tester,
        width: 1280,
        span: ShiftCalendarSpan.month,
      );
      expect(find.text('Oktober 2026'), findsOneWidget);
      // Today is on screen, so there is no way back to it.
      expect(find.text('Heute'), findsNothing);
      await tester.drag(find.text('24').first, const Offset(0, -900));
      await settle(tester);
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('Oktober 2026'), findsNothing);
      expect(find.text('Heute'), findsOneWidget);
      await tester.tap(find.byTooltip('Nächster Monat'));
      await settle(tester);
      expect(find.text('Dezember 2026'), findsOneWidget);
      expect(cubit.state.focused.month, 12);
      await tester.tap(find.text('Heute'));
      await settle(tester);
      expect(find.text('Oktober 2026'), findsOneWidget);
    });

    testWidgets('the month marks days and opens one on tap', (tester) async {
      final cubit = await pumpCalendar(
        tester,
        width: 390,
        span: ShiftCalendarSpan.month,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Kasse · fehlt 1'), findsNothing);
      expect(find.byType(TimeDayDotsRow), findsNWidgets(2));
      // The month read counts, never shifts.
      expect(repo.calls.where((c) => c.startsWith('calendar:')), isEmpty);
      expect(repo.calls, contains('marks:202610:all'));
      await tester.tap(find.text('22').first);
      await settle(tester);
      expect(cubit.state.span, ShiftCalendarSpan.week);
      expect(cubit.state.focused, DateTime(2026, 10, 22));
    });
  });

  group('Shift editor', () {
    Future<ShiftEditorCubit> pumpEditor(
      WidgetTester tester, {
      double width = 390,
      double scale = 1,
      Shift? shift,
    }) async {
      final cubit = ShiftEditorCubit(
        repo,
        event: sampleSummary(),
        shift: shift,
        deviceZone: 'Europe/Berlin',
      );
      addTearDown(cubit.close);
      await pumpShiftsUi(
        tester,
        BlocProvider.value(
          value: cubit,
          child: const SingleChildScrollView(child: ShiftEditorBody()),
        ),
        repository: repo,
        width: width,
        height: 1400,
        scale: scale,
      );
      return cubit;
    }

    testWidgets('fits 320 at 200 % and starts with no upper limit', (
      tester,
    ) async {
      await pumpEditor(tester, width: 320, scale: 2);
      expect(tester.takeException(), isNull);
      expect(find.text('keine Obergrenze'), findsOneWidget);
      expect(find.text('nur dieser Tag'), findsOneWidget);
    });

    testWidgets('the minus of the limit stops at the need', (tester) async {
      final cubit = await pumpEditor(tester);
      await tester.tap(find.byTooltip('Obergrenze erhöhen'));
      await tester.pump();
      expect(cubit.state.maxHelpers, 1);
      final minus = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, LucideIcons.minus).last,
      );
      expect(minus.onPressed, isNull);
    });

    testWidgets('a refused batch names the day it failed on', (tester) async {
      final cubit = await pumpEditor(tester);
      cubit.setTitle('Kasse');
      cubit.toggleExtraDay(DateTime(2026, 10, 25));
      await tester.pump();
      await cubit.save();
      await tester.pump();
      expect(
        find.textContaining('Die Schicht liegt außerhalb des Events'),
        findsWidgets,
      );
      expect(find.textContaining('So., 25. Okt.'), findsWidgets);
    });

    testWidgets('a limit below the people on it says how many', (tester) async {
      final cubit = await pumpEditor(
        tester,
        shift: sampleShift(required: 2, max: 5, assigned: 4),
      );
      repo.failure = refusal('error.shifts.maxBelowAssigned')
        ..details['assigned'] = '4';
      cubit.stepMax(-1);
      await cubit.save();
      await tester.pump();
      expect(
        find.text(
          'Es sind schon 4 Personen eingetragen. Nimm erst jemanden heraus.',
        ),
        findsOneWidget,
      );
    });
  });

  group('Event editor', () {
    testWidgets('fixed project, folded details, 200 % at 320', (tester) async {
      final cubit = ShiftEventEditorCubit(
        repo,
        projectId: 'p1',
        projectName: 'Messe Nord',
        deviceZone: 'Europe/Berlin',
        day: DateTime(2026, 11, 7),
      );
      addTearDown(cubit.close);
      await pumpShiftsUi(
        tester,
        BlocProvider.value(
          value: cubit,
          child: const SingleChildScrollView(
            child: ShiftEventEditorBody(projectLocked: true),
          ),
        ),
        repository: repo,
        width: 320,
        height: 1400,
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Messe Nord'), findsOneWidget);
      expect(find.byIcon(LucideIcons.lock), findsOneWidget);
      expect(find.text('Zeitzone'), findsNothing);
      await tester.tap(find.text('Weitere Angaben'));
      await tester.pump();
      expect(find.text('Zeitzone'), findsOneWidget);
      expect(find.text('Selbst eintragen erlaubt'), findsOneWidget);
    });
  });

  group('Event page for planners', () {
    ShiftEventDetail detail({required bool canPlan}) => ShiftEventDetail(
      summary: ShiftEventSummary(
        id: 'e1',
        projectId: 'p1',
        title: 'Sommerfest',
        startsAt: DateTime(2026, 10, 24, 14),
        endsAt: DateTime(2026, 10, 25, 3),
        startsLocal: DateTime(2026, 10, 24, 14),
        endsLocal: DateTime(2026, 10, 25, 3),
        canPlan: canPlan,
        placesRequired: 4,
        placesTaken: 1,
        shiftsUnderstaffed: 2,
      ),
      shifts: [
        sampleShift(id: 'a', title: 'Aufbau', assigned: 0, required: 2),
        sampleShift(
          id: 'b',
          title: 'Kasse',
          assigned: 1,
          required: 2,
          mine: true,
          myStatus: ShiftAssignmentStatus.assigned,
          myAssignmentId: 'a5',
        ),
      ],
    );

    Future<void> pumpEvent(WidgetTester tester, {required bool canPlan}) async {
      repo.eventDetail = detail(canPlan: canPlan);
      await pumpShiftsUi(
        tester,
        const ShiftEventScreen(eventId: 'e1'),
        repository: repo,
        blocs: [
          BlocProvider<ShiftActionsCubit>.value(value: actions),
          BlocProvider<ShiftPlanningCubit>.value(value: planning),
        ],
      );
      await settle(tester);
    }

    testWidgets('a planner gets one "Zuteilen" per shift', (tester) async {
      await pumpEvent(tester, canPlan: true);
      expect(find.text('Zuteilen'), findsNWidgets(2));
      expect(find.text('Eintragen'), findsNothing);
    });

    testWidgets('a helper sees no planner buttons, and confirms in place', (
      tester,
    ) async {
      await pumpEvent(tester, canPlan: false);
      expect(find.text('Zuteilen'), findsNothing);
      expect(find.text('Eintragen'), findsOneWidget);
      // The server named the caller's place (`myAssignment`).
      expect(find.text('Bestätigen'), findsOneWidget);
    });
  });

  group('Sheet', () {
    testWidgets('a planner takes people off; the caller withdraws in place', (
      tester,
    ) async {
      repo.shiftDetail = ShiftDetail.fromJson({
        'shift': const {
          'id': 's1',
          'eventId': 'e1',
          'projectId': 'p1',
          'title': 'Kasse',
          'startsAt': '2026-10-24T12:00:00Z',
          'endsAt': '2026-10-24T15:00:00Z',
          'startsLocal': '2026-10-24T14:00:00',
          'endsLocal': '2026-10-24T17:00:00',
          'requiredHelpers': 2,
          'assignedCount': 2,
          'mine': true,
          'myAssignment': {'id': 'a1', 'status': 'CONFIRMED'},
          'assigneeIds': ['me', 'u2'],
        },
        'event': sampleEvent.toJson(),
        'users': const {
          'me': {'name': 'Mia Krüger'},
          'u2': {'name': 'Jonas Weber'},
        },
        'canPlan': true,
        'assignments': const [
          {'id': 'a1', 'userId': 'me', 'status': 'CONFIRMED'},
          {'id': 'a2', 'userId': 'u2', 'status': 'ASSIGNED'},
        ],
      });
      final sheet = ShiftSheetCubit(repo, 's1');
      addTearDown(sheet.close);
      await pumpShiftsUi(
        tester,
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: sheet..load()),
            BlocProvider<ShiftActionsCubit>.value(value: actions),
            BlocProvider<ShiftPlanningCubit>.value(value: planning),
          ],
          child: const SingleChildScrollView(child: ShiftSheetBody()),
        ),
        repository: repo,
      );
      await settle(tester);
      expect(find.text('Austragen'), findsOneWidget);
      expect(find.byTooltip('Jonas Weber herausnehmen'), findsOneWidget);
      expect(find.text('Bearbeiten'), findsOneWidget);
      expect(find.text('Löschen'), findsOneWidget);
    });
  });

  group('Feed section', () {
    Future<ShiftFeedCubit> pumpFeed(
      WidgetTester tester, {
      double scale = 1,
    }) async {
      final cubit = ShiftFeedCubit(repo);
      addTearDown(cubit.close);
      await cubit.load();
      await pumpShiftsUi(
        tester,
        BlocProvider.value(
          value: cubit,
          child: const SingleChildScrollView(child: ShiftFeedView()),
        ),
        repository: repo,
        width: 320,
        scale: scale,
      );
      return cubit;
    }

    testWidgets('makes an address and shows it once', (tester) async {
      final cubit = await pumpFeed(tester, scale: 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Abo-Adresse erzeugen'));
      await settle(tester);
      expect(find.text(repo.feedAddress.url), findsOneWidget);
      expect(find.textContaining('nur jetzt angezeigt'), findsOneWidget);
      expect(find.text('In Kalender öffnen'), findsOneWidget);
      await tester.ensureVisible(find.text('Fertig'));
      await tester.tap(find.text('Fertig'));
      await settle(tester);
      expect(find.text(repo.feedAddress.url), findsNothing);
      expect(find.text('Neu erzeugen'), findsOneWidget);
      expect(cubit.state.address, isNull);
    });

    testWidgets('an active feed says since when and when last fetched', (
      tester,
    ) async {
      repo.feedStatus = ShiftFeedStatus(
        exists: true,
        createdAt: DateTime(2026, 10, 20),
        lastUsedAt: DateTime.now().subtract(const Duration(minutes: 12)),
      );
      await pumpFeed(tester);
      expect(find.textContaining('vor 12 Minuten'), findsOneWidget);
      expect(find.text('Entfernen'), findsOneWidget);
    });
  });
}
