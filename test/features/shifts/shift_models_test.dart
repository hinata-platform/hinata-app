import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/shift_models.dart';

import 'shift_fakes.dart';

/// The module reads the server's records leniently (HIN-44): what a stage
/// adds later is optional, and nothing of somebody else survives into the
/// offline snapshot.
void main() {
  final shiftJson = {
    'id': 's1',
    'eventId': 'e1',
    'projectId': 'p1',
    'title': 'Kasse',
    'startsAt': '2026-10-24T16:00:00Z',
    'endsAt': '2026-10-24T20:00:00Z',
    'startsLocal': '2026-10-24T18:00:00',
    'endsLocal': '2026-10-24T22:00:00',
    'requiredHelpers': 3,
    'maxHelpers': 4,
    'assignedCount': 3,
    'understaffed': false,
    'full': false,
    'mine': true,
    'cancelled': false,
    'assigneeIds': ['u1', 'u2', 'me'],
  };

  test('a shift keeps the wall clock the server wrote', () {
    final shift = Shift.fromJson(shiftJson);
    expect(shift.startsLocal, DateTime(2026, 10, 24, 18));
    expect(shift.endsLocal, DateTime(2026, 10, 24, 22));
    expect(
      shift.startsAt.isAtSameMomentAs(DateTime.utc(2026, 10, 24, 16)),
      isTrue,
    );
    expect(shift.coverage, const Coverage(assigned: 3, required: 3, max: 4));
    expect(shift.coverage.state, CoverageState.met);
    expect(shift.assigneeIds, ['u1', 'u2', 'me']);
  });

  test('a shift missing optional fields still reads', () {
    final shift = Shift.fromJson(const {
      'id': 's2',
      'startsAt': '2026-10-24T16:00:00Z',
    });
    expect(shift.requiredHelpers, 1);
    expect(shift.maxHelpers, isNull);
    expect(shift.assigneeIds, isEmpty);
    expect(shift.endsAt, shift.startsAt);
  });

  test('coverage: the four states and the fill', () {
    expect(const Coverage(assigned: 1, required: 2).state, CoverageState.under);
    expect(const Coverage(assigned: 1, required: 2).missing, 1);
    expect(const Coverage(assigned: 2, required: 2).state, CoverageState.met);
    expect(const Coverage(assigned: 5, required: 4).state, CoverageState.over);
    expect(
      const Coverage(assigned: 5, required: 3, max: 5).state,
      CoverageState.full,
    );
    expect(const Coverage(assigned: 9, required: 3).fill, 1.0);
    expect(const Coverage(assigned: 0, required: 0).fill, 1.0);
  });

  test('short means somebody is missing and the shift still happens', () {
    expect(sampleShift(assigned: 1, required: 2).isShort, isTrue);
    expect(sampleShift(assigned: 2, required: 2).isShort, isFalse);
    expect(
      sampleShift(assigned: 0, required: 2, cancelled: true).isShort,
      isFalse,
    );
  });

  test('planners read the documented form only', () {
    final planners = ShiftPlanners.fromJson(const {
      'planners': [
        {
          'userId': 'u1',
          'grantedBy': 'u0',
          'createdAt': '2026-10-01T08:00:00Z',
        },
        {'id': 'u2'},
      ],
      'users': {
        'u1': {'name': 'Ann'},
      },
    });
    expect(planners.planners.map((p) => p.userId), ['u1']);
    expect(planners.users['u1']!.name, 'Ann');
    expect(
      ShiftPlanners.fromJson(const [
        {'userId': 'u1'},
      ]).planners,
      isEmpty,
    );
  });

  test('a detail takes the own place from the shift, places from '
      'assignments', () {
    final detail = ShiftDetail.fromJson(const {
      'shift': {
        'id': 's1',
        'mine': true,
        'myAssignment': {'id': 'a1', 'status': 'CONFIRMED'},
      },
      'event': {'id': 'e1'},
      'assignments': [
        {'id': 'a1', 'userId': 'u1', 'status': 'CONFIRMED'},
      ],
      'places': [
        {'id': 'a2', 'userId': 'u2', 'status': 'ASSIGNED'},
      ],
    });
    expect(detail.myAssignment?.id, 'a1');
    expect(detail.myAssignment?.status, ShiftAssignmentStatus.confirmed);
    expect(detail.places.map((p) => p.id), ['a1']);
  });

  test('a sign-up answer carries the caller\'s place onto the shift', () {
    final result = ShiftAssignResult.fromJson({
      'shift': {...shiftJson, 'mine': true},
      'assignment': const {
        'id': 'a9',
        'shiftId': 's1',
        'userId': 'me',
        'status': 'CONFIRMED',
        'assignedBy': null,
        'createdAt': '2026-10-20T08:00:00Z',
      },
      'warnings': const ['absent'],
    });
    expect(result.absent, isTrue);
    expect(result.shift.myAssignmentId, 'a9');
    expect(result.shift.myStatus, ShiftAssignmentStatus.confirmed);
  });

  test('a release answer leaves no place on the shift', () {
    final result = ShiftAssignResult.fromJson({
      'shift': {...shiftJson, 'mine': false, 'assignedCount': 2},
      'assignment': const {'id': 'a9', 'status': 'RELEASED'},
      'warnings': const <String>[],
    });
    expect(result.shift.mine, isFalse);
    expect(result.shift.myAssignmentId, isNull);
    expect(result.absent, isFalse);
  });

  test('planners read with their names once', () {
    final planners = ShiftPlanners.fromJson(const {
      'planners': [
        {
          'userId': 'u1',
          'grantedBy': 'lead',
          'createdAt': '2026-10-20T08:00:00Z',
        },
      ],
      'users': {
        'u1': {'name': 'Lena Vogt', 'avatarUrl': null},
      },
    });
    expect(planners.planners.single.userId, 'u1');
    expect(planners.users['u1']!.name, 'Lena Vogt');
  });

  test('the snapshot form names nobody else and reads back', () {
    final mine = MyShift.fromJson({
      'assignmentId': 'a1',
      'status': 'ASSIGNED',
      'assignedBy': 'planner-id',
      'shift': shiftJson,
      'event': const {
        'id': 'e1',
        'title': 'Sommerfest',
        'location': 'Festwiese',
        'timezone': 'Europe/Berlin',
        'selfAssignable': true,
        'cancelled': false,
      },
    });
    final json = mine.toSnapshotJson();
    expect(json.toString(), isNot(contains('planner-id')));
    expect((json['shift'] as Map).containsKey('assigneeIds'), isFalse);
    final back = MyShift.fromJson(json);
    expect(back.assignmentId, 'a1');
    expect(back.status, ShiftAssignmentStatus.assigned);
    expect(back.shift.startsLocal, DateTime(2026, 10, 24, 18));
    expect(back.shift.assigneeIds, isEmpty);
    expect(back.assignedBy, isNull);
  });
}
