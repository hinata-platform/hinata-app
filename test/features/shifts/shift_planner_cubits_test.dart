import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/shift_models.dart';
import 'package:hinata/features/account/shift_feed_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_calendar_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_changes.dart';
import 'package:hinata/features/shifts/bloc/shift_editor_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_event_editor_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_planning_cubit.dart';

import 'shift_fakes.dart';

/// The planner's cubits (HIN-160) and the feed's (HIN-47).
void main() {
  late FakeShiftRepository repo;
  late StreamController<ShiftChange> bus;

  setUp(() {
    repo = FakeShiftRepository();
    bus = StreamController<ShiftChange>.broadcast();
    addTearDown(bus.close);
  });

  ShiftCalendar month(List<Shift> shifts, {Set<String> plannable = const {}}) =>
      ShiftCalendar(
        shifts: shifts,
        events: const {'e1': sampleEvent},
        plannableProjectIds: plannable,
      );

  group('ShiftCalendarCubit', () {
    ShiftCalendarCubit calendar({String? projectId}) => ShiftCalendarCubit(
      repo,
      focused: DateTime(2026, 10, 24),
      projectId: projectId,
      changes: bus.stream,
    );

    test('opens on three months, each read once', () async {
      final cubit = calendar();
      addTearDown(cubit.close);
      await cubit.start();
      expect(repo.calls, [
        'calendar:202609:all',
        'calendar:202610:all',
        'calendar:202611:all',
      ]);
      // Scrolling near them again asks for nothing; a new month for itself.
      await cubit.ensureMonths([DateTime(2026, 10), DateTime(2026, 12)]);
      expect(repo.calls.where((c) => c.startsWith('calendar:')), hasLength(4));
      expect(repo.calls.last, 'calendar:202612:all');
    });

    test('a day in a held month never reads again when focused', () async {
      final cubit = calendar();
      addTearDown(cubit.close);
      await cubit.start();
      cubit.focus(DateTime(2026, 10, 25));
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls, hasLength(3));
    });

    test('the month reads counts per day, the week shifts', () async {
      repo.marksMonths[202610] = [
        ShiftDayMarks(date: DateTime(2026, 10, 24), mine: 1, understaffed: 2),
      ];
      final cubit = calendar();
      addTearDown(cubit.close);
      cubit.setSpan(ShiftCalendarSpan.month);
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls, [
        'marks:202609:all',
        'marks:202610:all',
        'marks:202611:all',
      ]);
      expect(cubit.marksOn(DateTime(2026, 10, 24))!.understaffed, 2);
      expect(cubit.marksOn(DateTime(2026, 10, 25)), isNull);
      expect(cubit.state.months, isEmpty);

      cubit.openDay(DateTime(2026, 10, 24));
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls.where((c) => c.startsWith('calendar:')), hasLength(3));
    });

    test('keeps the four months used last', () async {
      final cubit = calendar();
      addTearDown(cubit.close);
      await cubit.start();
      for (var m = 12; m <= 15; m++) {
        await cubit.ensureMonths([DateTime(2026, m)]);
      }
      expect(cubit.state.months.length, ShiftCalendarCubit.monthCacheSize);
      expect(cubit.state.months.keys.toSet(), {202612, 202701, 202702, 202703});
    });

    test('a sign-up is put in from the answer, its counts read again, and '
        'nothing while hidden', () async {
      final shift = sampleShift(id: 's1', assigned: 1, required: 2);
      repo.calendarMonths[202610] = month([shift]);
      final cubit = calendar();
      addTearDown(cubit.close);
      await cubit.start();
      cubit.setSpan(ShiftCalendarSpan.month);
      await Future<void>.delayed(Duration.zero);
      repo.calls.clear();

      cubit.setVisible(false);
      bus.add(
        ShiftChange(
          shiftId: 's1',
          shift: sampleShift(id: 's1', assigned: 2, required: 2, mine: true),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(cubit.shiftsOn(DateTime(2026, 10, 24)).single.mine, isTrue);
      expect(repo.calls, isEmpty);

      cubit.setVisible(true);
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls, ['marks:202610:all']);
    });

    test('files shifts by day, a night shift on both, and filters short '
        'ones without a request', () async {
      repo.calendarMonths[202610] = month(
        [
          sampleShift(id: 'full', assigned: 2, required: 2),
          sampleShift(id: 'short', assigned: 1, required: 2),
          sampleShift(
            id: 'night',
            assigned: 2,
            required: 2,
            start: DateTime(2026, 10, 24, 22),
            length: const Duration(hours: 6),
          ),
        ],
        plannable: {'p1'},
      );
      final cubit = calendar();
      addTearDown(cubit.close);
      await cubit.start();
      expect(cubit.shiftsOn(DateTime(2026, 10, 24)).map((s) => s.id), [
        'full',
        'short',
        'night',
      ]);
      expect(cubit.shiftsOn(DateTime(2026, 10, 25)).map((s) => s.id), [
        'night',
      ]);
      expect(cubit.state.canPlan('p1'), isTrue);
      final before = repo.calls.length;
      cubit.toggleUnderstaffed();
      expect(cubit.shiftsOn(DateTime(2026, 10, 24)).map((s) => s.id), [
        'short',
      ]);
      expect(repo.calls.length, before);
    });

    test(
      'a project narrows it and reads the months for that project',
      () async {
        final cubit = calendar();
        addTearDown(cubit.close);
        await cubit.start();
        cubit.setProject('p9', name: 'Messe');
        await Future<void>.delayed(Duration.zero);
        expect(repo.calls.where((c) => c.endsWith(':p9')), hasLength(3));
        expect(cubit.state.projectName, 'Messe');
      },
    );

    test('a move patches both instants and reads the months again', () async {
      final shift = sampleShift(id: 's1');
      repo.calendarMonths[202610] = month([shift], plannable: {'p1'});
      repo.shiftEdit = ShiftEdit(
        shift: shift,
        warnings: const [
          ShiftWarning(userId: 'u1'),
          ShiftWarning(userId: 'u1', shiftId: 'x'),
          ShiftWarning(userId: 'u2'),
        ],
      );
      final cubit = calendar();
      addTearDown(cubit.close);
      await cubit.start();
      final outcome = await cubit.move(
        shift,
        DateTime(2026, 10, 24, 15),
        DateTime(2026, 10, 24, 18),
      );
      expect(outcome.ok, isTrue);
      expect(ShiftWarning.people(outcome.edit!.warnings), 2);
      expect(repo.lastPatch!.keys, {'startsAt', 'endsAt'});
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls.where((c) => c == 'calendar:202610:all'), hasLength(2));
    });

    test('a refused move names the module\'s key', () async {
      final shift = sampleShift(id: 's1');
      final cubit = calendar();
      addTearDown(cubit.close);
      repo.failure = refusal('error.shifts.shiftOutsideEvent', status: 400);
      final outcome = await cubit.move(
        shift,
        DateTime(2026, 10, 24, 15),
        DateTime(2026, 10, 24, 18),
      );
      expect(outcome.errorKey, 'error.shifts.shiftOutsideEvent');
    });

    test('a month that fails is held as failed and read on retry', () async {
      repo.failure = refusal('error.shifts.windowInvalid', status: 400);
      final cubit = calendar();
      addTearDown(cubit.close);
      await cubit.start();
      expect(cubit.state.failed, hasLength(3));
      repo.failure = null;
      await cubit.retry(DateTime(2026, 10));
      expect(cubit.state.months.keys, [202610]);
    });
  });

  group('ShiftEditorCubit', () {
    final event = sampleSummary();

    ShiftEditorCubit editor({Shift? shift}) => ShiftEditorCubit(
      repo,
      event: event,
      shift: shift,
      deviceZone: 'Europe/Berlin',
    );

    test('opens where the event does, needing one, without a limit', () {
      final cubit = editor();
      addTearDown(cubit.close);
      expect(cubit.state.day, DateTime(2026, 10, 24));
      expect(cubit.state.fromMinutes, 14 * 60);
      expect(cubit.state.requiredHelpers, 1);
      expect(cubit.state.maxHelpers, isNull);
      expect(cubit.eventDays, [DateTime(2026, 10, 24), DateTime(2026, 10, 25)]);
    });

    test('the limit never drops below the need', () {
      final cubit = editor();
      addTearDown(cubit.close);
      cubit.stepRequired(2);
      expect(cubit.state.requiredHelpers, 3);
      cubit.stepMax(1);
      expect(cubit.state.maxHelpers, 3, reason: 'from none it starts at need');
      expect(cubit.canLowerMax, isFalse);
      cubit.stepMax(-1);
      expect(cubit.state.maxHelpers, 3);
      cubit.stepRequired(1);
      expect(cubit.state.maxHelpers, 4, reason: 'raising the need raises it');
      cubit.clearMax();
      expect(cubit.state.maxHelpers, isNull);
      cubit.stepRequired(-10);
      expect(cubit.state.requiredHelpers, 1);
    });

    test(
      'blocks a shift that ends when it starts or leaves the event',
      () async {
        final cubit = editor();
        addTearDown(cubit.close);
        cubit.setTo(cubit.state.fromMinutes);
        expect(await cubit.save(), isFalse);
        expect(cubit.problem, ShiftEditorProblem.endBeforeStart);
        cubit.setFrom(10 * 60);
        cubit.setTo(12 * 60);
        expect(cubit.problem, ShiftEditorProblem.outsideEvent);
        expect(repo.calls, isEmpty);
      },
    );

    test('a night shift ends on the next day', () {
      final cubit = editor();
      addTearDown(cubit.close);
      cubit.setFrom(22 * 60);
      cubit.setTo(2 * 60);
      expect(cubit.state.endWall, DateTime(2026, 10, 25, 2));
      expect(cubit.problem, isNull);
    });

    test('saves every chosen day in one batch', () async {
      final cubit = editor();
      addTearDown(cubit.close);
      cubit
        ..setTitle('Kasse')
        ..setFrom(15 * 60)
        ..setTo(18 * 60);
      cubit.setDay(DateTime(2026, 10, 24));
      // The event ends at 03:00 on the 25th, so the 25th cannot hold it.
      cubit.toggleExtraDay(DateTime(2026, 10, 25));
      expect(await cubit.save(), isFalse);
      expect(cubit.state.dayErrors.keys, [DateTime(2026, 10, 25)]);
      expect(repo.calls, isEmpty, reason: 'caught before sending');
      cubit.toggleExtraDay(DateTime(2026, 10, 25));
      expect(await cubit.save(), isTrue);
      expect(repo.calls, ['createShifts:e1:1']);
      expect(repo.lastTemplate!.title, 'Kasse');
    });

    test('a refused batch names each failed day', () async {
      final cubit = editor();
      addTearDown(cubit.close);
      repo.failure = ApiFailure(
        'Server sentence',
        statusCode: 400,
        details: {
          'code': 'error.shifts.batchInvalid',
          '2026-10-24': 'error.shifts.tooManyShifts',
        },
      );
      expect(await cubit.save(), isFalse);
      expect(cubit.state.errorKey, 'error.shifts.batchInvalid');
      expect(cubit.state.dayErrors, {
        DateTime(2026, 10, 24): 'error.shifts.tooManyShifts',
      });
    });

    test(
      'editing sends only what changed; no limit is said in words',
      () async {
        final shift = sampleShift(required: 2, max: 4);
        repo.shiftEdit = ShiftEdit(shift: shift);
        final cubit = editor(shift: shift);
        addTearDown(cubit.close);
        cubit.clearMax();
        expect(await cubit.save(), isTrue);
        expect(repo.lastPatch, {'clearMaxHelpers': true});
      },
    );

    test('a limit under the people on it keeps their number', () async {
      final shift = sampleShift(required: 2, max: 5, assigned: 4);
      final cubit = editor(shift: shift);
      addTearDown(cubit.close);
      repo.failure = ApiFailure(
        'Server sentence',
        statusCode: 409,
        details: {'code': 'error.shifts.maxBelowAssigned', 'assigned': '4'},
      );
      cubit.stepMax(-1);
      expect(await cubit.save(), isFalse);
      expect(cubit.state.errorKey, 'error.shifts.maxBelowAssigned');
      expect(cubit.state.errorDetails['assigned'], '4');
    });
  });

  group('ShiftEventEditorCubit', () {
    test('a new event needs a name and a project', () async {
      final cubit = ShiftEventEditorCubit(
        repo,
        deviceZone: 'Europe/Berlin',
        day: DateTime(2026, 11, 7),
      );
      addTearDown(cubit.close);
      expect(await cubit.save(), isNull);
      expect(cubit.problem, ShiftEventProblem.titleMissing);
      cubit.setTitle('Sommerfest');
      expect(cubit.problem, ShiftEventProblem.projectMissing);
      cubit.setProject('p1', 'Verein');
      cubit.setEnd(cubit.state.start.add(const Duration(days: 15)));
      expect(cubit.problem, ShiftEventProblem.tooLong);
      cubit.setEnd(cubit.state.start);
      expect(cubit.problem, ShiftEventProblem.endBeforeStart);
      expect(repo.calls, isEmpty);
    });

    test('creates in the chosen project, in the device zone', () async {
      repo.createdEvent = ShiftEventDetail(summary: sampleSummary());
      final cubit = ShiftEventEditorCubit(
        repo,
        projectId: 'p1',
        projectName: 'Messe',
        deviceZone: 'Europe/Berlin',
        day: DateTime(2026, 11, 7),
      );
      addTearDown(cubit.close);
      cubit.setTitle('  Tag der offenen Tür ');
      final saved = await cubit.save();
      expect(saved, isNotNull);
      expect(repo.calls, ['createEvent:p1']);
      final body = repo.lastEventInput!.toDraftJson();
      expect(body['title'], 'Tag der offenen Tür');
      expect(body['timezone'], 'Europe/Berlin');
      expect(
        body['startsAt'],
        DateTime(2026, 11, 7, 10).toUtc().toIso8601String(),
      );
    });

    test('a change in zone keeps the wall clock and asks when shifts move', () {
      final existing = ShiftEventDetail(
        summary: sampleSummary(),
        shifts: [sampleShift()],
      );
      final cubit = ShiftEventEditorCubit(
        repo,
        existing: existing,
        deviceZone: 'Europe/Berlin',
      );
      addTearDown(cubit.close);
      expect(cubit.zoneChangeMovesShifts, isFalse);
      cubit.setTimezone('America/New_York');
      expect(cubit.state.start, DateTime(2026, 10, 24, 14));
      expect(cubit.zoneChangeMovesShifts, isTrue);
    });

    test('a move answers with who collides', () async {
      final existing = ShiftEventDetail(summary: sampleSummary());
      repo.eventChange = ShiftEventChange(
        event: existing,
        warnings: const [ShiftWarning(userId: 'u1')],
      );
      final cubit = ShiftEventEditorCubit(
        repo,
        existing: existing,
        deviceZone: 'Europe/Berlin',
      );
      addTearDown(cubit.close);
      cubit.setStart(DateTime(2026, 10, 24, 16));
      final saved = await cubit.save();
      expect(saved!.warnings, hasLength(1));
      expect(repo.lastPatch!.keys, {'startsAt', 'endsAt'});
    });
  });

  group('ShiftPlanningCubit', () {
    test('assigning answers with the shift and the absence hint', () async {
      repo.assigned = ShiftAssignResult(
        shift: sampleShift(assigned: 2),
        warnings: const ['absent'],
      );
      final cubit = ShiftPlanningCubit(repo);
      addTearDown(cubit.close);
      final outcome = await cubit.assign(sampleShift(), 'u2');
      expect(repo.calls, ['assign:s1:u2']);
      expect(outcome.absent, isTrue);
      expect(outcome.shift!.assignedCount, 2);
    });

    test('taking somebody off releases their place', () async {
      final cubit = ShiftPlanningCubit(repo);
      addTearDown(cubit.close);
      await cubit.remove(
        sampleShift(),
        const ShiftPlace(id: 'a9', userId: 'u2'),
      );
      expect(repo.calls, ['release:a9']);
    });

    test('a refused delete names the module key', () async {
      repo.failure = refusal('error.shifts.eventHasAssignments');
      final cubit = ShiftPlanningCubit(repo);
      addTearDown(cubit.close);
      final outcome = await cubit.deleteEvent('e1');
      expect(outcome.errorKey, 'error.shifts.eventHasAssignments');
    });
  });

  group('ShiftFeedCubit', () {
    test('shows a new address once and forgets it', () async {
      final cubit = ShiftFeedCubit(repo);
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.exists, isFalse);
      expect(await cubit.create(), isNull);
      expect(cubit.state.address!.webcalUrl, startsWith('webcal://'));
      expect(cubit.state.exists, isTrue);
      cubit.hideAddress();
      expect(cubit.state.address, isNull);
      expect(cubit.state.exists, isTrue);
    });

    test('removing ends it', () async {
      repo.feedStatus = ShiftFeedStatus(
        exists: true,
        createdAt: DateTime(2026, 10, 20),
      );
      final cubit = ShiftFeedCubit(repo);
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.exists, isTrue);
      await cubit.remove();
      expect(repo.calls, ['feed', 'deleteFeed']);
      expect(cubit.state.exists, isFalse);
    });
  });

  group('models', () {
    test('a shift reads the caller\'s place from myAssignment', () {
      final shift = Shift.fromJson(const {
        'id': 's1',
        'mine': true,
        'myAssignment': {'id': 'a1', 'status': 'ASSIGNED'},
      });
      expect(shift.myAssignmentId, 'a1');
      expect(shift.myStatus, ShiftAssignmentStatus.assigned);
      final detail = ShiftDetail.fromJson(const {
        'shift': {
          'id': 's1',
          'mine': true,
          'myAssignment': {'id': 'a1', 'status': 'CONFIRMED'},
        },
        'assignments': [
          {'id': 'a1', 'userId': 'me', 'status': 'CONFIRMED'},
          {'id': 'a2', 'userId': 'u2', 'status': 'ASSIGNED'},
          {'id': 'broken'},
        ],
      });
      expect(detail.myAssignment!.status, ShiftAssignmentStatus.confirmed);
      expect(detail.placeOf('u2')!.id, 'a2');
      expect(detail.places, hasLength(2));
    });

    test('a calendar names the projects the caller plans', () {
      final calendar = ShiftCalendar.fromJson(const {
        'shifts': [],
        'plannableProjectIds': ['p1', 7],
      });
      expect(calendar.plannableProjectIds, {'p1'});
    });

    test('a feed address falls back to webcal from https', () {
      final address = ShiftFeedAddress.fromJson(const {
        'url': 'https://h.example/api/v1/shifts/feed/t.ics',
      });
      expect(address.webcalUrl, 'webcal://h.example/api/v1/shifts/feed/t.ics');
    });
  });
}
