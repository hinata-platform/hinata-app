import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_approval_models.dart';
import 'package:hinata/features/time/time_approval_cubit.dart';

import '../../support/recording_fake.dart';

/// The five things that can happen to a submission reach the repository as
/// asked and come back as it answered — refusals included, since the actions
/// turn those into the toast.
void main() {
  final approval = TimesheetApproval(
    id: 'a1',
    userId: 'u1',
    projectId: 'p1',
    periodStart: DateTime(2026, 9, 1),
    periodEnd: DateTime(2026, 9, 30),
    status: ApprovalStatus.submitted,
  );

  late FakeTimeRepository time;
  late TimeApprovalCubit cubit;

  setUp(() {
    time = FakeTimeRepository();
    cubit = TimeApprovalCubit(time);
    addTearDown(cubit.close);
  });

  test('hands a span in for the projects named', () async {
    time.answer(#submitPeriod, [approval]);

    final submitted = await cubit.submit(
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 30),
      projectIds: ['p1'],
    );

    expect(submitted, [approval]);
    expect(
      time.calls.single,
      invoked(
        #submitPeriod,
        named: {
          #periodStart: DateTime(2026, 9, 1),
          #periodEnd: DateTime(2026, 9, 30),
          #projectIds: ['p1'],
        },
      ),
    );
  });

  test(
    'withdraws, approves, rejects and reopens the submission named',
    () async {
      for (final member in [#withdrawApproval, #approve, #reject, #reopen]) {
        time.answer(member, approval);
      }

      expect(await cubit.withdraw('a1'), approval);
      expect(await cubit.approve('a1'), approval);
      expect(await cubit.reject('a1', note: 'hours missing'), approval);
      expect(await cubit.reopen('a1', note: 'wrong project'), approval);

      expect(time.calls, [
        invoked(#withdrawApproval, positional: ['a1']),
        invoked(#approve, positional: ['a1'], named: {#note: null}),
        invoked(#reject, positional: ['a1'], named: {#note: 'hours missing'}),
        invoked(#reopen, positional: ['a1'], named: {#note: 'wrong project'}),
      ]);
    },
  );

  test('passes a failure through', () async {
    for (final member in [
      #submitPeriod,
      #withdrawApproval,
      #approve,
      #reject,
      #reopen,
    ]) {
      time.fail(member, failure);
    }

    await expectLater(
      () => cubit.submit(
        periodStart: DateTime(2026, 9, 1),
        periodEnd: DateTime(2026, 9, 30),
      ),
      throwsFailure,
    );
    await expectLater(() => cubit.withdraw('a1'), throwsFailure);
    await expectLater(() => cubit.approve('a1'), throwsFailure);
    await expectLater(() => cubit.reject('a1', note: 'no'), throwsFailure);
    await expectLater(() => cubit.reopen('a1', note: 'no'), throwsFailure);
  });
}
