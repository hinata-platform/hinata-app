import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/shift_models.dart';
import 'package:hinata/features/shifts/bloc/my_shifts_snapshot_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_actions_cubit.dart';
import 'package:hinata/features/shifts/view/my_shifts_view.dart';
import 'package:hinata/features/shifts/view/shift_event_screen.dart';
import 'package:hinata/features/shifts/view/shift_events_view.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../../support/timer_surface_fakes.dart' show MemoryStorage;
import 'shift_fakes.dart';

/// The helper's three surfaces (HIN-44) with a fake repository: loading,
/// empty, filled, failing, and offline from the snapshot.
void main() {
  late FakeShiftRepository repo;
  late MyShiftsSnapshotCubit snapshot;
  late ShiftActionsCubit actions;

  setUp(() {
    HydratedBloc.storage = MemoryStorage();
    repo = FakeShiftRepository();
    snapshot = MyShiftsSnapshotCubit(storageId: 'shifts#test');
    actions = ShiftActionsCubit(repo);
  });

  tearDown(() async {
    await snapshot.close();
    await actions.close();
  });

  List<BlocProvider> blocs() => [
    BlocProvider<MyShiftsSnapshotCubit>.value(value: snapshot),
    BlocProvider<ShiftActionsCubit>.value(value: actions),
  ];

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('Meine Schichten', () {
    testWidgets('loading, then the empty state with a way to the events', (
      tester,
    ) async {
      repo.gate = Completer<void>();
      await pumpShiftsUi(
        tester,
        MyShiftsPage(now: () => DateTime(2026, 10, 20, 15)),
        repository: repo,
        blocs: blocs(),
      );
      expect(find.text('Noch keine Schichten'), findsNothing);
      repo.gate!.complete();
      await settle(tester);
      expect(find.text('Noch keine Schichten'), findsOneWidget);
      expect(find.text('Alle Events ansehen'), findsWidgets);
      expect(find.text('Gerade sucht kein Projekt Leute.'), findsOneWidget);
    });

    for (final (width, scale) in const [
      (390.0, 1.0),
      (390.0, 2.0),
      (1280.0, 1.0),
    ]) {
      testWidgets('hero, rows by day and open shifts at $width px x$scale', (
        tester,
      ) async {
        final next = sampleMine(
          assignmentId: 'a0',
          status: ShiftAssignmentStatus.assigned,
          shift: sampleShift(
            id: 's0',
            mine: true,
            start: DateTime(2026, 10, 21, 10),
            assigned: 2,
          ),
        );
        final later = sampleMine(
          assignmentId: 'a1',
          shift: sampleShift(
            id: 's1',
            title: 'Standführung',
            mine: true,
            start: DateTime(2026, 10, 22, 14),
            assigned: 1,
            required: 1,
          ),
        );
        repo
          ..next = next
          ..mine = (items: [next, later], total: 2)
          ..shiftDetail = ShiftDetail(shift: next.shift, event: sampleEvent)
          ..open = ShiftCalendar(
            shifts: [sampleShift(id: 'o1', title: 'Aufbau')],
            events: const {'e1': sampleEvent},
          );
        await pumpShiftsUi(
          tester,
          MyShiftsPage(now: () => DateTime(2026, 10, 20, 16)),
          repository: repo,
          blocs: blocs(),
          width: width,
          scale: scale,
        );
        await settle(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('NÄCHSTE SCHICHT'), findsOneWidget);
        // The hero's shift is not listed a second time.
        expect(find.text('Standführung'), findsOneWidget);
        expect(find.text('Aufbau'), findsOneWidget);
        expect(find.text('Eintragen'), findsOneWidget);
        expect(find.text('Bestätigen'), findsOneWidget);
        // The fresh answers went into the snapshot.
        expect(snapshot.state.rows.map((r) => r.assignmentId), ['a0', 'a1']);
        expect(snapshot.state.next!.assignmentId, 'a0');
      });
    }

    testWidgets('offline: the snapshot, people counted, no actions', (
      tester,
    ) async {
      snapshot
        ..recordRows([
          sampleMine(
            assignmentId: 'a1',
            shift: sampleShift(id: 's1', title: 'Theke', mine: true),
          ),
        ])
        ..recordNext(
          sampleMine(
            assignmentId: 'a0',
            shift: sampleShift(id: 's0', mine: true, assigned: 2),
          ),
        );
      repo.failure = ApiFailure('errors.connection');
      await pumpShiftsUi(
        tester,
        MyShiftsPage(now: () => DateTime(2026, 10, 20, 16)),
        repository: repo,
        blocs: blocs(),
      );
      await settle(tester);

      expect(
        find.text('Keine Verbindung. Du siehst den Stand vom letzten Laden.'),
        findsOneWidget,
      );
      expect(find.text('Theke'), findsOneWidget);
      expect(find.text('mit 1 weiteren Person'), findsOneWidget);
      expect(find.text('Abgeben'), findsNothing);
    });

    testWidgets('failing without a snapshot offers a retry', (tester) async {
      repo.failure = ApiFailure('Server weg');
      await pumpShiftsUi(
        tester,
        const MyShiftsPage(),
        repository: repo,
        blocs: blocs(),
      );
      await settle(tester);
      expect(find.text('Server weg'), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsOneWidget);
    });

    testWidgets('confirming from the row asks the server and says so', (
      tester,
    ) async {
      final pending = sampleMine(
        assignmentId: 'a1',
        status: ShiftAssignmentStatus.assigned,
        shift: sampleShift(id: 's1', title: 'Theke', mine: true),
      );
      repo
        ..mine = (items: [pending], total: 1)
        ..confirmed = sampleMine(assignmentId: 'a1');
      await pumpShiftsUi(
        tester,
        MyShiftsPage(now: () => DateTime(2026, 10, 20, 16)),
        repository: repo,
        blocs: blocs(),
      );
      await settle(tester);

      await tester.tap(find.text('Bestätigen'));
      await settle(tester);

      expect(repo.calls, contains('confirm:a1'));
      expect(find.text('Schicht bestätigt'), findsOneWidget);
      expect(find.text('Bestätigt'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('Events', () {
    testWidgets('cards with places, staffing and own count', (tester) async {
      repo.eventPage = (
        items: [
          sampleSummary(),
          sampleSummary(
            id: 'e2',
            taken: 2,
            required: 2,
            understaffed: 0,
            mine: 0,
          ),
          sampleSummary(id: 'e3', cancelled: true, mine: 0),
        ],
        total: 3,
      );
      await pumpShiftsUi(
        tester,
        const ShiftEventsPage(),
        repository: repo,
        blocs: blocs(),
        scale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('10 / 14 Plätze'), findsOneWidget);
      expect(find.text('2 Schichten brauchen noch Leute'), findsOneWidget);
      expect(find.text('Alles besetzt'), findsOneWidget);
      expect(find.text('1 eigene'), findsOneWidget);
      expect(find.text('Abgesagt'), findsOneWidget);
      expect(repo.calls, contains('events:all:0'));
    });

    testWidgets('none yet', (tester) async {
      await pumpShiftsUi(
        tester,
        const ShiftEventsPage(),
        repository: repo,
        blocs: blocs(),
      );
      await settle(tester);
      expect(find.text('Noch keine Events'), findsOneWidget);
    });
  });

  group('Event', () {
    ShiftEventDetail detail() => ShiftEventDetail(
      summary: sampleSummary(taken: 3, required: 7, understaffed: 1),
      shifts: [
        sampleShift(id: 'a', title: 'Aufbau', assigned: 1, required: 2),
        sampleShift(
          id: 'b',
          title: 'Einlass',
          assigned: 5,
          required: 5,
          max: 5,
          start: DateTime(2026, 10, 24, 19),
        ),
      ],
      users: const {'u1': ShiftUser(name: 'Lena Vogt')},
    );

    for (final width in const [390.0, 1280.0]) {
      testWidgets('one action per shift, full in words, filter at $width px', (
        tester,
      ) async {
        repo.eventDetail = detail();
        await pumpShiftsUi(
          tester,
          const ShiftEventScreen(eventId: 'e1'),
          repository: repo,
          blocs: blocs(),
          width: width,
        );
        await settle(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('3 von 7 Plätzen besetzt'), findsOneWidget);
        expect(find.text('Selbsteintrag offen'), findsOneWidget);
        expect(find.text('Eintragen'), findsOneWidget);
        expect(find.text('Voll, 5 von 5'), findsOneWidget);

        await tester.tap(find.text('Nur unterbesetzt'));
        await settle(tester);
        expect(find.text('Einlass'), findsNothing);
        expect(find.text('Aufbau'), findsOneWidget);
      });
    }

    testWidgets('signing up replaces the row with the answer', (tester) async {
      repo
        ..eventDetail = detail()
        ..assignResult = ShiftAssignResult(
          shift: sampleShift(
            id: 'a',
            title: 'Aufbau',
            assigned: 2,
            required: 2,
            mine: true,
            myStatus: ShiftAssignmentStatus.confirmed,
            myAssignmentId: 'a7',
          ),
          warnings: const ['absent'],
        );
      await pumpShiftsUi(
        tester,
        const ShiftEventScreen(eventId: 'e1'),
        repository: repo,
        blocs: blocs(),
      );
      await settle(tester);

      await tester.tap(find.text('Eintragen'));
      await settle(tester);

      expect(repo.calls, contains('selfAssign:a'));
      expect(
        find.textContaining('Du bist an dem Tag als abwesend eingetragen'),
        findsOneWidget,
      );
      expect(find.text('Eintragen'), findsNothing);
      // The place is named (`myAssignment`), so giving it up is right there.
      expect(find.text('Abgeben'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a refusal reads in the app\'s words', (tester) async {
      repo.eventDetail = detail();
      await pumpShiftsUi(
        tester,
        const ShiftEventScreen(eventId: 'e1'),
        repository: repo,
        blocs: blocs(),
      );
      await settle(tester);
      repo.failure = refusal('error.shifts.overlappingAssignment', status: 400);

      await tester.tap(find.text('Eintragen'));
      await settle(tester);

      expect(
        find.text('Du hast zur selben Zeit schon eine Schicht.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
