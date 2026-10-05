import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/issues/issue_create_cubit.dart';

import 'issue_fixtures.dart';
import '../../support/recording_fake.dart';

void main() {
  late FakeIssueRepository issues;
  late FakeProjectRepository projects;
  late FakeSprintRepository sprints;
  late FakeUserRepository users;
  late FakeKnowledgeRepository knowledge;
  late IssueCreateCubit cubit;

  setUp(() {
    issues = FakeIssueRepository();
    projects = FakeProjectRepository();
    sprints = FakeSprintRepository();
    users = FakeUserRepository();
    knowledge = FakeKnowledgeRepository();
    cubit = IssueCreateCubit(
      issues: issues,
      projects: projects,
      sprints: sprints,
      users: users,
      knowledge: knowledge,
    );
  });

  tearDown(() => cubit.close());

  test('reads the pickers\' options', () async {
    await expectForwarded(
      projects,
      #projects,
      () => Future.value(const <Project>[]),
      cubit.projects,
    );
    await expectForwarded(
      users,
      #users,
      () => Future.value(const <DirectoryUser>[]),
      cubit.users,
    );
    await expectForwarded(
      issues,
      #issue,
      () => Future.value(testIssue('epic')),
      () => cubit.issue('epic'),
      positional: ['epic'],
    );
    await expectForwarded(
      sprints,
      #sprintsForProject,
      () => Future.value(const <Sprint>[]),
      () => cubit.sprintsForProject('p1'),
      positional: ['p1'],
    );
    await expectForwarded(
      issues,
      #issues,
      () => Future.value((issues: [testIssue('epic')], total: 1)),
      () => cubit.epics('p1', size: 100),
      named: {
        #projectId: 'p1',
        #types: ['EPIC'],
        #size: 100,
      },
    );
  });

  test('seeds the article cache', () async {
    await expectForwarded(
      knowledge,
      #init,
      () => Future<void>.value(),
      cubit.seedKnowledge,
    );
    expect(cubit.knowledge, same(knowledge));
  });

  test('looks up what the description references', () async {
    await expectForwarded(
      issues,
      #resolveIssues,
      () => Future.value([testIssue()]),
      () => cubit.resolveIssues(const ['HIN-1']),
      positional: [
        ['HIN-1'],
      ],
    );
    await expectForwarded(
      issues,
      #mentionSearch,
      () => Future.value(const <IssueRef>[]),
      () => cubit.mentionSearch(projectId: 'p1', query: 'log'),
      named: {#projectId: 'p1', #query: 'log'},
    );
    await expectForwarded(
      issues,
      #issues,
      () => Future.value((issues: [testIssue()], total: 1)),
      () => cubit.searchIssues('HIN-1', size: 20),
      named: {#query: 'HIN-1', #size: 20},
    );
  });

  test('creates the issue and edits the project around it', () async {
    final body = {'projectId': 'p1', 'title': 'New'};
    await expectForwarded(
      issues,
      #createIssue,
      () => Future.value(testIssue('new')),
      () => cubit.createIssue(body),
      positional: [body],
    );
    await expectForwarded(
      projects,
      #deleteProjectLabel,
      () => Future<void>.value(),
      () => cubit.deleteProjectLabel('p1', 'ux'),
      positional: ['p1', 'ux'],
    );
    const offset = RelativeDate(amount: 2);
    await expectForwarded(
      projects,
      #resolveOffset,
      () => Future<DateTime?>.value(DateTime(2026, 10, 7)),
      () => cubit.resolveOffset('p1', offset: offset),
      positional: ['p1'],
      named: {#offset: offset},
    );
  });

  test('passes a refused create on unchanged', () async {
    await expectFailurePassedOn(
      issues,
      #createIssue,
      () => cubit.createIssue(const {}),
    );
  });
}
