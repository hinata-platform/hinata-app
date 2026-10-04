import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/time_approval_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/organization/time_tracking/lock_exceptions_cubit.dart';

/// Opening and closing a span inside the lock date; both answer with every
/// exception still open.
void main() {
  final from = DateTime(2026, 9, 1);
  final to = DateTime(2026, 9, 3);

  test('an exception carries its span and reason', () async {
    final time = _FakeTime();
    final cubit = LockExceptionsCubit(time);

    final open = await cubit.add(from: from, to: to, note: 'Typo in Sept');

    expect(time.calls.single, 'add $from $to Typo in Sept');
    expect(open.single.id, 'x1');
    await cubit.close();
  });

  test('removing one answers with what is left', () async {
    final time = _FakeTime();
    final cubit = LockExceptionsCubit(time);

    expect(await cubit.remove('x1'), isEmpty);
    expect(time.calls.single, 'remove x1');
    await cubit.close();
  });

  test('a refusal passes through', () async {
    final cubit = LockExceptionsCubit(_FakeTime(fail: true));

    await expectLater(cubit.remove('x1'), throwsA(isA<ApiFailure>()));
    await cubit.close();
  });
}

class _FakeTime implements TimeRepository {
  _FakeTime({this.fail = false});

  final bool fail;
  final List<String> calls = [];

  @override
  Future<List<TimeLockException>> addLockException({
    required DateTime from,
    required DateTime to,
    required String note,
  }) async {
    calls.add('add $from $to $note');
    return [TimeLockException(id: 'x1', from: from, to: to, note: note)];
  }

  @override
  Future<List<TimeLockException>> removeLockException(String id) async {
    if (fail) throw ApiFailure('error.forbidden', statusCode: 403);
    calls.add('remove $id');
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
