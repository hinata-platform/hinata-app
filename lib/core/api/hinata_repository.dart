import 'package:dio/dio.dart';

import '../models/account_models.dart';
import '../models/admin_user_models.dart';
import '../models/audit_models.dart';
import '../models/content_models.dart';
import '../models/core_models.dart';
import '../models/deletion_models.dart';
import '../models/git_connection.dart';
import '../models/git_dev_info.dart';
import '../models/search_api.dart';
import '../models/team_models.dart';
import '../models/work_models.dart';
import 'api_client.dart';

/// Single REST gateway for the Hinata server API (v1).
class HinataRepository {
  HinataRepository(this._api);

  final ApiClient _api;

  /// The configured backend base URL (e.g. `https://api.track.asta.hn`). Used
  /// to derive shareable web links to in-app resources.
  String get apiBaseUrl => _api.baseUrl;

  // --- Meta & setup ---------------------------------------------------------

  Future<ServerMeta> meta() async => ServerMeta.fromJson(
    await _api.get('/api/v1/meta') as Map<String, dynamic>,
  );

  /// Reachability test for a *candidate* server [url] the app is not yet bound
  /// to — powers the "add server" connection test and the live status dots in
  /// the server manager. Returns null when the server is unreachable.
  Future<ServerProbe?> probeServer(String url) => _api.probe(url);

  Future<void> completeSetup({
    required String organizationName,
    required String adminEmail,
    required String adminUsername,
    required String adminDisplayName,
    required String adminPassword,
  }) => _api.post(
    '/api/v1/setup',
    body: {
      'organizationName': organizationName,
      'adminEmail': adminEmail,
      'adminUsername': adminUsername,
      'adminDisplayName': adminDisplayName,
      'adminPassword': adminPassword,
    },
  );

  // --- Auth -----------------------------------------------------------------

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

  // --- Account (/me self-service) -------------------------------------------

  Future<Me> meAccount() async =>
      Me.fromJson(await _api.get('/api/v1/me') as Map<String, dynamic>);

  Future<Me> updateMyProfile({
    String? displayName,
    String? title,
    String? locale,
  }) async => Me.fromJson(
    await _api.patch(
          '/api/v1/me',
          body: {
            'displayName': ?displayName,
            'title': ?title,
            'locale': ?locale,
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

  Future<List<DeviceSession>> sessions() async =>
      ((await _api.get('/api/v1/me/sessions')) as List<dynamic>)
          .map((s) => DeviceSession.fromJson(s as Map<String, dynamic>))
          .toList();

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

  // --- Users ----------------------------------------------------------------

  Future<List<DirectoryUser>> users() async =>
      ((await _api.get('/api/v1/users')) as List<dynamic>)
          .map((u) => DirectoryUser.fromJson(u as Map<String, dynamic>))
          .toList();

  /// Server-side type-ahead over the directory, for assignee/member pickers in
  /// large orgs where loading every user is wasteful. Returns one page plus the
  /// backend total. An empty [query] returns the first page of all active users.
  Future<({List<DirectoryUser> items, int total})> searchUsers(
    String query, {
    int page = 0,
    int size = 25,
  }) async {
    final data =
        await _api.get(
              '/api/v1/users/search',
              query: {'q': query, 'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? [])
          .map((u) => DirectoryUser.fromJson(u as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  // --- Projects -------------------------------------------------------------

  Future<List<Project>> projects({bool archived = false}) async =>
      ((await _api.get(
                '/api/v1/projects',
                query: archived ? {'archived': 'true'} : null,
              ))
              as List<dynamic>)
          .map((p) => Project.fromJson(p as Map<String, dynamic>))
          .toList();

  Future<Project> project(String id) async => Project.fromJson(
    await _api.get('/api/v1/projects/$id') as Map<String, dynamic>,
  );

  /// Issue count per workflow-state name — used by the settings UI to warn
  /// before deleting a state that still has issues assigned.
  Future<Map<String, int>> projectStateUsage(String id) async {
    final json =
        await _api.get('/api/v1/projects/$id/state-usage')
            as Map<String, dynamic>;
    return json.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  Future<Project> createProject({
    required String key,
    required String name,
    String? description,
    String? color,
    String? leadId,
  }) async => Project.fromJson(
    await _api.post(
          '/api/v1/projects',
          body: {
            'key': key,
            'name': name,
            'description': ?description,
            'color': ?color,
            'leadId': ?leadId,
          },
        )
        as Map<String, dynamic>,
  );

  /// Atomically commits the full edited project from the settings surface. Pass
  /// only the fields that changed; the server re-validates every invariant
  /// (>=1 lead, >=2 states, >=1 resolved) and cascades workflow/label renames.
  Future<Project> updateProject(String id, Map<String, dynamic> patch) async =>
      Project.fromJson(
        await _api.patch('/api/v1/projects/$id', body: patch)
            as Map<String, dynamic>,
      );

  /// Permanently removes a label from the project and every issue using it.
  Future<void> deleteProjectLabel(
    String projectId,
    String label,
  ) => _api.delete(
    '/api/v1/projects/$projectId/labels?label=${Uri.encodeQueryComponent(label)}',
  );

  // --- Issues ---------------------------------------------------------------

  Future<({List<Issue> issues, int total})> issues({
    String? projectId,
    String? state,
    String? assigneeId,
    String? sprintId,
    String? query,
    bool noSprint = false,
    int page = 0,
    int size = 50,
  }) async {
    final data =
        await _api.get(
              '/api/v1/issues',
              query: {
                'projectId': ?projectId,
                'state': ?state,
                'assigneeId': ?assigneeId,
                'sprintId': ?sprintId,
                if (noSprint) 'noSprint': true,
                if (query != null && query.isNotEmpty) 'query': query,
                'page': page,
                'size': size,
              },
            )
            as Map<String, dynamic>;
    return (
      issues: ((data['content'] as List<dynamic>?) ?? [])
          .map((i) => Issue.fromJson(i as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  /// Fetches **every** matching issue by paging through the server-clamped
  /// result set (the search endpoint caps `size` at 100), so callers that need
  /// the complete collection — exports, board swimlane indexes, smart-link
  /// `@`-menus — never silently miss issues beyond the first page.
  ///
  /// Pages are de-duplicated by id: the backend orders by `updatedAt`, so a row
  /// can shift across a page boundary while we page. Stops at the last partial
  /// page or once the accumulated count reaches the backend total.
  Future<List<Issue>> allIssues({
    String? projectId,
    String? state,
    String? assigneeId,
    String? sprintId,
    String? query,
    bool noSprint = false,
  }) async {
    const size = 100;
    final out = <Issue>[];
    final seen = <String>{};
    var page = 0;
    while (true) {
      final result = await issues(
        projectId: projectId,
        state: state,
        assigneeId: assigneeId,
        sprintId: sprintId,
        query: query,
        noSprint: noSprint,
        page: page,
        size: size,
      );
      for (final issue in result.issues) {
        if (seen.add(issue.id)) out.add(issue);
      }
      if (result.issues.length < size || out.length >= result.total) break;
      page++;
    }
    return out;
  }

  Future<Issue> issue(String id) async => Issue.fromJson(
    await _api.get('/api/v1/issues/$id') as Map<String, dynamic>,
  );

  /// Breadcrumb ancestors + direct children for the issue hierarchy view.
  Future<IssueHierarchy> issueHierarchy(String id) async =>
      IssueHierarchy.fromJson(
        await _api.get('/api/v1/issues/$id/hierarchy') as Map<String, dynamic>,
      );

  Future<Issue> createIssue(Map<String, dynamic> body) async => Issue.fromJson(
    await _api.post('/api/v1/issues', body: body) as Map<String, dynamic>,
  );

  Future<Issue> updateIssue(String id, Map<String, dynamic> patch) async =>
      Issue.fromJson(
        await _api.patch('/api/v1/issues/$id', body: patch)
            as Map<String, dynamic>,
      );

  Future<void> deleteIssue(String id) => _api.delete('/api/v1/issues/$id');

  // --- Issue links (Jira-style relationships) -------------------------------

  /// All links touching the issue, oriented for it (perspective-correct verbs).
  Future<List<IssueLink>> issueLinks(String issueId) async =>
      ((await _api.get('/api/v1/issues/$issueId/links')) as List<dynamic>)
          .map((l) => IssueLink.fromJson(l as Map<String, dynamic>))
          .toList();

  /// Links [issueId] to each of [targetIds] with the given [type]/direction;
  /// returns the refreshed, oriented link list.
  Future<List<IssueLink>> addIssueLinks(
    String issueId, {
    required String type,
    required bool outward,
    required List<String> targetIds,
  }) async =>
      ((await _api.post(
                '/api/v1/issues/$issueId/links',
                body: {
                  'type': type,
                  'outward': outward,
                  'targetIds': targetIds,
                },
              ))
              as List<dynamic>)
          .map((l) => IssueLink.fromJson(l as Map<String, dynamic>))
          .toList();

  /// Removes one link; returns the refreshed, oriented link list.
  Future<List<IssueLink>> deleteIssueLink(
    String issueId,
    String linkId,
  ) async =>
      ((await _api.delete('/api/v1/issues/$issueId/links/$linkId'))
              as List<dynamic>)
          .map((l) => IssueLink.fromJson(l as Map<String, dynamic>))
          .toList();

  /// Raw SSE byte stream of link changes for an issue (parse with [parseSse]).
  /// Carries a payload-free `changed` ping; the client re-fetches its links.
  Future<Stream<List<int>>> issueLinkEventStream(
    String issueId, {
    CancelToken? cancelToken,
  }) => _api.openEventStream(
    '/api/v1/issues/$issueId/links/stream',
    cancelToken: cancelToken,
  );

  /// One newest-first page of an issue's change history, plus the backend total.
  Future<({List<IssueActivity> items, int total})> issueActivity(
    String issueId, {
    int page = 0,
    int size = 30,
  }) async {
    final data =
        await _api.get(
              '/api/v1/issues/$issueId/activity',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? [])
          .map((a) => IssueActivity.fromJson(a as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  /// One newest-first page of an issue's comment thread, plus the backend total.
  /// Callers that show comments chat-style (oldest-first) reverse each page.
  Future<({List<IssueComment> items, int total})> comments(
    String issueId, {
    int page = 0,
    int size = 30,
  }) async {
    final data =
        await _api.get(
              '/api/v1/issues/$issueId/comments',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? [])
          .map((c) => IssueComment.fromJson(c as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  Future<IssueComment> addComment(String issueId, String text) async =>
      IssueComment.fromJson(
        await _api.post(
              '/api/v1/issues/$issueId/comments',
              body: {'text': text},
            )
            as Map<String, dynamic>,
      );

  /// Edits the text of one of the caller's own comments. Server returns the
  /// updated comment (with a fresh `updatedAt`).
  Future<IssueComment> editComment(
    String issueId,
    String commentId,
    String text,
  ) async => IssueComment.fromJson(
    await _api.patch(
          '/api/v1/issues/$issueId/comments/$commentId',
          body: {'text': text},
        )
        as Map<String, dynamic>,
  );

  /// Deletes one of the caller's own comments (admins may delete any).
  Future<void> deleteComment(String issueId, String commentId) =>
      _api.delete('/api/v1/issues/$issueId/comments/$commentId');

  /// Uploads one file to an issue, reporting fractional progress (0–1) as the
  /// bytes are sent so the tile's ring can fill. Returns the updated issue.
  Future<Issue> uploadAttachment(
    String issueId,
    MultipartFile file, {
    void Function(double pct)? onProgress,
    CancelToken? cancelToken,
  }) async => Issue.fromJson(
    await _api.upload(
          '/api/v1/issues/$issueId/attachments',
          file,
          cancelToken: cancelToken,
          onSendProgress: onProgress == null
              ? null
              : (sent, total) => onProgress(total > 0 ? sent / total : 0),
        )
        as Map<String, dynamic>,
  );

  /// Uploads an inline Markdown image (issue description/comment or KB article)
  /// and returns its app-relative URL — e.g. `/api/v1/media/<uuid>` — ready to
  /// embed as `![alt](url)`. Not bound to any entity; readable by any signed-in
  /// user, served back through the authenticated media proxy.
  Future<String> uploadMedia(
    MultipartFile file, {
    CancelToken? cancelToken,
  }) async =>
      ((await _api.upload('/api/v1/media', file, cancelToken: cancelToken))
              as Map<String, dynamic>)['url']
          as String;

  /// Short-lived presigned download URL for an attachment.
  Future<String> attachmentDownloadUrl(
    String issueId,
    String attachmentId,
  ) async =>
      ((await _api.get(
                '/api/v1/issues/$issueId/attachments/$attachmentId/download-url',
              ))
              as Map<String, dynamic>)['url']
          as String;

  Future<void> deleteAttachment(String issueId, String attachmentId) =>
      _api.delete('/api/v1/issues/$issueId/attachments/$attachmentId');

  /// Raw SSE byte stream of account-level events for the signed-in user (parse
  /// with [parseSse]). Currently carries the `logout` frame the server pushes
  /// when this device's session is revoked, for real-time sign-out. Cancel via
  /// [cancelToken] on logout / app teardown.
  Future<Stream<List<int>>> meEventStream({CancelToken? cancelToken}) =>
      _api.openEventStream('/api/v1/me/stream', cancelToken: cancelToken);

  /// Raw SSE byte stream of attachment changes for an issue (parse with
  /// [parseSse]). Cancel via [cancelToken] when the view is disposed.
  Future<Stream<List<int>>> attachmentEventStream(
    String issueId, {
    CancelToken? cancelToken,
  }) => _api.openEventStream(
    '/api/v1/issues/$issueId/attachments/stream',
    cancelToken: cancelToken,
  );

  // --- Boards ---------------------------------------------------------------

  Future<List<AgileBoard>> boards({String? projectId}) async =>
      ((await _api.get('/api/v1/boards', query: {'projectId': ?projectId}))
              as List<dynamic>)
          .map((b) => AgileBoard.fromJson(b as Map<String, dynamic>))
          .toList();

  Future<AgileBoard> createBoard(
    String name,
    List<String> projectIds, {
    BoardType type = BoardType.kanban,
  }) async => AgileBoard.fromJson(
    await _api.post(
          '/api/v1/boards',
          body: {
            'name': name,
            'projectIds': projectIds,
            'type': type == BoardType.scrum ? 'SCRUM' : 'KANBAN',
          },
        )
        as Map<String, dynamic>,
  );

  /// Renames a board (management action — server enforces owner/lead/admin).
  Future<AgileBoard> renameBoard(String boardId, String name) async =>
      AgileBoard.fromJson(
        await _api.patch('/api/v1/boards/$boardId', body: {'name': name})
            as Map<String, dynamic>,
      );

  Future<BoardView> boardView(String boardId, {String? sprintId}) async =>
      BoardView.fromJson(
        await _api.get(
              '/api/v1/boards/$boardId',
              query: {'sprintId': ?sprintId},
            )
            as Map<String, dynamic>,
      );

  // --- Sprints --------------------------------------------------------------

  Future<List<Sprint>> sprints(
    String boardId, {
    bool includeArchived = false,
  }) async =>
      ((await _api.get(
                '/api/v1/sprints',
                query: {'boardId': boardId, 'archived': includeArchived},
              ))
              as List<dynamic>)
          .map((s) => Sprint.fromJson(s as Map<String, dynamic>))
          .toList();

  Future<Sprint> createSprint({
    required String boardId,
    required String name,
    String? goal,
    DateTime? startDate,
    DateTime? endDate,
    int? capacityPoints,
  }) async => Sprint.fromJson(
    await _api.post(
          '/api/v1/sprints',
          body: {
            'boardId': boardId,
            'name': name,
            'goal': ?goal,
            if (startDate != null)
              'startDate': startDate.toIso8601String().substring(0, 10),
            if (endDate != null)
              'endDate': endDate.toIso8601String().substring(0, 10),
            'capacityPoints': ?capacityPoints,
          },
        )
        as Map<String, dynamic>,
  );

  /// All assignable (non-archived) sprints across every board of [projectId].
  /// A project can have several boards (e.g. a Kanban and a Scrum board); only
  /// the Scrum boards contribute sprints. Used by the issue form/detail pickers.
  Future<List<Sprint>> sprintsForProject(String projectId) async {
    final boardList = await boards(projectId: projectId);
    if (boardList.isEmpty) return const [];
    final lists = await Future.wait(boardList.map((b) => sprints(b.id)));
    final seen = <String>{};
    final out = <Sprint>[];
    for (final list in lists) {
      for (final s in list) {
        if (seen.add(s.id)) out.add(s);
      }
    }
    return out;
  }

  Future<Sprint> updateSprint(String id, Map<String, dynamic> patch) async =>
      Sprint.fromJson(
        await _api.patch('/api/v1/sprints/$id', body: patch)
            as Map<String, dynamic>,
      );

  /// Locks scope and sets the board's activeSprintId server-side.
  Future<Sprint> startSprint(
    String id, {
    String? goal,
    DateTime? endDate,
  }) async => Sprint.fromJson(
    await _api.post(
          '/api/v1/sprints/$id/start',
          body: {
            'goal': ?goal,
            if (endDate != null)
              'endDate': endDate.toIso8601String().substring(0, 10),
          },
        )
        as Map<String, dynamic>,
  );

  /// Archives the sprint; re-homes every unfinished issue to [moveOpenTo]
  /// (`backlog` → no sprint, or a sibling sprint id).
  Future<void> completeSprint(String id, {required String moveOpenTo}) => _api
      .post('/api/v1/sprints/$id/complete', body: {'moveOpenTo': moveOpenTo});

  /// Server-computed insights (summary, burndown, velocity, scope, breakdown).
  Future<SprintReport> sprintReport(String id) async => SprintReport.fromJson(
    await _api.get('/api/v1/sprints/$id/report') as Map<String, dynamic>,
  );

  // --- Time tracking --------------------------------------------------------

  Future<List<WorkItem>> workItems(String issueId) async =>
      ((await _api.get('/api/v1/issues/$issueId/work-items')) as List<dynamic>)
          .map((w) => WorkItem.fromJson(w as Map<String, dynamic>))
          .toList();

  Future<WorkItem> addWorkItem(
    String issueId, {
    required int minutes,
    String? activityType,
    String? description,
    DateTime? date,
  }) async {
    return WorkItem.fromJson(
      await _api.post(
            '/api/v1/issues/$issueId/work-items',
            body: {
              'durationMinutes': minutes,
              'activityType': ?activityType,
              'description': ?description,
              if (date != null) 'date': date.toIso8601String().substring(0, 10),
            },
          )
          as Map<String, dynamic>,
    );
  }

  Future<List<TimesheetRow>> timesheet(
    DateTime from,
    DateTime to, {
    String? userId,
    String? projectId,
  }) async {
    final data =
        await _api.get(
              '/api/v1/timesheet',
              query: {
                'from': from.toIso8601String().substring(0, 10),
                'to': to.toIso8601String().substring(0, 10),
                'userId': ?userId,
                'projectId': ?projectId,
              },
            )
            as List<dynamic>;
    return data
        .map((r) => TimesheetRow.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // --- Gantt ----------------------------------------------------------------

  Future<List<GanttTask>> gantt(String projectId) async =>
      ((await _api.get('/api/v1/projects/$projectId/gantt')) as List<dynamic>)
          .map((t) => GanttTask.fromJson(t as Map<String, dynamic>))
          .toList();

  // --- Global search --------------------------------------------------------

  /// Unified search across issues, projects, people, boards and knowledge.
  /// [scope] is `all` (default) or a single category (`issues`, `projects`,
  /// `people`, `boards`, `docs`). A blank [query] returns just category counts.
  Future<SearchApiResponse> search({String query = '', String? scope}) async =>
      SearchApiResponse.fromJson(
        await _api.get(
              '/api/v1/search',
              query: {
                'q': ?(query.trim().isEmpty ? null : query.trim()),
                'scope': ?scope,
              },
            )
            as Map<String, dynamic>,
      );

  // --- Knowledge base -------------------------------------------------------

  /// Lists articles. [all] fetches every article (the whole knowledge base
  /// across projects + org-wide); otherwise scoped by [projectId] (or org-wide
  /// when null).
  Future<List<Article>> articles({String? projectId, bool all = false}) async =>
      ((await _api.get(
                '/api/v1/articles',
                query: {'projectId': ?projectId, if (all) 'all': true},
              ))
              as List<dynamic>)
          .map((a) => Article.fromJson(a as Map<String, dynamic>))
          .toList();

  Future<Article> article(String id) async => Article.fromJson(
    await _api.get('/api/v1/articles/$id') as Map<String, dynamic>,
  );

  Future<Article> saveArticle({
    String? id,
    required String title,
    String? content,
    String? projectId,
    String? teamId,
    String? parentId,
    String? space,
    String? icon,
    List<String>? tags,
  }) async {
    final body = {
      'title': title,
      'content': ?content,
      'projectId': ?projectId,
      'teamId': ?teamId,
      'parentId': ?parentId,
      'space': ?space,
      'icon': ?icon,
      'tags': ?tags,
    };
    final data = id == null
        ? await _api.post('/api/v1/articles', body: body)
        : await _api.patch('/api/v1/articles/$id', body: body);
    return Article.fromJson(data as Map<String, dynamic>);
  }

  /// Moves an article under a new parent (or to the space root when [parentId]
  /// is null — sent explicitly, unlike [saveArticle] which omits nulls) and/or
  /// into a different [space]. Content/tags/icon are left untouched.
  Future<Article> moveArticle(
    String id, {
    required String title,
    String? parentId,
    String? space,
  }) async {
    final data = await _api.patch(
      '/api/v1/articles/$id',
      body: {'title': title, 'parentId': parentId, 'space': ?space},
    );
    return Article.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteArticle(String id) async =>
      _api.delete('/api/v1/articles/$id');

  /// Lists every knowledge-base space (organisation-wide, sorted).
  Future<List<Space>> spaces() async =>
      ((await _api.get('/api/v1/spaces')) as List<dynamic>)
          .map((s) => Space.fromJson(s as Map<String, dynamic>))
          .toList();

  Future<Space> createSpace({
    required String name,
    String? icon,
    int? hue,
    String? description,
  }) async {
    final data = await _api.post(
      '/api/v1/spaces',
      body: {
        'name': name,
        'icon': ?icon,
        'hue': ?hue,
        'description': ?description,
      },
    );
    return Space.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteSpace(String id) async =>
      _api.delete('/api/v1/spaces/$id');

  // --- Dashboard, reports, notifications ------------------------------------

  Future<DashboardData> dashboard() async => DashboardData.fromJson(
    await _api.get('/api/v1/dashboard') as Map<String, dynamic>,
  );

  Future<Map<String, int>> report(
    String name,
    Map<String, dynamic> query,
  ) async =>
      ((await _api.get('/api/v1/reports/$name', query: query))
              as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toInt()));

  /// Fetches the configured organization logo through the server-side proxy
  /// (`/api/v1/meta/logo`) so it is delivered same-origin (no browser CORS).
  /// Returns the raw bytes plus whether the payload is SVG, or null when no
  /// logo is configured / reachable.
  Future<({List<int> bytes, bool isSvg})?> organizationLogo() async {
    final result = await _api.getBytes('/api/v1/meta/logo');
    if (result == null) return null;
    final head = String.fromCharCodes(result.bytes.take(256)).toLowerCase();
    final isSvg =
        result.contentType.contains('svg') ||
        head.contains('<svg') ||
        head.contains('<?xml');
    return (bytes: result.bytes, isSvg: isSvg);
  }

  /// Daily created/resolved counts for a project over the last [days] —
  /// the basis for the burndown (cumulative remaining) trend.
  Future<List<TrendPoint>> createdVsResolved(
    String projectId, {
    int days = 30,
  }) async =>
      ((await _api.get(
                '/api/v1/reports/created-vs-resolved',
                query: {'projectId': projectId, 'days': '$days'},
              ))
              as List<dynamic>)
          .map((e) => TrendPoint.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<List<AppNotification>> notifications({int page = 0}) async {
    final data =
        await _api.get('/api/v1/notifications', query: {'page': page})
            as Map<String, dynamic>;
    return ((data['content'] as List<dynamic>?) ?? [])
        .map((n) => AppNotification.fromJson(n as Map<String, dynamic>))
        .toList();
  }

  /// One page of notifications plus the backend total, for infinite scroll.
  Future<({List<AppNotification> items, int total})> notificationsPage({
    int page = 0,
    int size = 25,
  }) async {
    final data =
        await _api.get(
              '/api/v1/notifications',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? [])
          .map((n) => AppNotification.fromJson(n as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  Future<int> unreadNotifications() async =>
      ((await _api.get('/api/v1/notifications/unread-count'))
              as Map<String, dynamic>)['count']
          as int? ??
      0;

  Future<void> markNotificationRead(String id) =>
      _api.post('/api/v1/notifications/$id/read');

  /// Marks every supplied notification id as read. The backend exposes no bulk
  /// endpoint, so we fan the per-id calls out concurrently.
  Future<void> markNotificationsRead(Iterable<String> ids) =>
      Future.wait(ids.map(markNotificationRead));

  // --- Admin ----------------------------------------------------------------

  Future<Map<String, dynamic>> adminSettings() async =>
      await _api.get('/api/v1/admin/settings') as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateAdminSettings(
    Map<String, dynamic> settings,
  ) async =>
      await _api.put('/api/v1/admin/settings', body: settings)
          as Map<String, dynamic>;

  // --- Admin · User management ----------------------------------------------

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

  // --- Admin · Audit log ----------------------------------------------------

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

  // --- Teams ----------------------------------------------------------------

  Future<List<Team>> teams() async =>
      ((await _api.get('/api/v1/teams')) as List<dynamic>)
          .map((t) => Team.fromJson(t as Map<String, dynamic>))
          .toList();

  Future<Team> team(String id) async => Team.fromJson(
    await _api.get('/api/v1/teams/$id') as Map<String, dynamic>,
  );

  Future<Team> createTeam({
    required String name,
    required String key,
    String? description,
    required int colorHue,
    required String icon,
  }) async => Team.fromJson(
    await _api.post(
          '/api/v1/teams',
          body: {
            'name': name,
            'key': key,
            'description': ?description,
            'colorHue': colorHue,
            'icon': icon,
          },
        )
        as Map<String, dynamic>,
  );

  Future<Team> updateTeam(String id, Map<String, dynamic> patch) async =>
      Team.fromJson(
        await _api.patch('/api/v1/teams/$id', body: patch)
            as Map<String, dynamic>,
      );

  Future<void> deleteTeam(String id) => _api.delete('/api/v1/teams/$id');

  /// Adds [userIds] to the team with a single [role] + [access] for the batch.
  Future<Team> addTeamMembers(
    String teamId,
    List<String> userIds, {
    required TeamRole role,
    required ProjectAccess access,
  }) async => Team.fromJson(
    await _api.post(
          '/api/v1/teams/$teamId/members',
          body: {
            'userIds': userIds,
            'role': role.wire,
            'access': access.toJson(),
          },
        )
        as Map<String, dynamic>,
  );

  Future<Team> updateTeamMembership(
    String teamId,
    String userId, {
    TeamRole? role,
    ProjectAccess? access,
  }) async => Team.fromJson(
    await _api.patch(
          '/api/v1/teams/$teamId/members/$userId',
          body: {
            if (role != null) 'role': role.wire,
            if (access != null) 'access': access.toJson(),
          },
        )
        as Map<String, dynamic>,
  );

  Future<Team> removeTeamMember(String teamId, String userId) async =>
      Team.fromJson(
        await _api.delete('/api/v1/teams/$teamId/members/$userId')
            as Map<String, dynamic>,
      );

  Future<Team> attachTeamProjects(
    String teamId,
    List<String> projectIds,
  ) async => Team.fromJson(
    await _api.post(
          '/api/v1/teams/$teamId/projects',
          body: {'projectIds': projectIds},
        )
        as Map<String, dynamic>,
  );

  Future<Project> createTeamProject(
    String teamId, {
    required String key,
    required String name,
    String? description,
    String? color,
    String? leadId,
  }) async => Project.fromJson(
    await _api.post(
          '/api/v1/teams/$teamId/projects/new',
          body: {
            'key': key,
            'name': name,
            'description': ?description,
            'color': ?color,
            'leadId': ?leadId,
          },
        )
        as Map<String, dynamic>,
  );

  Future<Team> detachTeamProject(String teamId, String projectId) async =>
      Team.fromJson(
        await _api.delete('/api/v1/teams/$teamId/projects/$projectId')
            as Map<String, dynamic>,
      );

  Future<List<TeamActivity>> teamActivity(String teamId, {int page = 0}) async {
    final data =
        await _api.get('/api/v1/teams/$teamId/activity', query: {'page': page})
            as Map<String, dynamic>;
    return ((data['content'] as List<dynamic>?) ?? const [])
        .map((a) => TeamActivity.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  /// One newest-first page of a team's activity feed, plus the backend total.
  Future<({List<TeamActivity> items, int total})> teamActivityPage(
    String teamId, {
    int page = 0,
    int size = 20,
  }) async {
    final data =
        await _api.get(
              '/api/v1/teams/$teamId/activity',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? const [])
          .map((a) => TeamActivity.fromJson(a as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  // --- Cascading deletion ---------------------------------------------------

  /// Counts driving the board delete confirmation (sprints, issues to detach).
  Future<BoardDeletionImpact> boardDeletionImpact(String boardId) async =>
      BoardDeletionImpact.fromJson(
        await _api.get('/api/v1/boards/$boardId/deletion-impact')
            as Map<String, dynamic>,
      );

  /// Affected boards/issues/etc. + the projects issues could migrate into.
  Future<ProjectDeletionImpact> projectDeletionImpact(String projectId) async =>
      ProjectDeletionImpact.fromJson(
        await _api.get('/api/v1/projects/$projectId/deletion-impact')
            as Map<String, dynamic>,
      );

  /// The access (members/projects/boards/issues) members lose with the team.
  Future<TeamDeletionImpact> teamDeletionImpact(String teamId) async =>
      TeamDeletionImpact.fromJson(
        await _api.get('/api/v1/teams/$teamId/deletion-impact')
            as Map<String, dynamic>,
      );

  /// Raw SSE byte stream of a board deletion (parse with [parseSse] →
  /// [DeleteEvent.tryParse]). Cancel via [cancelToken] to abort listening.
  Future<Stream<List<int>>> boardDeleteStream(
    String boardId, {
    CancelToken? cancelToken,
  }) => _api.openEventStream(
    '/api/v1/boards/$boardId/delete-stream',
    cancelToken: cancelToken,
  );

  /// Raw SSE byte stream of a project deletion. [strategy]/[migrateToProjectId]
  /// are required only when the project still has issues.
  Future<Stream<List<int>>> projectDeleteStream(
    String projectId, {
    IssueStrategy? strategy,
    String? migrateToProjectId,
    CancelToken? cancelToken,
  }) {
    final query = <String, String>{
      'issueStrategy': ?strategy?.wire,
      'migrateToProjectId': ?migrateToProjectId,
    };
    final suffix = query.isEmpty
        ? ''
        : '?${query.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    return _api.openEventStream(
      '/api/v1/projects/$projectId/delete-stream$suffix',
      cancelToken: cancelToken,
    );
  }

  /// Raw SSE byte stream of a team deletion.
  Future<Stream<List<int>>> teamDeleteStream(
    String teamId, {
    CancelToken? cancelToken,
  }) => _api.openEventStream(
    '/api/v1/teams/$teamId/delete-stream',
    cancelToken: cancelToken,
  );

  // --- Git integration ------------------------------------------------------
  // Per-project repository connection + automation, and per-issue development
  // information. OAuth is brokered server-side; the client never sees a token.

  /// Kicks off the real OAuth flow for [provider]; returns the consent URL to
  /// open + the `state` to poll (or `available:false` when no provider app is
  /// configured, in which case the client uses the URL + token method).
  Future<GitOAuthStart> gitOAuthStart(String projectId, String provider) async =>
      GitOAuthStart.fromJson(
        await _api.post(
              '/api/v1/projects/$projectId/git/oauth/start',
              body: {'provider': provider},
            )
            as Map<String, dynamic>,
      );

  /// Polls the server-side OAuth session (by [state]) for completion.
  Future<GitOAuthSessionStatus> gitOAuthSession(String state) async =>
      GitOAuthSessionStatus.fromJson(
        await _api.get('/api/v1/git/oauth/session/$state') as Map<String, dynamic>,
      );

  /// Owners (org / group / workspace) the authorized account exposes.
  Future<List<GitOwner>> gitOwners(
    String projectId,
    String provider, {
    String? state,
  }) async =>
      ((await _api.get(
                '/api/v1/projects/$projectId/git/owners',
                query: {
                  'provider': provider,
                  'state': ?state,
                },
              ))
              as List<dynamic>)
          .map((o) => GitOwner.fromJson(o as Map<String, dynamic>))
          .toList();

  /// Repositories under [owner], optionally filtered by [query].
  Future<List<GitRepo>> gitRepos(
    String projectId,
    String provider,
    String owner, {
    String? query,
    String? state,
  }) async =>
      ((await _api.get(
                '/api/v1/projects/$projectId/git/repos',
                query: {
                  'provider': provider,
                  'owner': owner,
                  if (query != null && query.isNotEmpty) 'q': query,
                  'state': ?state,
                },
              ))
              as List<dynamic>)
          .map((r) => GitRepo.fromJson(r as Map<String, dynamic>))
          .toList();

  /// Binds the chosen repo to the project; returns the updated project.
  Future<Project> gitConnect(
    String projectId, {
    required String provider,
    required String owner,
    required String repo,
    String? state,
  }) async => Project.fromJson(
    await _api.post(
          '/api/v1/projects/$projectId/git/connect',
          body: {
            'provider': provider,
            'owner': owner,
            'repo': repo,
            'state': ?state,
          },
        )
        as Map<String, dynamic>,
  );

  /// Self-managed fallback — connect with a repo URL + access token.
  Future<Project> gitConnectToken(
    String projectId, {
    required String repoUrl,
    required String token,
  }) async => Project.fromJson(
    await _api.post(
          '/api/v1/projects/$projectId/git/connect-token',
          body: {'repoUrl': repoUrl, 'token': token},
        )
        as Map<String, dynamic>,
  );

  Future<Project> gitDisconnect(String projectId) async => Project.fromJson(
    await _api.delete('/api/v1/projects/$projectId/git') as Map<String, dynamic>,
  );

  Future<Project> gitResync(String projectId) async => Project.fromJson(
    await _api.post('/api/v1/projects/$projectId/git/resync')
        as Map<String, dynamic>,
  );

  Future<Project> gitSetAutomation(
    String projectId,
    GitAutomation automation,
  ) async => Project.fromJson(
    await _api.patch(
          '/api/v1/projects/$projectId/git/automation',
          body: automation.toJson(),
        )
        as Map<String, dynamic>,
  );

  Future<Project> gitSetBranchTemplate(String projectId, String template) async =>
      Project.fromJson(
        await _api.patch(
              '/api/v1/projects/$projectId/git/branch-template',
              body: {'branchTemplate': template},
            )
            as Map<String, dynamic>,
      );

  /// Development information (branches/commits/PRs/builds) for an issue key.
  Future<DevInfo> gitDevInfo(String issueKey) async => DevInfo.fromJson(
    await _api.get('/api/v1/issues/$issueKey/dev-info') as Map<String, dynamic>,
  );

  /// Merges a PR/MR from the Development panel; the server applies the project's
  /// `prMerged` automation and returns the updated dev-info + issue.
  Future<({DevInfo devInfo, Issue issue})> gitMergePr(
    String issueKey,
    int number,
  ) async {
    final json =
        await _api.post('/api/v1/issues/$issueKey/dev-info/prs/$number/merge')
            as Map<String, dynamic>;
    return (
      devInfo: DevInfo.fromJson(json['devInfo'] as Map<String, dynamic>),
      issue: Issue.fromJson(json['issue'] as Map<String, dynamic>),
    );
  }

  /// Marks a draft PR/MR ready for review; applies the `prOpened` automation.
  Future<({DevInfo devInfo, Issue issue})> gitReadyPr(
    String issueKey,
    int number,
  ) async {
    final json =
        await _api.post('/api/v1/issues/$issueKey/dev-info/prs/$number/ready')
            as Map<String, dynamic>;
    return (
      devInfo: DevInfo.fromJson(json['devInfo'] as Map<String, dynamic>),
      issue: Issue.fromJson(json['issue'] as Map<String, dynamic>),
    );
  }
}
