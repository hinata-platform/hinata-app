import '../api/api_client.dart';
import '../models/admin_user_models.dart';
import '../models/audit_models.dart';

/// Administration: platform settings, user management, and the security audit
/// log.
class AdminRepository {
  AdminRepository(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> adminSettings() async =>
      await _api.get('/api/v1/admin/settings') as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateAdminSettings(
    Map<String, dynamic> settings,
  ) async =>
      await _api.put('/api/v1/admin/settings', body: settings)
          as Map<String, dynamic>;

  // --- User management --------------------------------------------------------

  /// One page of the platform user directory + global KPI counts. Filter/sort/
  /// paginate server-side; a blank [query] / null filters return everything.
  Future<AdminUserPage> adminUsersPage({
    String query = '',
    AdminRole? role,
    UserStatus? status,
    UserOrigin? origin,
    UserSortKey sort = UserSortKey.lastActive,
    bool desc = true,
    int page = 1,
    int perPage = 25,
  }) async => AdminUserPage.fromJson(
    await _api.get(
          '/api/v1/admin/users',
          query: {
            'q': ?(query.trim().isEmpty ? null : query.trim()),
            'role': ?role?.wire,
            'status': ?status?.wire,
            'origin': ?origin?.wire,
            'sort': sort.wire,
            'dir': desc ? 'desc' : 'asc',
            'page': '$page',
            'perPage': '$perPage',
          },
        )
        as Map<String, dynamic>,
  );

  Future<int> adminInvite({
    required List<String> emails,
    required AdminRole role,
    String? message,
  }) async {
    final result = await _api.post(
      '/api/v1/admin/users/invite',
      body: {
        'emails': emails,
        'admin': role == AdminRole.admin,
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
      },
    );
    return (result is Map && result['sent'] is num)
        ? (result['sent'] as num).toInt()
        : emails.length;
  }

  Future<void> adminResendInvites(List<String> ids) =>
      _api.post('/api/v1/admin/users/resend', body: {'ids': ids});

  Future<void> adminSetStatus(List<String> ids, UserStatus status) => _api.post(
    '/api/v1/admin/users/status',
    body: {'ids': ids, 'status': status.wire},
  );

  /// Approves verified self-registrations awaiting admin sign-off.
  Future<void> adminApproveUsers(List<String> ids) =>
      _api.post('/api/v1/admin/users/approve', body: {'ids': ids});

  /// Fetches a single user for the admin board (e.g. an approval deep-link that
  /// opens straight to the user's detail drawer).
  Future<AdminUser> adminUser(String id) async => AdminUser.fromJson(
    await _api.get('/api/v1/admin/users/$id') as Map<String, dynamic>,
  );

  Future<void> adminSetRole(List<String> ids, AdminRole role) => _api.post(
    '/api/v1/admin/users/role',
    body: {'ids': ids, 'role': role.wire},
  );

  Future<void> adminSendPasswordReset(List<String> ids) =>
      _api.post('/api/v1/admin/users/password-reset', body: {'ids': ids});

  Future<void> adminRevokeSessions(List<String> ids) =>
      _api.post('/api/v1/admin/users/revoke-sessions', body: {'ids': ids});

  Future<void> adminUpdateUserDetails(
    String id, {
    String? displayName,
    String? title,
    String? email,
  }) => _api.patch(
    '/api/v1/admin/users/$id',
    body: {'displayName': ?displayName, 'title': ?title, 'email': ?email},
  );

  Future<void> adminDeleteUsers(List<String> ids) =>
      _api.post('/api/v1/admin/users/delete', body: {'ids': ids});

  // --- Audit log ---------------------------------------------------------------

  /// One filtered, paginated page of the security audit log. Blank/null filters
  /// widen the query; results are newest-first.
  Future<AuditPage> auditLog({
    String query = '',
    AuditCategory? category,
    AuditSeverity? severity,
    String? action,
    String? outcome,
    String? actorId,
    int page = 1,
    int perPage = 30,
  }) async => AuditPage.fromJson(
    await _api.get(
          '/api/v1/admin/audit',
          query: {
            'query': ?(query.trim().isEmpty ? null : query.trim()),
            'category': ?(category == null || category == AuditCategory.unknown
                ? null
                : category.wire),
            'severity': ?(severity == null || severity == AuditSeverity.unknown
                ? null
                : severity.wire),
            'action': ?action,
            'outcome': ?outcome,
            'actorId': ?actorId,
            'page': '$page',
            'perPage': '$perPage',
          },
        )
        as Map<String, dynamic>,
  );

  /// The catalogue of audit event types — used to render the per-event toggles.
  Future<List<AuditEventType>> auditEventTypes() async =>
      ((await _api.get('/api/v1/admin/audit/event-types')) as List<dynamic>)
          .map((e) => AuditEventType.fromJson(e as Map<String, dynamic>))
          .toList();
}
