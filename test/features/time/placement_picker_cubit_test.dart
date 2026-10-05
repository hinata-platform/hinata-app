import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/time/placement_picker_cubit.dart';

import '../../support/recording_fake.dart';

/// The placement picker's two searches reach their repositories as asked and
/// come back as they answered.
void main() {
  const alpha = Project(id: 'p1', key: 'ALP', name: 'Alpha');
  const issue = Issue(
    id: 'i1',
    projectId: 'p1',
    readableId: 'ALP-1',
    title: 'Fix the gate',
    state: 'todo',
  );

  late FakeProjectRepository projects;
  late FakeIssueRepository issues;
  late PlacementPickerCubit cubit;

  setUp(() {
    projects = FakeProjectRepository();
    issues = FakeIssueRepository();
    cubit = PlacementPickerCubit(projects, issues);
    addTearDown(cubit.close);
  });

  test('searches projects and issues with the size asked for', () async {
    projects.answer(#searchProjects, (projects: [alpha], total: 1));
    issues.answer(#issues, (issues: [issue], total: 1));

    expect((await cubit.searchProjects(query: 'al', size: 8)).projects, [
      alpha,
    ]);
    expect((await cubit.searchIssues(query: 'gate', size: 12)).issues, [issue]);
    expect(
      projects.calls.single,
      invoked(#searchProjects, named: {#query: 'al', #size: 8}),
    );
    expect(
      issues.calls.single,
      invoked(#issues, named: {#query: 'gate', #size: 12}),
    );
  });

  test('an issue search without a query asks for none', () async {
    issues.answer(#issues, (issues: <Issue>[], total: 0));

    await cubit.searchIssues(size: 12);

    expect(issues.calls.single, invoked(#issues, named: {#query: null}));
  });

  test('passes a failure through', () async {
    projects.fail(#searchProjects, failure);
    issues.fail(#issues, failure);

    await expectLater(
      () => cubit.searchProjects(query: '', size: 8),
      throwsFailure,
    );
    await expectLater(() => cubit.searchIssues(size: 12), throwsFailure);
  });
}
