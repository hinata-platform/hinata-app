import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/time_approval_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/organization/time_tracking/approval_period_preview_cubit.dart';

/// The periods the saved rhythm cuts, read over the window the preview asks.
void main() {
  final from = DateTime(2026, 10);
  final to = DateTime(2027, 7);

  test('asks for the window given and answers with the periods', () async {
    final time = _FakeTime();
    final cubit = ApprovalPeriodPreviewCubit(time);

    final periods = await cubit.periods(from: from, to: to);

    expect(time.windows.single, (from, to));
    expect(periods.single.type, 'MONTHLY');
    await cubit.close();
  });

  test('a refusal passes through', () async {
    final cubit = ApprovalPeriodPreviewCubit(_FakeTime(fail: true));

    await expectLater(
      cubit.periods(from: from, to: to),
      throwsA(isA<ApiFailure>()),
    );
    await cubit.close();
  });
}

class _FakeTime implements TimeRepository {
  _FakeTime({this.fail = false});

  final bool fail;
  final List<(DateTime, DateTime)> windows = [];

  @override
  Future<List<ApprovalPeriod>> approvalPeriods({
    required DateTime from,
    required DateTime to,
    String? projectId,
  }) async {
    windows.add((from, to));
    if (fail) throw ApiFailure('error.time.approvalsOff', statusCode: 404);
    return [ApprovalPeriod(start: from, end: from, type: 'MONTHLY')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
