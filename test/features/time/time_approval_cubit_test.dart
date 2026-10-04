import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_approval_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/time/time_approval_cubit.dart';

import 'recording_repository.dart';

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

  late _FakeTime time;
  late TimeApprovalCubit cubit;

  setUp(() {
    time = _FakeTime();
    cubit = TimeApprovalCubit(time);
    addTearDown(cubit.close);
  });

  test('hands a span in for the projects named', () async {
    time.answers[#submitPeriod] = Future.value([approval]);

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
        time.answers[member] = Future.value(approval);
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

  test('passes a refusal through', () async {
    time.failure = refusal;

    await expectLater(
      () => cubit.submit(
        periodStart: DateTime(2026, 9, 1),
        periodEnd: DateTime(2026, 9, 30),
      ),
      throwsRefusal,
    );
    await expectLater(() => cubit.withdraw('a1'), throwsRefusal);
    await expectLater(() => cubit.approve('a1'), throwsRefusal);
    await expectLater(() => cubit.reject('a1', note: 'no'), throwsRefusal);
    await expectLater(() => cubit.reopen('a1', note: 'no'), throwsRefusal);
  });
}

class _FakeTime with RecordingRepository implements TimeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}
