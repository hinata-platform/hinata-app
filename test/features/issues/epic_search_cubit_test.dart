import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/issues/epic_search_cubit.dart';

import 'issue_fixtures.dart';
import '../../support/recording_fake.dart';

void main() {
  late FakeIssueRepository issues;
  late EpicSearchCubit cubit;

  setUp(() {
    issues = FakeIssueRepository();
    cubit = EpicSearchCubit(issues, projectId: 'p1');
  });

  tearDown(() => cubit.close());

  test('searches the project for the type and query asked', () async {
    await expectForwarded(
      issues,
      #issues,
      () => Future.value((issues: [testIssue()], total: 1)),
      () => cubit.search(type: 'EPIC', query: 'login', page: 2, size: 25),
      named: {
        #projectId: 'p1',
        #type: 'EPIC',
        #query: 'login',
        #page: 2,
        #size: 25,
      },
    );
  });

  test('passes a failed search on', () async {
    await expectFailurePassedOn(
      issues,
      #issues,
      () => cubit.search(page: 0, size: 25),
    );
  });
}
