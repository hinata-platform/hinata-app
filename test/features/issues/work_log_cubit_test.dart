import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/issues/work_log_cubit.dart';

import 'recording_fakes.dart';

void main() {
  late FakeIssueRepository issues;
  late WorkLogCubit cubit;

  setUp(() {
    issues = FakeIssueRepository();
    cubit = WorkLogCubit(issues);
  });

  tearDown(() => cubit.close());

  final date = DateTime(2026, 9, 1);

  test('logs new work on the issue', () async {
    await expectForwarded(
      issues,
      #addWorkItem,
      () => Future.value(testWorkItem),
      () => cubit.log('i1', minutes: 90, description: 'Notes', date: date),
      positional: ['i1'],
      named: {#minutes: 90, #description: 'Notes', #date: date},
    );
  });

  test('corrects an entry with only the fields it was given', () async {
    await expectForwarded(
      issues,
      #updateWorkItem,
      () => Future.value(testWorkItem),
      () => cubit.correct('w1', minutes: 45),
      positional: ['w1'],
      named: {#minutes: 45, #description: null, #date: null},
    );
  });

  test('passes a refusal on unchanged', () async {
    await expectFailurePassedOn<WorkItem>(
      issues,
      #addWorkItem,
      () => cubit.log('i1', minutes: 30),
    );
  });
}
