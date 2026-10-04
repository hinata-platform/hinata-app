import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/time_approval_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/features/time/approvals_cubit.dart';

import 'recording_repository.dart';

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

  late _FakeTime time;
  late _FakeUsers users;
  late _FakeProjects projects;
  late ApprovalsCubit cubit;

  setUp(() {
    time = _FakeTime();
    users = _FakeUsers();
    projects = _FakeProjects();
    cubit = ApprovalsCubit(time, users, projects);
    addTearDown(cubit.close);
  });

  test('reads a page of the scope asked for', () async {
    time.answers[#approvals] = Future.value((items: [approval], total: 1));

    final page = await cubit.approvals(scope: 'inbox', page: 1, size: 25);

    expect(page.items, [approval]);
    expect(
      time.calls.single,
      invoked(#approvals, named: {#scope: 'inbox', #page: 1, #size: 25}),
    );
  });

  test('names the people and projects on screen', () async {
    users.answers[#usersByIds] = Future.value([ada]);
    projects.answers[#resolveProjects] = Future.value([alpha]);

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

  test('passes a refusal through', () async {
    time.failure = refusal;
    users.failure = refusal;
    projects.failure = refusal;

    await expectLater(
      () => cubit.approvals(scope: 'mine', page: 0, size: 25),
      throwsRefusal,
    );
    await expectLater(() => cubit.usersByIds(['u1']), throwsRefusal);
    await expectLater(() => cubit.resolveProjects(['p1']), throwsRefusal);
  });
}

class _FakeTime with RecordingRepository implements TimeRepository {
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
