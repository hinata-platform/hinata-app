import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/admin_user_models.dart';
import 'package:hinata/core/repositories/admin_repository.dart';
import 'package:hinata/features/admin/users/user_management_cubit.dart';

/// User management: the directory, one person, an invitation and every
/// lifecycle step, sent on as the board asked.
void main() {
  late _FakeAdmin admin;
  late UserManagementCubit cubit;

  setUp(() {
    admin = _FakeAdmin();
    cubit = UserManagementCubit(admin);
  });

  tearDown(() => cubit.close());

  test('a directory page carries the filters', () async {
    final page = await cubit.users(
      query: 'mira',
      role: AdminRole.admin,
      status: UserStatus.active,
      origin: UserOrigin.local,
      sort: UserSortKey.name,
      desc: false,
      page: 3,
      perPage: 10,
    );

    expect(page, same(admin.page));
    expect(admin.calls.single, 'page mira admin active local name false 3 10');
  });

  test('an invitation answers with how many went out', () async {
    final sent = await cubit.invite(
      emails: ['a@example.org', 'b@example.org'],
      role: AdminRole.user,
      message: 'Welcome',
    );

    expect(sent, 2);
    expect(
      admin.calls.single,
      'invite a@example.org,b@example.org user Welcome',
    );
  });

  test('every lifecycle step reaches the repository', () async {
    const ids = ['u1', 'u2'];

    await cubit.resendInvites(ids);
    await cubit.setStatus(ids, UserStatus.disabled);
    await cubit.approve(ids);
    await cubit.setRole(ids, AdminRole.admin);
    await cubit.setOrgAdmin(ids, true);
    await cubit.sendPasswordReset(ids);
    await cubit.revokeSessions(ids);
    await cubit.updateDetails(
      'u1',
      displayName: 'Mira',
      title: 'Kasse',
      email: 'mira@example.org',
    );
    await cubit.delete(ids);

    expect(admin.calls, [
      'resend u1,u2',
      'status u1,u2 disabled',
      'approve u1,u2',
      'role u1,u2 admin',
      'orgRole u1,u2 true',
      'reset u1,u2',
      'revoke u1,u2',
      'details u1 Mira Kasse mira@example.org',
      'delete u1,u2',
    ]);
  });

  test('one person, and a refusal passes through', () async {
    expect((await cubit.user('u1')).id, 'u1');

    admin.fail = true;
    await expectLater(cubit.user('u1'), throwsA(isA<ApiFailure>()));
  });
}

class _FakeAdmin implements AdminRepository {
  bool fail = false;
  final List<String> calls = [];
  final AdminUserPage page = const AdminUserPage(
    items: [],
    total: 0,
    page: 1,
    perPage: 10,
    counts: AdminUserCounts.empty,
  );

  @override
  Future<AdminUserPage> adminUsersPage({
    String query = '',
    AdminRole? role,
    UserStatus? status,
    UserOrigin? origin,
    UserSortKey sort = UserSortKey.lastActive,
    bool desc = true,
    int page = 1,
    int perPage = 25,
  }) async {
    calls.add(
      'page $query ${role?.name} ${status?.name} ${origin?.name} '
      '${sort.name} $desc $page $perPage',
    );
    return this.page;
  }

  @override
  Future<AdminUser> adminUser(String id) async {
    if (fail) throw ApiFailure('error.notFound', statusCode: 404);
    return AdminUser(
      id: id,
      name: 'Mira Kaya',
      username: 'mira',
      email: 'mira@example.org',
      title: '',
      role: AdminRole.user,
      orgAdmin: false,
      origin: UserOrigin.local,
      status: UserStatus.active,
      twoFA: false,
      sso: false,
      sessions: 0,
    );
  }

  @override
  Future<int> adminInvite({
    required List<String> emails,
    required AdminRole role,
    String? message,
  }) async {
    calls.add('invite ${emails.join(',')} ${role.name} $message');
    return emails.length;
  }

  @override
  Future<void> adminResendInvites(List<String> ids) async =>
      calls.add('resend ${ids.join(',')}');

  @override
  Future<void> adminSetStatus(List<String> ids, UserStatus status) async =>
      calls.add('status ${ids.join(',')} ${status.name}');

  @override
  Future<void> adminApproveUsers(List<String> ids) async =>
      calls.add('approve ${ids.join(',')}');

  @override
  Future<void> adminSetRole(List<String> ids, AdminRole role) async =>
      calls.add('role ${ids.join(',')} ${role.name}');

  @override
  Future<void> adminSetOrgRole(List<String> ids, bool orgAdmin) async =>
      calls.add('orgRole ${ids.join(',')} $orgAdmin');

  @override
  Future<void> adminSendPasswordReset(List<String> ids) async =>
      calls.add('reset ${ids.join(',')}');

  @override
  Future<void> adminRevokeSessions(List<String> ids) async =>
      calls.add('revoke ${ids.join(',')}');

  @override
  Future<void> adminUpdateUserDetails(
    String id, {
    String? displayName,
    String? title,
    String? email,
  }) async => calls.add('details $id $displayName $title $email');

  @override
  Future<void> adminDeleteUsers(List<String> ids) async =>
      calls.add('delete ${ids.join(',')}');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
