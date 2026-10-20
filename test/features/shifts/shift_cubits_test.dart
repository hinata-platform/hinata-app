import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/shift_models.dart';
import 'package:hinata/features/projects/settings/shift_planners_cubit.dart';
import 'package:hinata/features/shifts/bloc/my_shifts_cubit.dart';
import 'package:hinata/features/shifts/bloc/my_shifts_snapshot_cubit.dart';
import 'package:hinata/features/shifts/bloc/next_shift_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_actions_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_changes.dart';
import 'package:hinata/features/shifts/bloc/shift_event_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_events_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_sheet_cubit.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../../support/timer_surface_fakes.dart' show MemoryStorage;
import 'shift_fakes.dart';

void main() {
  late FakeShiftRepository repo;
  late StreamController<ShiftChange> bus;

  setUp(() {
    HydratedBloc.storage = MemoryStorage();
    repo = FakeShiftRepository();
    bus = StreamController<ShiftChange>.broadcast();
    addTearDown(bus.close);
  });

  group('MyShiftsCubit', () {
    test(
      'hands only a fresh first page to the snapshot, never a later one',
      () async {
        final written = <List<MyShift>>[];
        repo.minePages = [
          (items: [sampleMine(assignmentId: 'a1')], total: 2),
          (items: [sampleMine(assignmentId: 'a2')], total: 2),
        ];
        final cubit = MyShiftsCubit(
          repo,
          pageSize: 1,
          onFirstPage: written.add,
          changes: bus.stream,
        );
        addTearDown(cubit.close);

        await cubit.load();
        await cubit.loadMore();

        expect(cubit.state.items.map((r) => r.assignmentId), ['a1', 'a2']);
        expect(written, hasLength(1));
        expect(written.single.single.assignmentId, 'a1');
      },
    );

    test('a failed load writes nothing', () async {
      final written = <List<MyShift>>[];
      repo.failure = ApiFailure('offline');
      final cubit = MyShiftsCubit(
        repo,
        onFirstPage: written.add,
        changes: bus.stream,
      );
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.errorKey, 'offline');
      expect(written, isEmpty);
    });

    test(
      'a change without a shift reads the held rows once, debounced',
      () async {
        repo.mine = (items: [sampleMine()], total: 1);
        final cubit = MyShiftsCubit(repo, changes: bus.stream);
        addTearDown(cubit.close);
        await cubit.load();
        repo.calls.clear();

        bus
          ..add(const ShiftChange(shiftId: 's1'))
          ..add(const ShiftChange(shiftId: 's2'));
        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(repo.calls, ['myShifts:0']);
      },
    );

    test('an answer is put into the rows held without a request', () async {
      final row = sampleMine(
        assignmentId: 'a1',
        status: ShiftAssignmentStatus.assigned,
      );
      final other = sampleMine(
        assignmentId: 'a2',
        shift: sampleShift(id: 's2', mine: true),
      );
      repo.mine = (items: [row, other], total: 2);
      final cubit = MyShiftsCubit(repo, changes: bus.stream);
      addTearDown(cubit.close);
      await cubit.load();
      repo.calls.clear();

      bus.add(
        ShiftChange(
          shiftId: 's1',
          shift: sampleShift(
            mine: true,
            myStatus: ShiftAssignmentStatus.confirmed,
            myAssignmentId: 'a1',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(repo.calls, isEmpty);
      expect(cubit.state.items.first.status, ShiftAssignmentStatus.confirmed);

      // Given away: the row goes, still without a request.
      bus.add(ShiftChange(shiftId: 's1', shift: sampleShift()));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(repo.calls, isEmpty);
      expect(cubit.state.items, [other]);
    });

    test('a new place reads the pages held in one request, and waits while '
        'hidden', () async {
      repo.minePages = [
        (items: [sampleMine(assignmentId: 'a1')], total: 3),
        (items: [sampleMine(assignmentId: 'a2')], total: 3),
      ];
      final cubit = MyShiftsCubit(repo, pageSize: 1, changes: bus.stream);
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.loadMore();
      repo
        ..calls.clear()
        ..minePages = null
        ..mine = (
          items: [
            sampleMine(assignmentId: 'a1'),
            sampleMine(assignmentId: 'a9'),
          ],
          total: 3,
        );

      cubit.setVisible(false);
      bus.add(
        ShiftChange(
          shiftId: 's9',
          shift: sampleShift(id: 's9', mine: true),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(repo.calls, isEmpty);

      cubit.setVisible(true);
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls, ['myShifts:0']);
      expect(repo.lastMineSize, 2);
      expect(cubit.state.items.map((r) => r.assignmentId), ['a1', 'a9']);
    });
  });

  group('MyShiftsSnapshotCubit', () {
    test('keeps at most fifty rows and forgets on demand', () async {
      final cubit = MyShiftsSnapshotCubit(storageId: 'shifts#test');
      addTearDown(cubit.close);
      cubit.recordRows([
        for (var i = 0; i < 60; i++) sampleMine(assignmentId: 'a$i'),
      ]);
      cubit.recordNext(sampleMine(assignmentId: 'n'));
      expect(cubit.state.rows, hasLength(MyShiftsSnapshot.maxRows));
      expect(cubit.state.next!.assignmentId, 'n');

      final restored = cubit.fromJson(cubit.toJson(cubit.state)!)!;
      expect(restored.rows.first.assignmentId, 'a0');
      expect(restored.next!.assignmentId, 'n');

      await cubit.forget();
      expect(cubit.state.isEmpty, isTrue);
    });
  });

  group('NextShiftCubit', () {
    test('reads the next shift, its people and the open shifts', () async {
      final next = sampleMine();
      repo
        ..next = next
        ..shiftDetail = ShiftDetail(
          shift: next.shift,
          event: sampleEvent,
          users: const {'u1': ShiftUser(name: 'Lena Vogt')},
        )
        ..open = ShiftCalendar(
          shifts: [
            sampleShift(id: 'o1'),
            sampleShift(id: 'o2', mine: true),
          ],
        );
      MyShift? recorded;
      final cubit = NextShiftCubit(
        repo,
        onNext: (n) => recorded = n,
        changes: bus.stream,
      );
      addTearDown(cubit.close);

      await cubit.load();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.next, next);
      expect(recorded, next);
      expect(cubit.state.nextDetail!.users['u1']!.name, 'Lena Vogt');
      // Never offered a shift the caller is already on.
      expect(cubit.state.open.shifts.map((s) => s.id), ['o1']);
      expect(repo.calls, containsAll(['next', 'open:3', 'shift:s1']));
    });

    test('open shifts failing does not take the next one down', () async {
      repo.next = sampleMine();
      final cubit = _FailingOpen(repo, bus.stream);
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.next, isNotNull);
      expect(cubit.state.open.shifts, isEmpty);
    });

    test('a change reads the next shift alone, not all four', () async {
      repo.next = sampleMine(
        shift: sampleShift(
          id: 's1',
          mine: true,
          myStatus: ShiftAssignmentStatus.confirmed,
        ),
      );
      final cubit = NextShiftCubit(repo, changes: bus.stream);
      addTearDown(cubit.close);
      await cubit.load();
      await Future<void>.delayed(Duration.zero);
      repo.calls.clear();

      // A place earlier than the hero's: which one is next, the server says.
      bus.add(
        ShiftChange(
          shiftId: 's0',
          shift: sampleShift(
            id: 's0',
            mine: true,
            start: DateTime(2026, 10, 23, 9),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(repo.calls, ['next']);

      // Joining a waiting list reads the waiting lists alone.
      repo.calls.clear();
      bus.add(
        ShiftChange(
          shiftId: 's5',
          shift: sampleShift(id: 's5', myWaitPosition: 2),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(repo.calls, ['waiting']);
    });

    test(
      'the waiting lists failing is said, and what was held stays',
      () async {
        final waits = sampleMine(
          assignmentId: 'w1',
          status: ShiftAssignmentStatus.waiting,
        );
        repo
          ..next = sampleMine()
          ..waiting = [waits];
        final cubit = NextShiftCubit(repo, changes: bus.stream);
        addTearDown(cubit.close);
        await cubit.load();
        expect(cubit.state.waiting, [waits]);
        expect(cubit.state.waitingFailed, isFalse);

        repo.waitingFailure = ApiFailure('errors.unexpected');
        await cubit.load();

        expect(cubit.state.next, isNotNull);
        expect(cubit.state.waitingFailed, isTrue);
        expect(cubit.state.waiting, [waits]);
      },
    );
  });

  group('ShiftEventsCubit', () {
    test(
      'reads two months from today, across projects or within one',
      () async {
        final cubit = ShiftEventsCubit(
          repo,
          now: () => DateTime(2026, 10, 20, 15),
          changes: bus.stream,
        );
        addTearDown(cubit.close);

        await cubit.load();
        expect(repo.calls.last, 'events:all:0');
        expect(repo.lastFrom, DateTime(2026, 10, 20));
        expect(repo.lastTo, DateTime(2026, 12, 20));

        await cubit.filter('p7');
        expect(repo.calls.last, 'events:p7:0');
        expect(cubit.projectId, 'p7');
      },
    );
  });

  group('ShiftEventCubit', () {
    test('filters to understaffed and replaces a row from an answer', () async {
      repo.eventDetail = ShiftEventDetail(
        summary: sampleSummary(),
        shifts: [
          sampleShift(id: 'a', assigned: 1, required: 2),
          sampleShift(id: 'b', assigned: 2, required: 2),
        ],
      );
      final cubit = ShiftEventCubit(repo, 'e1', changes: bus.stream);
      addTearDown(cubit.close);
      await cubit.load();

      cubit.toggleUnderstaffed();
      expect(cubit.state.visibleShifts.map((s) => s.id), ['a']);

      cubit.applyShift(sampleShift(id: 'a', assigned: 2, required: 2));
      expect(cubit.state.visibleShifts, isEmpty);
      expect(cubit.state.detail!.shifts.first.assignedCount, 2);
    });

    test('a cancelled shift is never among the understaffed', () async {
      repo.eventDetail = ShiftEventDetail(
        summary: sampleSummary(),
        shifts: [
          sampleShift(id: 'a', assigned: 0, required: 2, cancelled: true),
          sampleShift(id: 'b', assigned: 1, required: 2),
        ],
      );
      final cubit = ShiftEventCubit(repo, 'e1', changes: bus.stream);
      addTearDown(cubit.close);
      await cubit.load();

      cubit.toggleUnderstaffed();
      expect(cubit.state.visibleShifts.map((s) => s.id), ['b']);
    });
  });

  group('ShiftActionsCubit', () {
    test('signs up, says so on the bus and returns the new shift', () async {
      final heard = <ShiftChange>[];
      final changes = ShiftChanges.instance.changes.listen(heard.add);
      addTearDown(changes.cancel);
      repo.assignResult = ShiftAssignResult(
        shift: sampleShift(assigned: 2, mine: true),
        warnings: const ['absent'],
      );
      final cubit = ShiftActionsCubit(repo);
      addTearDown(cubit.close);

      final outcome = await cubit.join(sampleShift());
      await Future<void>.delayed(Duration.zero);

      expect(outcome.ok, isTrue);
      expect(outcome.messageKey, 'shifts.done.joined');
      expect(outcome.absent, isTrue);
      expect(outcome.shift!.assignedCount, 2);
      expect(heard.single.shiftId, 's1');
      expect(cubit.state.busy, isEmpty);
    });

    test('a refusal comes back as the module\'s own key', () async {
      repo.failure = refusal('error.shifts.shiftFull');
      final cubit = ShiftActionsCubit(repo);
      addTearDown(cubit.close);

      final outcome = await cubit.join(sampleShift());

      expect(outcome.ok, isFalse);
      expect(outcome.errorKey, 'error.shifts.shiftFull');
    });

    test('without a code the server\'s sentence is shown', () async {
      repo.failure = ApiFailure('Nur wer plant', statusCode: 403);
      final cubit = ShiftActionsCubit(repo);
      addTearDown(cubit.close);
      expect((await cubit.release('s1', 'a1')).errorKey, 'Nur wer plant');
    });

    test(
      'confirm hands back the place, release and decline the shift',
      () async {
        repo
          ..confirmed = sampleMine(status: ShiftAssignmentStatus.confirmed)
          ..releaseResult = ShiftAssignResult(shift: sampleShift(assigned: 0));
        final cubit = ShiftActionsCubit(repo);
        addTearDown(cubit.close);

        final confirmed = await cubit.confirm('s1', 'a1');
        expect(confirmed.myShift!.status, ShiftAssignmentStatus.confirmed);
        expect(confirmed.shift!.myStatus, ShiftAssignmentStatus.confirmed);

        final released = await cubit.release('s1', 'a1');
        expect(released.messageKey, 'shifts.done.released');
        expect(released.shift!.assignedCount, 0);

        final declined = await cubit.decline('s1', 'a1');
        expect(declined.messageKey, 'shifts.done.declined');
        expect(repo.calls, ['confirm:a1', 'release:a1', 'decline:a1']);
      },
    );
  });

  group('ShiftSheetCubit', () {
    test(
      'drops the opener\'s place once the shift is not the caller\'s',
      () async {
        repo.shiftDetail = ShiftDetail(
          shift: sampleShift(),
          event: sampleEvent,
        );
        final cubit = ShiftSheetCubit(
          repo,
          's1',
          assignment: const ShiftAssignmentRef(
            id: 'a1',
            status: ShiftAssignmentStatus.confirmed,
          ),
        );
        addTearDown(cubit.close);
        await cubit.load();
        expect(cubit.state.assignment, isNull);
      },
    );
  });

  group('ShiftPlannersCubit', () {
    test('grants, revokes and reads again; a refusal names the key', () async {
      repo.plannerList = const ShiftPlanners(
        planners: [ShiftPlanner(userId: 'u1')],
        users: {'u1': ShiftUser(name: 'Lena Vogt')},
      );
      final cubit = ShiftPlannersCubit(repo, 'p1');
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.planners!.planners.single.userId, 'u1');

      expect(await cubit.add(['u2', 'u3']), isNull);
      expect(await cubit.remove('u1'), isNull);
      expect(repo.calls, [
        'planners:p1',
        'addPlanner:u2',
        'addPlanner:u3',
        'planners:p1',
        'removePlanner:u1',
        'planners:p1',
      ]);

      repo.failure = refusal('error.shifts.plannerNotMember', status: 400);
      expect(await cubit.add(['x']), 'error.shifts.plannerNotMember');

      repo.failure = ApiFailure('Verboten', statusCode: 403);
      expect(await cubit.remove('u1'), 'error.shifts.notPlanner');
    });
  });
}

class _FailingOpen extends NextShiftCubit {
  _FailingOpen(FakeShiftRepository repo, Stream<ShiftChange> changes)
    : super(_OpenFails(repo), changes: changes);
}

class _OpenFails extends FakeShiftRepository {
  _OpenFails(this.inner);
  final FakeShiftRepository inner;

  @override
  Future<MyShift?> nextShift() => inner.nextShift();

  @override
  Future<ShiftCalendar> openShifts({
    required DateTime from,
    required DateTime to,
    int limit = 3,
  }) => Future.error(ApiFailure('boom'));
}
