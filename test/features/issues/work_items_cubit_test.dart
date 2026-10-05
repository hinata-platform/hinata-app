import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/issues/work_items_cubit.dart';

import 'issue_fixtures.dart';
import '../../support/recording_fake.dart';

void main() {
  late FakeIssueRepository issues;
  late WorkItemsPageCubit cubit;

  setUp(() {
    issues = FakeIssueRepository();
    cubit = WorkItemsPageCubit(issues, issueId: 'i1', pageSize: 20);
  });

  tearDown(() => cubit.close());

  test('pages the issue\'s entries', () async {
    issues.answer(#workItemsPage, (items: [testWorkItem], total: 1));
    await cubit.load();
    final call = issues.calls.single;
    expect(call.memberName, #workItemsPage);
    expect(call.positionalArguments, ['i1']);
    expect(call.namedArguments[#page], 0);
    expect(call.namedArguments[#size], 20);
    expect(cubit.state.items, [testWorkItem]);
  });

  test('deletes an entry', () async {
    await expectForwarded(
      issues,
      #deleteWorkItem,
      () => Future<void>.value(),
      () => cubit.delete('w1'),
      positional: ['w1'],
    );
  });

  test('passes a refused delete on unchanged', () async {
    await expectFailurePassedOn(
      issues,
      #deleteWorkItem,
      () => cubit.delete('w1'),
    );
  });
}
