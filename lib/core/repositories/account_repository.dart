import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../models/account_models.dart';
import '../models/moderation_models.dart';
import '../models/personal_access_token.dart';

/// The signed-in user's self-service account surface (`/me`): profile, avatar,
/// sessions, notification preferences, 2FA management, access overview, GDPR,
/// blocking, the house rules, reports, and personal access tokens.
class AccountRepository {
  AccountRepository(this._api);

  final ApiClient _api;

  Future<Me> meAccount() async =>
      Me.fromJson(await _api.get('/api/v1/me') as Map<String, dynamic>);

  /// Patches the profile; only the fields passed travel. [timezone] is an IANA
  /// id (`Europe/Berlin`) — the server validates it and answers 400 for one it
  /// cannot resolve.
  Future<Me> updateMyProfile({
    String? displayName,
    String? title,
    String? pronouns,
    String? locale,
    String? timezone,
    TimePreferences? timePreferences,
    TintPreferences? tint,
  }) async => Me.fromJson(
    await _api.patch(
          '/api/v1/me',
          body: {
            'displayName': ?displayName,
            'title': ?title,
            'pronouns': ?pronouns,
            'locale': ?locale,
            'timezone': ?timezone,
            // Whole when present: five lengths and a switch that one panel
            // edits together, and the server merges them onto what it holds.
            if (timePreferences != null)
              'timePreferences': timePreferences.toJson(),
            // The tint (HIN-150): three values the server merges onto what
            // it holds and writes with a targeted set.
            if (tint != null) 'tint': tint.toJson(),
          },
        )
        as Map<String, dynamic>,
  );

  /// Uploads a new profile picture; the server compresses + stores it and
  /// returns the (relative) avatar URL. [onProgress] reports 0–1 upload progress.
  Future<String> uploadAvatar(
    MultipartFile file, {
    void Function(double pct)? onProgress,
  }) async =>
      ((await _api.upload(
                '/api/v1/me/avatar',
                file,
                onSendProgress: onProgress == null
                    ? null
                    : (sent, total) => onProgress(total > 0 ? sent / total : 0),
              ))
              as Map<String, dynamic>)['avatarUrl']
          as String;

  /// Removes the current profile picture.
  Future<void> deleteAvatar() => _api.delete('/api/v1/me/avatar');

  /// Starts a double-opt-in change of the sign-in email (mails the new address).
  Future<void> requestEmailChange(String newEmail) =>
      _api.post('/api/v1/me/email-change', body: {'newEmail': newEmail});

  /// Emails a one-time password-reset link (LOCAL accounts only).
  Future<void> sendPasswordReset() => _api.post('/api/v1/me/password-reset');

  /// One page of device sessions, most recently active first.
  ///
  /// Paginated end to end: the list grows with every browser and every
  /// reinstall, and the settings screen shows only the first few until the
  /// reader asks for the rest.
  Future<({List<DeviceSession> items, int total})> sessionsPage({
    int page = 0,
    int size = 25,
  }) async {
    final data =
        await _api.get(
              '/api/v1/me/sessions',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? [])
          .map((s) => DeviceSession.fromJson(s as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  Future<void> revokeSession(String id) =>
      _api.delete('/api/v1/me/sessions/$id');

  Future<void> revokeOtherSessions() =>
      _api.post('/api/v1/me/sessions/revoke-others');

  Future<NotifPrefs> notificationPrefs() async => NotifPrefs.fromJson(
    await _api.get('/api/v1/me/notification-preferences')
        as Map<String, dynamic>,
  );

  Future<NotifPrefs> saveNotificationPrefs(NotifPrefs prefs) async =>
      NotifPrefs.fromJson(
        await _api.put(
              '/api/v1/me/notification-preferences',
              body: prefs.toJson(),
            )
            as Map<String, dynamic>,
      );

  // 2FA (TOTP) ----------------------------------------------------------------

  Future<TotpSetup> beginTotpSetup() async => TotpSetup.fromJson(
    await _api.post('/api/v1/me/2fa/totp/setup') as Map<String, dynamic>,
  );

  /// Verifies the first code, enabling 2FA. Returns the one-time recovery codes.
  Future<List<String>> verifyTotpSetup(String code) async =>
      (((await _api.post('/api/v1/me/2fa/totp/verify', body: {'code': code}))
                  as Map<String, dynamic>)['recoveryCodes']
              as List<dynamic>)
          .cast<String>();

  Future<List<String>> regenerateRecoveryCodes(String code) async =>
      (((await _api.post(
                    '/api/v1/me/2fa/recovery-codes/regenerate',
                    body: {'code': code},
                  ))
                  as Map<String, dynamic>)['recoveryCodes']
              as List<dynamic>)
          .cast<String>();

  Future<void> disableTotp(String code) =>
      _api.post('/api/v1/me/2fa/disable', body: {'code': code});

  // Access overview -----------------------------------------------------------

  Future<List<AccessTeam>> myTeams() async =>
      ((await _api.get('/api/v1/me/teams')) as List<dynamic>)
          .map((t) => AccessTeam.fromJson(t as Map<String, dynamic>))
          .toList();

  Future<List<AccessProject>> myProjects() async =>
      ((await _api.get('/api/v1/me/projects')) as List<dynamic>)
          .map((p) => AccessProject.fromJson(p as Map<String, dynamic>))
          .toList();

  // GDPR ----------------------------------------------------------------------

  /// Requests an async data report (Art. 15); the user is emailed when ready.
  Future<void> requestDataReport() => _api.post('/api/v1/me/data-report');

  /// Erases the account (Art. 17). The body must literally be `DELETE`.
  Future<void> deleteMyAccount() =>
      _api.delete('/api/v1/me', body: {'confirm': 'DELETE'});

  // Blocking (HIN-168) ----------------------------------------------------------

  /// Blocks [userId]: what they set off no longer reaches the reader, and their
  /// comments fold away. Idempotent, and nobody is told.
  Future<void> block(String userId) => _api.put('/api/v1/me/blocks/$userId');

  /// Lifts a block. Idempotent.
  Future<void> unblock(String userId) =>
      _api.delete('/api/v1/me/blocks/$userId');

  /// The people the reader blocks, newest first.
  Future<({List<BlockedPerson> items, int total})> blocksPage({
    int page = 0,
    int size = 25,
  }) async {
    final data =
        await _api.get('/api/v1/me/blocks', query: {'page': page, 'size': size})
            as Map<String, dynamic>;
    return (
      items: ((data['items'] as List<dynamic>?) ?? [])
          .map((p) => BlockedPerson.fromJson(p as Map<String, dynamic>))
          .toList(),
      total: data['total'] as int? ?? 0,
    );
  }

  /// Every id the reader blocks, at most a thousand, for folding their posts
  /// away wherever they show.
  Future<Set<String>> blockedIds() async =>
      ((await _api.get('/api/v1/me/blocks/ids')) as List<dynamic>)
          .cast<String>()
          .toSet();

  // Trusted mail senders (HIN-181) ---------------------------------------------

  /// Always loads the external images of mail from [domain] for the reader.
  /// Idempotent.
  Future<void> trustSender(String domain) => _api.put(
    '/api/v1/me/trusted-image-senders/${Uri.encodeComponent(domain)}',
  );

  /// Asks again before loading [domain]'s images. Idempotent.
  Future<void> distrustSender(String domain) => _api.delete(
    '/api/v1/me/trusted-image-senders/${Uri.encodeComponent(domain)}',
  );

  /// The senders the reader trusts, newest first.
  Future<({List<TrustedSender> items, int total})> trustedSendersPage({
    int page = 0,
    int size = 25,
  }) async {
    final data =
        await _api.get(
              '/api/v1/me/trusted-image-senders',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['items'] as List<dynamic>?) ?? [])
          .map((s) => TrustedSender.fromJson(s as Map<String, dynamic>))
          .toList(),
      total: data['total'] as int? ?? 0,
    );
  }

  // House rules and reports (HIN-175) -----------------------------------------

  /// The current house rules in the reader's language, and whether they still
  /// wait for the reader.
  Future<HouseRules> houseRules() async => HouseRules.fromJson(
    await _api.get('/api/v1/me/rules') as Map<String, dynamic>,
  );

  /// Accepts [version] of the house rules. Only the current one counts, an
  /// older one answers 409; accepting the same one again changes nothing.
  Future<void> acceptHouseRules(int version) =>
      _api.post('/api/v1/me/rules/acceptance', body: {'version': version});

  // Personal access tokens (MCP) ------------------------------------------------

  /// The caller's Personal Access Tokens (metadata only; secrets never returned).
  Future<List<PersonalAccessToken>> listPats() async =>
      ((await _api.get('/api/v1/me/pats')) as List<dynamic>)
          .map((p) => PersonalAccessToken.fromJson(p as Map<String, dynamic>))
          .toList();

  /// Mints a new PAT. [ttlDays] null → the server's default lifetime; a value
  /// ≤ 0 → never expires. Returns the one-time plaintext token plus its metadata;
  /// the plaintext is only ever available here.
  Future<CreatedPat> createPat({
    required String name,
    required List<String> scopes,
    int? ttlDays,
  }) async => CreatedPat.fromJson(
    await _api.post(
          '/api/v1/me/pats',
          body: {'name': name, 'scopes': scopes, 'ttlDays': ttlDays},
        )
        as Map<String, dynamic>,
  );

  /// Revokes a PAT by id (soft: the token is disabled but stays in the list).
  Future<void> revokePat(String id) => _api.delete('/api/v1/me/pats/$id');

  /// Permanently deletes a PAT by id, removing it from the caller's list.
  Future<void> deletePat(String id) =>
      _api.delete('/api/v1/me/pats/$id/permanent');

  /// Raw SSE byte stream of account-level events for the signed-in user (parse
  /// with [parseSse]). Currently carries the `logout` frame the server pushes
  /// when this device's session is revoked, for real-time sign-out. Cancel via
  /// [cancelToken] on logout / app teardown.
  Future<Stream<List<int>>> meEventStream({CancelToken? cancelToken}) =>
      _api.openEventStream('/api/v1/me/stream', cancelToken: cancelToken);
}
