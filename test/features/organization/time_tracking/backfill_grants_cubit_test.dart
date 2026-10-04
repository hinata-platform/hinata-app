import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/time_privacy_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/organization/time_tracking/backfill_grants_cubit.dart';

/// The open backfill grants, 25 to a page, and closing one sooner.
void main() {
  TimeBackfillGrant grant(String id) => TimeBackfillGrant(
    id: id,
    from: DateTime(2026, 9, 1),
    to: DateTime(2026, 9, 2),
  );

  test('reads the first page of 25', () async {
    final time = _FakeTime([grant('g1'), grant('g2')]);
    final cubit = BackfillGrantsCubit(time);

    await cubit.load();

    expect(time.pages.single, (0, 25));
    expect(cubit.state.items.map((each) => each.id), ['g1', 'g2']);
    await cubit.close();
  });

  test('a revoke reaches the repository and leaves the list alone', () async {
    final time = _FakeTime([grant('g1')]);
    final cubit = BackfillGrantsCubit(time);
    await cubit.load();

    await cubit.revoke('g1');

    expect(time.revoked.single, 'g1');
    // The card drops the row once the call has landed, not the cubit.
    expect(cubit.state.items, hasLength(1));
    await cubit.close();
  });

  test('a refused revoke passes through', () async {
    final cubit = BackfillGrantsCubit(_FakeTime(const [], fail: true));

    await expectLater(cubit.revoke('g1'), throwsA(isA<ApiFailure>()));
    await cubit.close();
  });
}

class _FakeTime implements TimeRepository {
  _FakeTime(this.grants, {this.fail = false});

  final List<TimeBackfillGrant> grants;
  final bool fail;
  final List<(int, int)> pages = [];
  final List<String> revoked = [];

  @override
  Future<PageResult<TimeBackfillGrant>> backfillGrants({
    int page = 0,
    int size = 25,
  }) async {
    pages.add((page, size));
    return (items: grants, total: grants.length);
  }

  @override
  Future<void> revokeBackfillGrant(String id) async {
    if (fail) throw ApiFailure('error.time.grantGone', statusCode: 404);
    revoked.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
