import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/issues/issue_links_cubit.dart';

import 'issue_fixtures.dart';
import '../../support/recording_fake.dart';

void main() {
  late FakeIssueRepository issues;
  late IssueLinksCubit cubit;

  setUp(() {
    issues = FakeIssueRepository();
    cubit = IssueLinksCubit(issues);
  });

  tearDown(() => cubit.close());

  final link = IssueLink(
    id: 'l1',
    type: 'BLOCKS',
    outward: true,
    verb: 'blocks',
    issue: testIssue('i2'),
  );

  test('opens the live link events of the issue', () async {
    final token = CancelToken();
    await expectForwarded(
      issues,
      #issueLinkEventStream,
      () => Future.value(const Stream<List<int>>.empty()),
      () => cubit.events('i1', cancelToken: token),
      positional: ['i1'],
      named: {#cancelToken: token},
    );
  });

  test('reads, adds and removes links', () async {
    await expectForwarded(
      issues,
      #issueLinks,
      () => Future.value([link]),
      () => cubit.links('i1'),
      positional: ['i1'],
    );
    await expectForwarded(
      issues,
      #addIssueLinks,
      () => Future.value([link]),
      () => cubit.add('i1', type: 'BLOCKS', outward: false, targetIds: ['i2']),
      positional: ['i1'],
      named: {
        #type: 'BLOCKS',
        #outward: false,
        #targetIds: ['i2'],
      },
    );
    await expectForwarded(
      issues,
      #deleteIssueLink,
      () => Future.value(<IssueLink>[]),
      () => cubit.remove('i1', 'l1'),
      positional: ['i1', 'l1'],
    );
  });

  test('searches the project for candidates', () async {
    await expectForwarded(
      issues,
      #issues,
      () => Future.value((issues: [testIssue('i2')], total: 1)),
      () => cubit.candidates('p1', query: 'HIN-2', size: 25),
      named: {#projectId: 'p1', #query: 'HIN-2', #size: 25},
    );
  });

  test('passes a refused change on unchanged', () async {
    await expectFailurePassedOn(
      issues,
      #deleteIssueLink,
      () => cubit.remove('i1', 'l1'),
    );
  });
}
