import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/admin_user_models.dart';
import '../../../core/repositories/admin_repository.dart';

/// What the user management board asks of the server: the directory, one
/// person, an invitation and every step of an account's lifecycle.
///
/// Holds no state: the board keeps its page, filters, selection and request
/// token, and runs every action through its own toast-and-reload, as before.
/// Failures pass through as the repository's `ApiFailure`.
class UserManagementCubit extends Cubit<void> {
  UserManagementCubit(this._admin) : super(null);

  final AdminRepository _admin;

  /// One page (1-based) of the directory with its global counts.
  Future<AdminUserPage> users({
    String query = '',
    AdminRole? role,
    UserStatus? status,
    UserOrigin? origin,
    UserSortKey sort = UserSortKey.lastActive,
    bool desc = true,
    int page = 1,
    int perPage = 25,
  }) => _admin.adminUsersPage(
    query: query,
    role: role,
    status: status,
    origin: origin,
    sort: sort,
    desc: desc,
    page: page,
    perPage: perPage,
  );

  Future<AdminUser> user(String id) => _admin.adminUser(id);

  /// Invites every address in [emails]; answers with how many were sent.
  Future<int> invite({
    required List<String> emails,
    required AdminRole role,
    String? message,
  }) => _admin.adminInvite(emails: emails, role: role, message: message);

  Future<void> resendInvites(List<String> ids) =>
      _admin.adminResendInvites(ids);

  Future<void> setStatus(List<String> ids, UserStatus status) =>
      _admin.adminSetStatus(ids, status);

  Future<void> approve(List<String> ids) => _admin.adminApproveUsers(ids);

  Future<void> setRole(List<String> ids, AdminRole role) =>
      _admin.adminSetRole(ids, role);

  Future<void> setOrgAdmin(List<String> ids, bool orgAdmin) =>
      _admin.adminSetOrgRole(ids, orgAdmin);

  Future<void> sendPasswordReset(List<String> ids) =>
      _admin.adminSendPasswordReset(ids);

  Future<void> revokeSessions(List<String> ids) =>
      _admin.adminRevokeSessions(ids);

  Future<void> updateDetails(
    String id, {
    String? displayName,
    String? title,
    String? email,
  }) => _admin.adminUpdateUserDetails(
    id,
    displayName: displayName,
    title: title,
    email: email,
  );

  Future<void> delete(List<String> ids) => _admin.adminDeleteUsers(ids);
}
