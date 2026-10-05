import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/availability_models.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/time_approval_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/timesheet/timesheet_cubit.dart';

import '../../support/recording_fake.dart';

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

  late FakeTimeRepository time;
  late FakeTimesheetRepository timesheets;
  late FakeUserRepository users;
  late FakeProjectRepository projects;
  late FakeAvailabilityRepository availability;
  late TimesheetCubit cubit;

  setUp(() {
    time = FakeTimeRepository();
    timesheets = FakeTimesheetRepository();
    users = FakeUserRepository();
    projects = FakeProjectRepository();
    availability = FakeAvailabilityRepository();
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
    time.answer(#timesheet, (items: [row], total: 1));
    timesheets.answer(#timesheet, [row]);

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
    time.answer(#approvalPeriods, [period]);

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
    users.answer(#usersByIds, [ada]);
    users.answer(#searchUsers, (items: [ada], total: 1));
    projects.answer(#resolveProjects, [alpha]);
    projects.answer(#searchProjects, (projects: [alpha], total: 1));

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
    availability.answer(#capacity, capacity);

    expect(await cubit.capacity(from, to), capacity);
    expect(
      availability.calls.single,
      invoked(#capacity, positional: [from, to]),
    );
  });

  test('passes a failure through', () async {
    time
      ..fail(#timesheet, failure)
      ..fail(#approvalPeriods, failure);
    timesheets.fail(#timesheet, failure);
    users
      ..fail(#usersByIds, failure)
      ..fail(#searchUsers, failure);
    projects
      ..fail(#resolveProjects, failure)
      ..fail(#searchProjects, failure);
    availability.fail(#capacity, failure);

    await expectLater(
      () => cubit.moduleRows(from: from, to: to, size: 200),
      throwsFailure,
    );
    await expectLater(() => cubit.rows(from, to), throwsFailure);
    await expectLater(
      () => cubit.approvalPeriods(from: from, to: to),
      throwsFailure,
    );
    await expectLater(() => cubit.usersByIds(['u1']), throwsFailure);
    await expectLater(() => cubit.resolveProjects(['p1']), throwsFailure);
    await expectLater(
      () => cubit.searchUsers('', page: 0, size: 20),
      throwsFailure,
    );
    await expectLater(
      () => cubit.searchProjects(query: '', page: 0, size: 20),
      throwsFailure,
    );
    await expectLater(() => cubit.capacity(from, to), throwsFailure);
  });
}
