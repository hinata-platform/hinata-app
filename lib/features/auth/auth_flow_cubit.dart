import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/core_models.dart' show SsoProvider;
import '../../core/repositories/auth_repository.dart';

/// The signed-out screens: the sign-in page's SSO buttons, registration and
/// its verification mail, invitations, password resets and the SSO handoff.
///
/// Holds no state of its own. Each screen keeps its form and its busy flag,
/// hands a token pair it receives to the auth bloc, and shows a failure as it
/// did; these calls answer or fail exactly as the repository does.
class AuthFlowCubit extends Cubit<void> {
  AuthFlowCubit(this._auth) : super(null);

  final AuthRepository _auth;

  Future<List<SsoProvider>> ssoProviders() => _auth.ssoProviders();

  Future<({String access, String refresh})> exchangeSso(String code) =>
      _auth.exchangeSso(code);

  Future<({String email, String displayName})> inviteInfo(String token) =>
      _auth.inviteInfo(token);

  Future<({String access, String refresh})> acceptInvite(
    String token,
    String password,
  ) => _auth.acceptInvite(token, password);

  Future<({String access, String refresh})> acceptPasswordReset(
    String token,
    String password,
  ) => _auth.acceptPasswordReset(token, password);

  Future<void> register({
    required String email,
    required String username,
    required String displayName,
    required String password,
  }) => _auth.register(
    email: email,
    username: username,
    displayName: displayName,
    password: password,
  );

  Future<void> resendVerification(String email) =>
      _auth.resendVerification(email);

  Future<({bool pendingApproval, String? access, String? refresh})> verifyEmail(
    String token,
  ) => _auth.verifyEmail(token);

  Future<void> requestPasswordReset(String email) =>
      _auth.requestPasswordReset(email);
}
