import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/features/time/placement_picker_cubit.dart';

import 'recording_repository.dart';

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

  late _FakeProjects projects;
  late _FakeIssues issues;
  late PlacementPickerCubit cubit;

  setUp(() {
    projects = _FakeProjects();
    issues = _FakeIssues();
    cubit = PlacementPickerCubit(projects, issues);
    addTearDown(cubit.close);
  });

  test('searches projects and issues with the size asked for', () async {
    projects.answers[#searchProjects] = Future.value((
      projects: [alpha],
      total: 1,
    ));
    issues.answers[#issues] = Future.value((issues: [issue], total: 1));

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
    issues.answers[#issues] = Future.value((issues: <Issue>[], total: 0));

    await cubit.searchIssues(size: 12);

    expect(issues.calls.single, invoked(#issues, named: {#query: null}));
  });

  test('passes a refusal through', () async {
    projects.failure = refusal;
    issues.failure = refusal;

    await expectLater(
      () => cubit.searchProjects(query: '', size: 8),
      throwsRefusal,
    );
    await expectLater(() => cubit.searchIssues(size: 12), throwsRefusal);
  });
}

class _FakeProjects with RecordingRepository implements ProjectRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class _FakeIssues with RecordingRepository implements IssueRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}
