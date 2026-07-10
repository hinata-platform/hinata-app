import '../api/api_client.dart';
import '../models/core_models.dart';
import '../models/oauth_consent.dart';

/// Sign-in, registration, invitation/reset token flows, the 2FA login
/// challenge, and OAuth consent (MCP authorization).
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  /// Authenticates with a password. When the account has 2FA enabled the server
  /// returns [LoginResult.mfaRequired] with an [LoginResult.mfaToken] the caller
  /// must complete via [verifyTwoFactor]; otherwise a token pair + user.
  Future<LoginResult> login(String identifier, String password) async {
    final data =
        await _api.post(
              '/api/v1/auth/login',
              body: {'identifier': identifier, 'password': password},
            )
            as Map<String, dynamic>;
    if (data['mfaRequired'] == true) {
      return LoginResult.twoFactor(data['mfaToken'] as String);
    }
    return LoginResult.tokens(
      access: data['accessToken'] as String,
      refresh: data['refreshToken'] as String,
      user: AuthUser.fromJson(data['user'] as Map<String, dynamic>),
    );
  }

  Future<AuthUser> me() async => AuthUser.fromJson(
    await _api.get('/api/v1/auth/me') as Map<String, dynamic>,
  );

  Future<List<SsoProvider>> ssoProviders() async =>
      ((await _api.get('/api/v1/auth/sso/providers')) as List<dynamic>)
          .map((p) => SsoProvider.fromJson(p as Map<String, dynamic>))
          .toList();

  Future<void> changePassword(String current, String next) => _api.post(
    '/api/v1/auth/password',
    body: {'currentPassword': current, 'newPassword': next},
  );

  /// Validates an invitation token, returning the invitee's email + name to show
  /// on the accept screen.
  Future<({String email, String displayName})> inviteInfo(String token) async {
    final data =
        await _api.get('/api/v1/auth/invite/info', query: {'token': token})
            as Map<String, dynamic>;
    return (
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
    );
  }

  /// Accepts an invitation by setting the account password; the server signs the
  /// user in and returns a token pair.
  Future<({String access, String refresh})> acceptInvite(
    String token,
    String password,
  ) async {
    final data =
        await _api.post(
              '/api/v1/auth/invite/accept',
              body: {'token': token, 'password': password},
            )
            as Map<String, dynamic>;
    return (
      access: data['accessToken'] as String,
      refresh: data['refreshToken'] as String,
    );
  }

  /// Sets a new password from a reset link; the server signs the user in and
  /// returns a token pair.
  Future<({String access, String refresh})> acceptPasswordReset(
    String token,
    String password,
  ) async {
    final data =
        await _api.post(
              '/api/v1/auth/reset/accept',
              body: {'token': token, 'password': password},
            )
            as Map<String, dynamic>;
    return (
      access: data['accessToken'] as String,
      refresh: data['refreshToken'] as String,
    );
  }

  /// Registers a new local account. The server always answers 202 (it never
  /// reveals whether the email already exists) and emails a verification link.
  Future<void> register({
    required String email,
    required String username,
    required String displayName,
    required String password,
  }) => _api.post(
    '/api/v1/auth/register',
    body: {
      'email': email,
      'username': username,
      'displayName': displayName,
      'password': password,
    },
  );

  /// Resends the email-verification link. Always succeeds (anti-enumeration).
  Future<void> resendVerification(String email) =>
      _api.post('/api/v1/auth/resend-verification', body: {'email': email});

  /// Confirms an email from the verification link. Returns either a token pair
  /// (verified → signed in) or [pendingApproval] when an admin must approve.
  Future<({bool pendingApproval, String? access, String? refresh})> verifyEmail(
    String token,
  ) async {
    final data =
        await _api.post('/api/v1/auth/verify-email', body: {'token': token})
            as Map<String, dynamic>;
    return (
      pendingApproval: data['pendingApproval'] as bool? ?? false,
      access: data['accessToken'] as String?,
      refresh: data['refreshToken'] as String?,
    );
  }

  /// Requests a password-reset email (forgot-password). Always succeeds; the
  /// server never reveals whether the address maps to an account.
  Future<void> requestPasswordReset(String email) =>
      _api.post('/api/v1/auth/reset/request', body: {'email': email});

  /// Completes a 2FA login challenge. [mfaToken] comes from the login response;
  /// [code] is a current TOTP or a recovery code. Returns a real token pair.
  Future<({String access, String refresh, AuthUser user})> verifyTwoFactor(
    String mfaToken,
    String code,
  ) async {
    final data =
        await _api.post(
              '/api/v1/auth/2fa',
              body: {'mfaToken': mfaToken, 'code': code},
            )
            as Map<String, dynamic>;
    return (
      access: data['accessToken'] as String,
      refresh: data['refreshToken'] as String,
      user: AuthUser.fromJson(data['user'] as Map<String, dynamic>),
    );
  }

  /// Details of a pending OAuth authorization request an AI client started —
  /// looked up by the `request_id` the backend hands the web app when it
  /// 302-redirects the browser to `/oauth-consent?request_id=<id>`. Throws an
  /// [ApiFailure] with `statusCode == 404` when the request is unknown/expired.
  Future<OAuthConsentInfo> oauthConsentInfo(String requestId) async =>
      OAuthConsentInfo.fromJson(
        await _api.get('/api/v1/oauth/consent/$requestId')
            as Map<String, dynamic>,
      );

  /// Records the user's decision on a pending OAuth request and returns the
  /// `redirectUri` the browser must be sent to next (the AI client's callback,
  /// carrying `code`+`state` on approve, or `error=access_denied` on deny).
  Future<String> oauthConsentDecision(
    String requestId, {
    required bool approved,
    required List<String> grantedScopes,
  }) async =>
      ((await _api.post(
                '/api/v1/oauth/consent',
                body: {
                  'requestId': requestId,
                  'approved': approved,
                  'grantedScopes': grantedScopes,
                },
              ))
              as Map<String, dynamic>)['redirectUri']
          as String;
}
