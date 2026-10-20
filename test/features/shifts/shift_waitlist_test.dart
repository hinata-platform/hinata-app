import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/shift_models.dart';
import 'package:hinata/features/shifts/bloc/my_shifts_snapshot_cubit.dart';
import 'package:hinata/features/shifts/bloc/next_shift_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_actions_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_assignees.dart';
import 'package:hinata/features/shifts/bloc/shift_changes.dart';
import 'package:hinata/features/shifts/bloc/shift_planning_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_sheet_cubit.dart';
import 'package:hinata/features/shifts/view/my_shifts_view.dart';
import 'package:hinata/features/shifts/view/shift_event_screen.dart';
import 'package:hinata/features/shifts/widgets/shift_actions.dart';
import 'package:hinata/features/shifts/widgets/shift_sheet.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../../support/timer_surface_fakes.dart' show MemoryStorage;
import 'shift_fakes.dart';

/// The waiting list (HIN-162) and the planner's candidates, from the wire
/// to the screens.
void main() {
  group('models', () {
    test('a shift reads the waiting list leniently', () {
      final shift = Shift.fromJson(const {
        'id': 's1',
        'assignedCount': 5,
        'maxHelpers': 5,
        'waitingCount': 3,
        'myWaitPosition': 2,
        'myWaitAssignmentId': 'a-77',
        'waitingIds': ['u1', 7, 'u2'],
      });
      expect(shift.waitingCount, 3);
      expect(shift.waiting, isTrue);
      expect(shift.myWaitAssignmentId, 'a-77');
      expect(shift.waitingIds, ['u1', 'u2']);
      // An older server says nothing: nobody waits.
      final old = Shift.fromJson(const {'id': 's2'});
      expect(old.waitingCount, 0);
      expect(old.waiting, isFalse);
      expect(old.waitingIds, isEmpty);
    });

    test('a promoted place carries its deadline as a wall clock', () {
      final mine = MyShift.fromJson(const {
        'assignmentId': 'a1',
        'status': 'ASSIGNED',
        'shift': {'id': 's1'},
        'event': {'id': 'e1'},
        'confirmBy': '2026-10-21T16:00:00Z',
        'confirmByLocal': '2026-10-21T18:00:00',
      });
      expect(mine.promoted, isTrue);
      expect(mine.confirmByLocal, DateTime(2026, 10, 21, 18));
      expect(mine.ref.promoted, isTrue);
      expect(
        mine.copyWith(clearConfirmBy: true).promoted,
        isFalse,
        reason: 'a confirmation ends the deadline',
      );
      final planned = MyShift.fromJson(const {
        'assignmentId': 'a2',
        'status': 'ASSIGNED',
        'shift': {'id': 's1'},
        'event': {'id': 'e1'},
      });
      expect(planned.promoted, isFalse);
    });

    test('joining a full shift answers with a waiting place', () {
      final result = ShiftAssignResult.fromJson(const {
        'shift': {
          'id': 's1',
          'assignedCount': 5,
          'maxHelpers': 5,
          'waitingCount': 1,
          'myWaitPosition': 1,
        },
        'assignment': {'id': 'a9', 'status': 'WAITING'},
      });
      expect(result.waitlisted, isTrue);
      expect(result.shift.mine, isFalse);
      expect(result.shift.myAssignmentId, isNull);
      expect(result.shift.myWaitAssignmentId, 'a9');
      expect(result.shift.myWaitPosition, 1);
    });

    test('candidates keep only rows with an id', () {
      final c = ShiftCandidates.fromJson(const {
        'candidates': [
          {'userId': 'u1', 'name': 'Ann', 'avatarUrl': null},
          {'name': 'nobody'},
          {'userId': 'u2', 'name': 'Dana', 'avatarUrl': 'https://x/y.png'},
        ],
        'truncated': true,
      });
      expect(c.candidates.map((x) => x.userId), ['u1', 'u2']);
      expect(c.candidates.last.avatarUrl, 'https://x/y.png');
      expect(c.truncated, isTrue);
      expect(ShiftCandidates.fromJson(null).candidates, isEmpty);
    });
  });

  group('the offer table', () {
    test('waiting: leave the list, nothing primary', () {
      final offer = shiftOfferFor(
        sampleShift(
          assigned: 5,
          required: 5,
          max: 5,
          waitingCount: 3,
          myWaitPosition: 2,
          myWaitAssignmentId: 'a7',
        ),
      );
      expect(offer.primary, isNull);
      expect(offer.secondary, ShiftAction.waitlistLeave);
    });

    test('promoted: confirm first, give up second', () {
      final shift = sampleShift(
        mine: true,
        myStatus: ShiftAssignmentStatus.assigned,
      );
      final promoted = shiftOfferFor(shift, promoted: true);
      expect(promoted.primary, ShiftAction.confirm);
      expect(promoted.secondary, ShiftAction.release);
      final planned = shiftOfferFor(shift);
      expect(planned.secondary, ShiftAction.decline);
    });

    test('a free place with people waiting does not jump the queue', () {
      final offer = shiftOfferFor(
        sampleShift(assigned: 4, required: 5, max: 5, waitingCount: 2),
      );
      expect(offer.primary, isNull);
      expect(offer.secondary, ShiftAction.waitlistJoin);
    });
  });

  group('cubits', () {
    late FakeShiftRepository repo;
    late ShiftChanges bus;

    setUp(() {
      repo = FakeShiftRepository();
      bus = ShiftChanges.instance;
    });

    test('joining a full shift says it is the waiting list', () async {
      final cubit = ShiftActionsCubit(repo, changes: bus);
      addTearDown(cubit.close);
      repo.assignResult = ShiftAssignResult(
        shift: sampleShift(myWaitPosition: 1, waitingCount: 1),
        assignment: const ShiftAssignmentRef(
          id: 'a9',
          status: ShiftAssignmentStatus.waiting,
        ),
      );
      final outcome = await cubit.join(sampleShift(assigned: 5, max: 5));
      expect(outcome.messageKey, 'shifts.done.waitlisted');
      expect(repo.calls, ['selfAssign:s1']);
    });

    test('leaving the list releases the waiting place', () async {
      final cubit = ShiftActionsCubit(repo, changes: bus);
      addTearDown(cubit.close);
      final outcome = await cubit.leaveWaitlist('s1', 'a7');
      expect(outcome.messageKey, 'shifts.done.waitlistLeft');
      expect(repo.calls, ['release:a7']);
    });

    test(
      'the head reads the waiting lists, and survives without them',
      () async {
        final waiting = sampleMine(
          assignmentId: 'w1',
          status: ShiftAssignmentStatus.waiting,
          shift: sampleShift(id: 'w', myWaitPosition: 1, waitingCount: 1),
        );
        repo.waiting = [waiting];
        final cubit = NextShiftCubit(repo, changes: const Stream.empty());
        addTearDown(cubit.close);
        await cubit.load();
        expect(cubit.state.waiting, [waiting]);
        expect(repo.calls, containsAll(['next', 'open:3', 'waiting']));
        cubit.dropWaiting('w1');
        expect(cubit.state.waiting, isEmpty);
      },
    );

    test('the open list never offers a shift the caller waits for', () async {
      repo.open = ShiftCalendar(
        shifts: [
          sampleShift(id: 'o1'),
          sampleShift(id: 'o2', myWaitPosition: 1),
        ],
      );
      final cubit = NextShiftCubit(repo, changes: const Stream.empty());
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.open.shifts.map((s) => s.id), ['o1']);
    });

    test(
      'the people come from the candidates, one request per query',
      () async {
        repo.candidateList = const ShiftCandidates(
          candidates: [ShiftCandidate(userId: 'u1', name: 'Ann')],
          truncated: true,
        );
        final assignees = ShiftAssignees(repo, 'p1');
        final first = await assignees.search('an', 0, 25);
        expect(first.items.single.id, 'u1');
        expect(first.items.single.displayName, 'Ann');
        expect(assignees.truncated, isTrue);
        expect(repo.lastQuery, 'an');
        final second = await assignees.search('an', 1, 25);
        expect(second.items, isEmpty);
        expect(repo.calls, ['candidates:p1:50']);
      },
    );

    test('the sheet keeps the deadline the opener knew', () async {
      repo.shiftDetail = ShiftDetail(
        shift: sampleShift(
          mine: true,
          myStatus: ShiftAssignmentStatus.assigned,
          myAssignmentId: 'a1',
        ),
        event: sampleEvent,
        myAssignment: const ShiftAssignmentRef(
          id: 'a1',
          status: ShiftAssignmentStatus.assigned,
        ),
      );
      final cubit = ShiftSheetCubit(
        repo,
        's1',
        assignment: ShiftAssignmentRef(
          id: 'a1',
          status: ShiftAssignmentStatus.assigned,
          confirmByLocal: DateTime(2026, 10, 21, 18),
        ),
      );
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.assignment?.promoted, isTrue);
    });
  });

  group('screens', () {
    late FakeShiftRepository repo;
    late ShiftActionsCubit actions;
    late ShiftPlanningCubit planning;
    late MyShiftsSnapshotCubit snapshot;

    setUp(() {
      HydratedBloc.storage = MemoryStorage();
      repo = FakeShiftRepository();
      actions = ShiftActionsCubit(repo);
      planning = ShiftPlanningCubit(repo);
      snapshot = MyShiftsSnapshotCubit(storageId: 'shifts#waitlist');
    });

    tearDown(() async {
      await actions.close();
      await planning.close();
      await snapshot.close();
    });

    List<BlocProvider> blocs() => [
      BlocProvider<MyShiftsSnapshotCubit>.value(value: snapshot),
      BlocProvider<ShiftActionsCubit>.value(value: actions),
      BlocProvider<ShiftPlanningCubit>.value(value: planning),
    ];

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    ShiftEventDetail event({
      required bool canPlan,
      required List<Shift> shifts,
      Map<String, ShiftUser> users = const {},
    }) => ShiftEventDetail(
      summary: ShiftEventSummary(
        id: 'e1',
        projectId: 'p1',
        title: 'Vereinsfest',
        startsAt: DateTime(2026, 10, 24, 14),
        endsAt: DateTime(2026, 10, 24, 22),
        startsLocal: DateTime(2026, 10, 24, 14),
        endsLocal: DateTime(2026, 10, 24, 22),
        canPlan: canPlan,
        placesRequired: 5,
        placesTaken: 5,
      ),
      shifts: shifts,
      users: users,
    );

    for (final (width, scale) in const [
      (320.0, 2.0),
      (390.0, 1.0),
      (1440.0, 1.0),
    ]) {
      testWidgets('a full shift offers the waiting list at $width px x$scale', (
        tester,
      ) async {
        repo
          ..eventDetail = event(
            canPlan: false,
            shifts: [
              sampleShift(
                title: 'Kasse',
                assigned: 5,
                required: 5,
                max: 5,
                waitingCount: 3,
              ),
            ],
          )
          ..assignResult = ShiftAssignResult(
            shift: sampleShift(
              assigned: 5,
              required: 5,
              max: 5,
              waitingCount: 4,
              myWaitPosition: 4,
              myWaitAssignmentId: 'a9',
            ),
            assignment: const ShiftAssignmentRef(
              id: 'a9',
              status: ShiftAssignmentStatus.waiting,
            ),
          );
        await pumpShiftsUi(
          tester,
          const ShiftEventScreen(eventId: 'e1'),
          repository: repo,
          blocs: blocs(),
          width: width,
          scale: scale,
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Voll, 5 von 5'), findsNothing);
        expect(find.text('3 warten'), findsOneWidget);
        // Exactly one thing to press on the row, and it is the quiet one.
        expect(find.text('Eintragen'), findsNothing);
        await tester.ensureVisible(find.text('Auf Warteliste setzen'));
        await tester.tap(find.text('Auf Warteliste setzen'));
        await settle(tester);
        expect(repo.calls, contains('selfAssign:s1'));
        expect(find.text('Du stehst auf der Warteliste'), findsOneWidget);
        expect(find.text('Warteliste, Platz 4 von 4'), findsOneWidget);
        expect(find.text('Warteliste verlassen'), findsOneWidget);
      });
    }

    testWidgets('waiting: the rank as a badge, leaving asks first', (
      tester,
    ) async {
      repo.eventDetail = event(
        canPlan: false,
        shifts: [
          sampleShift(
            assigned: 5,
            required: 5,
            max: 5,
            waitingCount: 3,
            myWaitPosition: 2,
            myWaitAssignmentId: 'a7',
          ),
        ],
      );
      await pumpShiftsUi(
        tester,
        const ShiftEventScreen(eventId: 'e1'),
        repository: repo,
        blocs: blocs(),
      );
      await settle(tester);
      expect(find.text('Warteliste, Platz 2 von 3'), findsOneWidget);
      await tester.ensureVisible(find.text('Warteliste verlassen'));
      await tester.tap(find.text('Warteliste verlassen'));
      await settle(tester);
      expect(find.text('Warteliste verlassen?'), findsOneWidget);
      expect(repo.calls, isNot(contains('release:a7')));
      await tester.tap(find.text('Warteliste verlassen').last);
      await settle(tester);
      expect(repo.calls, contains('release:a7'));
    });

    testWidgets('a planner sees who waits and gives a free place now', (
      tester,
    ) async {
      repo
        ..eventDetail = event(
          canPlan: true,
          shifts: [
            sampleShift(
              assigned: 4,
              required: 5,
              max: 5,
              waitingCount: 2,
              waitingIds: const ['u1', 'u2'],
            ),
          ],
          users: const {
            'u1': ShiftUser(name: 'Ann Berg'),
            'u2': ShiftUser(name: 'Dana Ruiz'),
          },
        )
        ..assigned = ShiftAssignResult(shift: sampleShift(assigned: 5, max: 5));
      await pumpShiftsUi(
        tester,
        const ShiftEventScreen(eventId: 'e1'),
        repository: repo,
        blocs: blocs(),
        width: 1280,
      );
      await settle(tester);
      expect(find.text('1. Ann Berg'), findsOneWidget);
      expect(find.text('2. Dana Ruiz'), findsOneWidget);
      await tester.tap(find.text('1. Ann Berg'));
      await settle(tester);
      expect(find.text('Jetzt zuteilen?'), findsOneWidget);
      await tester.tap(find.text('Jetzt zuteilen').last);
      await settle(tester);
      expect(repo.calls, contains('assign:s1:u1'));
    });

    testWidgets('on a full shift the waiting chips only say who waits', (
      tester,
    ) async {
      repo.eventDetail = event(
        canPlan: true,
        shifts: [
          sampleShift(
            assigned: 5,
            required: 5,
            max: 5,
            waitingCount: 1,
            waitingIds: const ['u1'],
          ),
        ],
        users: const {'u1': ShiftUser(name: 'Ann Berg')},
      );
      await pumpShiftsUi(
        tester,
        const ShiftEventScreen(eventId: 'e1'),
        repository: repo,
        blocs: blocs(),
      );
      await settle(tester);
      await tester.tap(find.text('1. Ann Berg'));
      await settle(tester);
      expect(find.text('Jetzt zuteilen?'), findsNothing);
    });

    testWidgets('the planner picks from the candidates and hears of the rest', (
      tester,
    ) async {
      repo
        ..eventDetail = event(
          canPlan: true,
          shifts: [sampleShift(assigned: 1, required: 2)],
        )
        ..candidateList = const ShiftCandidates(
          candidates: [ShiftCandidate(userId: 'u5', name: 'Kemal Aydın')],
          truncated: true,
        );
      await pumpShiftsUi(
        tester,
        const ShiftEventScreen(eventId: 'e1'),
        repository: repo,
        blocs: blocs(),
        width: 1280,
      );
      await settle(tester);
      await tester.tap(find.text('Zuteilen'));
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      expect(repo.calls, contains('candidates:p1:50'));
      expect(find.text('Kemal Aydın'), findsOneWidget);
      expect(
        find.text(
          'Es gibt noch mehr Personen. Such nach einem Namen, um sie zu finden.',
        ),
        findsOneWidget,
      );
    });

    for (final (width, scale) in const [(320.0, 2.0), (1440.0, 1.0)]) {
      testWidgets('Meine Schichten: the waiting group and a promoted place '
          'at $width px x$scale', (tester) async {
        final promoted = sampleMine(
          assignmentId: 'p1',
          status: ShiftAssignmentStatus.assigned,
          confirmByLocal: DateTime(2026, 10, 20, 18),
          shift: sampleShift(
            id: 'sp',
            title: 'Getränke',
            mine: true,
            myStatus: ShiftAssignmentStatus.assigned,
            myAssignmentId: 'p1',
            start: DateTime(2026, 10, 22, 10),
          ),
        );
        final waiting = sampleMine(
          assignmentId: 'w1',
          status: ShiftAssignmentStatus.waiting,
          shift: sampleShift(
            id: 'sw',
            title: 'Garderobe',
            assigned: 4,
            required: 4,
            max: 4,
            waitingCount: 2,
            myWaitPosition: 1,
            start: DateTime(2026, 10, 25, 10),
          ),
        );
        repo
          ..next = promoted
          ..mine = (items: [promoted], total: 1)
          ..waiting = [waiting]
          ..shiftDetail = ShiftDetail(
            shift: promoted.shift,
            event: sampleEvent,
          );
        await pumpShiftsUi(
          tester,
          MyShiftsPage(now: () => DateTime(2026, 10, 20, 12)),
          repository: repo,
          blocs: blocs(),
          width: width,
          scale: scale,
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        // The hero holds the promoted place, never the waiting one.
        expect(find.text('NÄCHSTE SCHICHT'), findsOneWidget);
        expect(
          find.text('Nachgerückt, bitte bis 18:00 bestätigen'),
          findsOneWidget,
        );
        expect(find.text('Bestätigen'), findsOneWidget);
        expect(find.text('Abgeben'), findsOneWidget);
        expect(find.text('Ablehnen'), findsNothing);
        expect(find.text('WARTELISTE'), findsOneWidget);
        expect(find.text('Garderobe'), findsOneWidget);
        expect(find.text('Warteliste, Platz 1 von 2'), findsOneWidget);
        expect(find.text('Warteliste verlassen'), findsOneWidget);
      });
    }

    testWidgets('the sheet of a promoted place: deadline, confirm, give up', (
      tester,
    ) async {
      repo.shiftDetail = ShiftDetail(
        shift: sampleShift(
          mine: true,
          myStatus: ShiftAssignmentStatus.assigned,
          myAssignmentId: 'a1',
        ),
        event: sampleEvent,
      );
      final sheet = ShiftSheetCubit(
        repo,
        's1',
        assignment: ShiftAssignmentRef(
          id: 'a1',
          status: ShiftAssignmentStatus.assigned,
          confirmByLocal: DateTime(2026, 10, 21, 18),
        ),
      );
      addTearDown(sheet.close);
      await pumpShiftsUi(
        tester,
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: sheet..load()),
            ...blocs(),
          ],
          child: const SingleChildScrollView(child: ShiftSheetBody()),
        ),
        repository: repo,
      );
      await settle(tester);
      expect(find.textContaining('Nachgerückt, bitte bis'), findsOneWidget);
      expect(find.text('Bestätigen'), findsOneWidget);
      expect(find.text('Abgeben'), findsOneWidget);
      expect(find.text('Ablehnen'), findsNothing);
    });
  });
}
