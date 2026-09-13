import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/time_privacy_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/admin/sections/admin_backfill_grants_card.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The days opened for single people (HIN-89): who, which days, why, until when,
/// and the way to close them sooner.
void main() {
  final grant = TimeBackfillGrant(
    id: 'g1',
    from: DateTime(2025, 6, 2),
    to: DateTime(2025, 6, 6),
    userId: 'u2',
    userLabel: 'Ada',
    note: 'Nachtrag nach dem Urlaub',
    grantedByLabel: 'Admin',
    grantedAt: DateTime.utc(2026, 9, 12),
    expiresAt: DateTime.utc(2026, 9, 26),
  );

  Future<_FakeTimeRepository> show(
    WidgetTester tester,
    List<TimeBackfillGrant> grants,
  ) async {
    final repository = _FakeTimeRepository(grants);
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepositoryProvider<TimeRepository>.value(
        value: repository,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AdminBackfillGrantsCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('nothing open says so', (tester) async {
    await show(tester, const []);

    expect(find.text('admin.timeTracking.grantsEmpty'), findsOneWidget);
  });

  testWidgets('an opening names the person and the reason, and closes early', (
    tester,
  ) async {
    final repository = await show(tester, [grant]);

    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Nachtrag nach dem Urlaub'), findsOneWidget);
    expect(
      find.textContaining('admin.timeTracking.grantOpenUntil'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(LucideIcons.calendarX));
    await tester.pumpAndSettle();
    expect(find.text('admin.timeTracking.grantRevokeTitle'), findsOneWidget);
    await tester.tap(find.text('common.close'));
    await tester.pumpAndSettle();

    expect(repository.revoked, ['g1']);
    expect(find.text('Ada'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });
}

class _FakeTimeRepository implements TimeRepository {
  _FakeTimeRepository(this.grants);

  final List<TimeBackfillGrant> grants;
  final List<String> revoked = [];

  @override
  Future<PageResult<TimeBackfillGrant>> backfillGrants({
    int page = 0,
    int size = 25,
  }) async => (items: grants, total: grants.length);

  @override
  Future<void> revokeBackfillGrant(String id) async => revoked.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
