import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/issues/issue_clone_cubit.dart';

import 'recording_fakes.dart';

void main() {
  late FakeIssueRepository issues;
  late IssueCloneCubit cubit;

  setUp(() {
    issues = FakeIssueRepository();
    cubit = IssueCloneCubit(issues);
  });

  tearDown(() => cubit.close());

  Future<Issue> clone() => cubit.clone(
    'i1',
    title: 'CLONE - Title',
    assigneeIds: const ['u1'],
    includeAttachments: true,
    includeLinks: false,
    includeSprint: true,
  );

  test('asks the server for the copy as configured', () async {
    await expectForwarded(
      issues,
      #cloneIssue,
      () => Future.value(testIssue('i2')),
      clone,
      positional: ['i1'],
      named: {
        #title: 'CLONE - Title',
        #assigneeIds: ['u1'],
        #includeAttachments: true,
        #includeLinks: false,
        #includeSprint: true,
      },
    );
  });

  test('passes a refusal on unchanged', () async {
    await expectFailurePassedOn<Issue>(issues, #cloneIssue, clone);
  });
}
