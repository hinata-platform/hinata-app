import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/audit_models.dart';
import 'package:hinata/core/repositories/admin_repository.dart';
import 'package:hinata/core/repositories/org_settings_repository.dart';
import 'package:hinata/features/admin/sections/audit_log_cubit.dart';

/// The feed behind the audit timeline: the platform admin's or the
/// organisation's, read a filtered page at a time.
void main() {
  const answer = AuditPage(items: [], total: 0, page: 2, perPage: 30);

  test('the admin feed is read with the filters given', () async {
    final admin = _FakeAdmin(answer);
    final cubit = AuditLogCubit.admin(admin);

    final page = await cubit.entries(
      query: 'login',
      category: AuditCategory.values.first,
      severity: AuditSeverity.values.first,
      outcome: 'FAILURE',
      page: 2,
      perPage: 30,
    );

    expect(page, same(answer));
    final call = admin.calls.single;
    expect(call.query, 'login');
    expect(call.category, AuditCategory.values.first);
    expect(call.severity, AuditSeverity.values.first);
    expect(call.outcome, 'FAILURE');
    expect(call.page, 2);
    expect(call.perPage, 30);
    await cubit.close();
  });

  test('the organisation feed is its own', () async {
    final org = _FakeOrg(answer);
    final cubit = AuditLogCubit.organization(org);

    expect(await cubit.entries(page: 3), same(answer));
    expect(org.pages.single, 3);
    await cubit.close();
  });

  test('a refused read passes the failure on', () async {
    final cubit = AuditLogCubit(
      ({
        String query = '',
        AuditCategory? category,
        AuditSeverity? severity,
        String? outcome,
        int page = 1,
        int perPage = 30,
      }) async => throw ApiFailure('error.forbidden', statusCode: 403),
    );

    await expectLater(cubit.entries(), throwsA(isA<ApiFailure>()));
    await cubit.close();
  });
}

typedef _Call = ({
  String query,
  AuditCategory? category,
  AuditSeverity? severity,
  String? outcome,
  int page,
  int perPage,
});

class _FakeAdmin implements AdminRepository {
  _FakeAdmin(this.answer);

  final AuditPage answer;
  final List<_Call> calls = [];

  @override
  Future<AuditPage> auditLog({
    String query = '',
    AuditCategory? category,
    AuditSeverity? severity,
    String? action,
    String? outcome,
    String? actorId,
    int page = 1,
    int perPage = 30,
  }) async {
    calls.add((
      query: query,
      category: category,
      severity: severity,
      outcome: outcome,
      page: page,
      perPage: perPage,
    ));
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeOrg implements OrgSettingsRepository {
  _FakeOrg(this.answer);

  final AuditPage answer;
  final List<int> pages = [];

  @override
  Future<AuditPage> auditLog({
    String query = '',
    AuditCategory? category,
    AuditSeverity? severity,
    String? outcome,
    int page = 1,
    int perPage = 30,
  }) async {
    pages.add(page);
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
