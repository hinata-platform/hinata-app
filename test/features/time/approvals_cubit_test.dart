import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/time_approval_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/time/approvals_cubit.dart';

import '../../support/recording_fake.dart';

/// The approvals page reads its submissions and their labels through this
/// cubit: each read reaches the repository as asked and comes back as it
/// answered.
void main() {
  final approval = TimesheetApproval(
    id: 'a1',
    userId: 'u1',
    projectId: 'p1',
    periodStart: DateTime(2026, 9, 1),
    periodEnd: DateTime(2026, 9, 30),
    status: ApprovalStatus.submitted,
  );
  const alpha = Project(id: 'p1', key: 'ALP', name: 'Alpha');
  const ada = DirectoryUser(id: 'u1', username: 'ada', displayName: 'Ada');

  late FakeTimeRepository time;
  late FakeUserRepository users;
  late FakeProjectRepository projects;
  late ApprovalsCubit cubit;

  setUp(() {
    time = FakeTimeRepository();
    users = FakeUserRepository();
    projects = FakeProjectRepository();
    cubit = ApprovalsCubit(time, users, projects);
    addTearDown(cubit.close);
  });

  test('reads a page of the scope asked for', () async {
    time.answer(#approvals, (items: [approval], total: 1));

    final page = await cubit.approvals(scope: 'inbox', page: 1, size: 25);

    expect(page.items, [approval]);
    expect(
      time.calls.single,
      invoked(#approvals, named: {#scope: 'inbox', #page: 1, #size: 25}),
    );
  });

  test('names the people and projects on screen', () async {
    users.answer(#usersByIds, [ada]);
    projects.answer(#resolveProjects, [alpha]);

    expect(await cubit.usersByIds(['u1']), [ada]);
    expect(await cubit.resolveProjects(['p1']), [alpha]);
    expect(
      users.calls.single,
      invoked(
        #usersByIds,
        positional: [
          ['u1'],
        ],
      ),
    );
    expect(
      projects.calls.single,
      invoked(
        #resolveProjects,
        positional: [
          ['p1'],
        ],
      ),
    );
  });

  test('passes a failure through', () async {
    time.fail(#approvals, failure);
    users.fail(#usersByIds, failure);
    projects.fail(#resolveProjects, failure);

    await expectLater(
      () => cubit.approvals(scope: 'mine', page: 0, size: 25),
      throwsFailure,
    );
    await expectLater(() => cubit.usersByIds(['u1']), throwsFailure);
    await expectLater(() => cubit.resolveProjects(['p1']), throwsFailure);
  });
}
