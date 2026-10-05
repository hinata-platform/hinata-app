import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/issues/watched_issues_cubit.dart';

import 'issue_fixtures.dart';
import '../../support/recording_fake.dart';

void main() {
  late FakeIssueRepository issues;
  late FakeUserRepository users;
  late FakeProjectRepository projects;
  late WatchedIssuesCubit cubit;

  setUp(() {
    issues = FakeIssueRepository();
    users = FakeUserRepository();
    projects = FakeProjectRepository();
    cubit = WatchedIssuesCubit(
      issues: issues,
      users: users,
      projects: projects,
    );
  });

  tearDown(() => cubit.close());

  test('pages the watched issues, 25 at a time', () async {
    final issue = testIssue();
    issues.answer(#watchedIssues, (items: [issue], total: 1));
    await cubit.load();
    final call = issues.calls.single;
    expect(call.memberName, #watchedIssues);
    expect(call.namedArguments[#page], 0);
    expect(call.namedArguments[#size], 25);
    expect(cubit.state.items, [issue]);
  });

  test('reads the directory and the projects for the rows', () async {
    const user = DirectoryUser(id: 'u1', username: 'ada', displayName: 'Ada');
    const project = Project(id: 'p1', key: 'HIN', name: 'Hinata');
    users.answer(#users, const [user]);
    projects.answer(#projects, const [project]);
    final reference = await cubit.reference();
    expect(reference.users, [user]);
    expect(reference.projects, [project]);
  });

  test('passes a failed directory read on', () async {
    projects.answer(#projects, const <Project>[]);
    await expectFailurePassedOn(users, #users, () => cubit.reference());
  });
}
