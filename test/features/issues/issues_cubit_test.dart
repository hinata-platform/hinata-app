import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/issues/issues_cubit.dart';

import 'recording_fakes.dart';

void main() {
  late FakeIssueRepository issues;
  late FakeProjectRepository projects;
  late FakeUserRepository users;

  IssueListQuery query = (
    projectId: 'p1',
    archived: false,
    states: ['OPEN'],
    priorities: null,
    types: ['BUG'],
    assigneeIds: ['u1'],
    sort: 'updated',
  );

  setUp(() {
    issues = FakeIssueRepository();
    projects = FakeProjectRepository();
    users = FakeUserRepository();
  });

  group('IssuesListCubit', () {
    late IssuesListCubit cubit;

    setUp(() {
      cubit = IssuesListCubit(
        issues: issues,
        projects: projects,
        users: users,
        query: () => query,
        pageSize: 100,
      );
    });

    tearDown(() => cubit.close());

    test('pages with the query the head shows at fetch time', () async {
      final issue = testIssue();
      issues.answers[#issues] = (_) =>
          Future.value((issues: [issue], total: 1));
      query = (
        projectId: 'p1',
        archived: true,
        states: ['DONE'],
        priorities: ['HIGH'],
        types: null,
        assigneeIds: null,
        sort: 'created',
      );
      await cubit.load();
      final call = issues.calls.single;
      expect(call.namedArguments[#projectId], 'p1');
      expect(call.namedArguments[#archived], true);
      expect(call.namedArguments[#states], ['DONE']);
      expect(call.namedArguments[#priorities], ['HIGH']);
      expect(call.namedArguments[#types], null);
      expect(call.namedArguments[#assigneeIds], null);
      expect(call.namedArguments[#sort], 'created');
      expect(call.namedArguments[#page], 0);
      expect(call.namedArguments[#size], 100);
      expect(cubit.state.items, [issue]);
    });

    test('reads the directory and the projects for the rows', () async {
      const user = DirectoryUser(id: 'u1', username: 'ada', displayName: 'Ada');
      const project = Project(id: 'p1', key: 'HIN', name: 'Hinata');
      users.answers[#users] = (_) => Future.value(const [user]);
      projects.answers[#projects] = (_) => Future.value(const [project]);
      final reference = await cubit.reference();
      expect(reference.users, [user]);
      expect(reference.projects, [project]);
    });

    test('sets a deadline on the selection', () async {
      final day = DateTime(2026, 10, 1);
      await expectForwarded(
        issues,
        #bulkSetDeadline,
        () => Future.value([testIssue()]),
        () => cubit.bulkSetDeadline(const ['i1', 'i2'], dueDate: day),
        positional: [
          ['i1', 'i2'],
        ],
        named: {#dueDate: day, #dueOffset: null, #clearDueDate: false},
      );
    });

    test('resolves a rule against the project', () async {
      const offset = RelativeDate(amount: -3);
      final day = DateTime(2026, 9, 28);
      await expectForwarded(
        projects,
        #resolveOffset,
        () => Future<DateTime?>.value(day),
        () => cubit.resolveOffset('p1', offset: offset),
        positional: ['p1'],
        named: {#offset: offset},
      );
    });

    test('passes a refused deadline on unchanged', () async {
      await expectFailurePassedOn<List<Issue>>(
        issues,
        #bulkSetDeadline,
        () => cubit.bulkSetDeadline(const ['i1'], clearDueDate: true),
      );
    });
  });

  group('IssuesExportCubit', () {
    late FakeMetaRepository meta;
    late IssuesExportCubit cubit;

    setUp(() {
      meta = FakeMetaRepository();
      cubit = IssuesExportCubit(issues: issues, meta: meta);
    });

    tearDown(() => cubit.close());

    test('drains every issue the query matches', () async {
      await expectForwarded(
        issues,
        #allIssues,
        () => Future.value([testIssue()]),
        () => cubit.all(query),
        named: {
          #projectId: query.projectId,
          #archived: query.archived,
          #states: query.states,
          #priorities: query.priorities,
          #types: query.types,
          #assigneeIds: query.assigneeIds,
          #sort: query.sort,
        },
      );
    });

    test('reads the server meta and the organisation logo', () async {
      await expectForwarded(
        meta,
        #organizationLogo,
        () => Future.value((bytes: const [1], isSvg: false)),
        () => cubit.organizationLogo(),
      );
    });

    test('passes a failed export read on unchanged', () async {
      await expectFailurePassedOn<List<Issue>>(
        issues,
        #allIssues,
        () => cubit.all(query),
      );
    });
  });
}
