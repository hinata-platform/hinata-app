import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/availability_models.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/time_approval_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/availability_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/repositories/timesheet_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/features/timesheet/timesheet_cubit.dart';

import '../time/recording_repository.dart';

/// The timesheet reads its rows, its period, its labels, its filter searches
/// and the reader's capacity through this cubit: each read reaches the right
/// repository as asked and comes back as it answered.
void main() {
  const row = TimesheetRow(
    userId: 'u1',
    projectId: 'p1',
    minutesPerDay: {},
    totalMinutes: 0,
  );
  const alpha = Project(id: 'p1', key: 'ALP', name: 'Alpha');
  const ada = DirectoryUser(id: 'u1', username: 'ada', displayName: 'Ada');
  final from = DateTime(2026, 9, 7);
  final to = DateTime(2026, 9, 13);

  late _FakeTime time;
  late _FakeTimesheets timesheets;
  late _FakeUsers users;
  late _FakeProjects projects;
  late _FakeAvailability availability;
  late TimesheetCubit cubit;

  setUp(() {
    time = _FakeTime();
    timesheets = _FakeTimesheets();
    users = _FakeUsers();
    projects = _FakeProjects();
    availability = _FakeAvailability();
    cubit = TimesheetCubit(
      time: time,
      timesheets: timesheets,
      users: users,
      projects: projects,
      availability: availability,
    );
    addTearDown(cubit.close);
  });

  test('reads rows from the route each page asks', () async {
    time.answers[#timesheet] = Future.value((items: [row], total: 1));
    timesheets.answers[#timesheet] = Future.value([row]);

    final page = await cubit.moduleRows(
      from: from,
      to: to,
      userId: 'u1',
      projectId: 'p1',
      size: 200,
    );
    final rows = await cubit.rows(from, to, userId: 'u1', projectId: 'p1');

    expect(page.items, [row]);
    expect(rows, [row]);
    expect(
      time.calls.single,
      invoked(
        #timesheet,
        named: {
          #from: from,
          #to: to,
          #userId: 'u1',
          #projectId: 'p1',
          #size: 200,
        },
      ),
    );
    expect(
      timesheets.calls.single,
      invoked(
        #timesheet,
        positional: [from, to],
        named: {#userId: 'u1', #projectId: 'p1'},
      ),
    );
  });

  test('reads the periods around a window', () async {
    final period = ApprovalPeriod(start: from, end: to, type: 'WEEKLY');
    time.answers[#approvalPeriods] = Future.value([period]);

    expect(await cubit.approvalPeriods(from: from, to: to, projectId: 'p1'), [
      period,
    ]);
    expect(
      time.calls.single,
      invoked(
        #approvalPeriods,
        named: {#from: from, #to: to, #projectId: 'p1'},
      ),
    );
  });

  test('names rows and searches the filters', () async {
    users.answers[#usersByIds] = Future.value([ada]);
    users.answers[#searchUsers] = Future.value((items: [ada], total: 1));
    projects.answers[#resolveProjects] = Future.value([alpha]);
    projects.answers[#searchProjects] = Future.value((
      projects: [alpha],
      total: 1,
    ));

    expect(await cubit.usersByIds(['u1']), [ada]);
    expect((await cubit.searchUsers('ad', page: 1, size: 20)).items, [ada]);
    expect(await cubit.resolveProjects(['p1']), [alpha]);
    expect(
      (await cubit.searchProjects(query: 'al', page: 1, size: 20)).projects,
      [alpha],
    );

    expect(users.calls, [
      invoked(
        #usersByIds,
        positional: [
          ['u1'],
        ],
      ),
      invoked(#searchUsers, positional: ['ad'], named: {#page: 1, #size: 20}),
    ]);
    expect(projects.calls, [
      invoked(
        #resolveProjects,
        positional: [
          ['p1'],
        ],
      ),
      invoked(#searchProjects, named: {#query: 'al', #page: 1, #size: 20}),
    ]);
  });

  test("reads the reader's capacity", () async {
    final capacity = Capacity(from: from, to: to);
    availability.answers[#capacity] = Future.value(capacity);

    expect(await cubit.capacity(from, to), capacity);
    expect(
      availability.calls.single,
      invoked(#capacity, positional: [from, to]),
    );
  });

  test('passes a refusal through', () async {
    for (final fake in <RecordingRepository>[
      time,
      timesheets,
      users,
      projects,
      availability,
    ]) {
      fake.failure = refusal;
    }

    await expectLater(
      () => cubit.moduleRows(from: from, to: to, size: 200),
      throwsRefusal,
    );
    await expectLater(() => cubit.rows(from, to), throwsRefusal);
    await expectLater(
      () => cubit.approvalPeriods(from: from, to: to),
      throwsRefusal,
    );
    await expectLater(() => cubit.usersByIds(['u1']), throwsRefusal);
    await expectLater(() => cubit.resolveProjects(['p1']), throwsRefusal);
    await expectLater(
      () => cubit.searchUsers('', page: 0, size: 20),
      throwsRefusal,
    );
    await expectLater(
      () => cubit.searchProjects(query: '', page: 0, size: 20),
      throwsRefusal,
    );
    await expectLater(() => cubit.capacity(from, to), throwsRefusal);
  });
}

class _FakeTime with RecordingRepository implements TimeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class _FakeTimesheets with RecordingRepository implements TimesheetRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class _FakeUsers with RecordingRepository implements UserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class _FakeProjects with RecordingRepository implements ProjectRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class _FakeAvailability
    with RecordingRepository
    implements AvailabilityRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}
