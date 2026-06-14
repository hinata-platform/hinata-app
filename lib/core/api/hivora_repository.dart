import 'package:dio/dio.dart';

import '../models/content_models.dart';
import '../models/core_models.dart';
import '../models/search_api.dart';
import '../models/work_models.dart';
import 'api_client.dart';

/// Single REST gateway for the Hivora server API (v1).
class HivoraRepository {
  HivoraRepository(this._api);

  final ApiClient _api;

  // --- Meta & setup ---------------------------------------------------------

  Future<ServerMeta> meta() async =>
      ServerMeta.fromJson(await _api.get('/api/v1/meta') as Map<String, dynamic>);

  Future<void> completeSetup({
    required String organizationName,
    required String adminEmail,
    required String adminUsername,
    required String adminDisplayName,
    required String adminPassword,
  }) =>
      _api.post('/api/v1/setup', body: {
        'organizationName': organizationName,
        'adminEmail': adminEmail,
        'adminUsername': adminUsername,
        'adminDisplayName': adminDisplayName,
        'adminPassword': adminPassword,
      });

  // --- Auth -----------------------------------------------------------------

  Future<({String access, String refresh, AuthUser user})> login(
      String identifier, String password) async {
    final data = await _api.post('/api/v1/auth/login',
        body: {'identifier': identifier, 'password': password}) as Map<String, dynamic>;
    return (
      access: data['accessToken'] as String,
      refresh: data['refreshToken'] as String,
      user: AuthUser.fromJson(data['user'] as Map<String, dynamic>),
    );
  }

  Future<AuthUser> me() async =>
      AuthUser.fromJson(await _api.get('/api/v1/auth/me') as Map<String, dynamic>);

  Future<List<SsoProvider>> ssoProviders() async =>
      ((await _api.get('/api/v1/auth/sso/providers')) as List<dynamic>)
          .map((p) => SsoProvider.fromJson(p as Map<String, dynamic>))
          .toList();

  Future<void> changePassword(String current, String next) =>
      _api.post('/api/v1/auth/password',
          body: {'currentPassword': current, 'newPassword': next});

  // --- Users ----------------------------------------------------------------

  Future<List<DirectoryUser>> users() async =>
      ((await _api.get('/api/v1/users')) as List<dynamic>)
          .map((u) => DirectoryUser.fromJson(u as Map<String, dynamic>))
          .toList();

  // --- Projects -------------------------------------------------------------

  Future<List<Project>> projects() async =>
      ((await _api.get('/api/v1/projects')) as List<dynamic>)
          .map((p) => Project.fromJson(p as Map<String, dynamic>))
          .toList();

  Future<Project> createProject({
    required String key,
    required String name,
    String? description,
    String? color,
  }) async =>
      Project.fromJson(await _api.post('/api/v1/projects', body: {
        'key': key,
        'name': name,
        'description': ?description,
        'color': ?color,
      }) as Map<String, dynamic>);

  // --- Issues ---------------------------------------------------------------

  Future<({List<Issue> issues, int total})> issues({
    String? projectId,
    String? state,
    String? assigneeId,
    String? query,
    int page = 0,
    int size = 50,
  }) async {
    final data = await _api.get('/api/v1/issues', query: {
      'projectId': ?projectId,
      'state': ?state,
      'assigneeId': ?assigneeId,
      if (query != null && query.isNotEmpty) 'query': query,
      'page': page,
      'size': size,
    }) as Map<String, dynamic>;
    return (
      issues: ((data['content'] as List<dynamic>?) ?? [])
          .map((i) => Issue.fromJson(i as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  Future<Issue> issue(String id) async =>
      Issue.fromJson(await _api.get('/api/v1/issues/$id') as Map<String, dynamic>);

  Future<Issue> createIssue(Map<String, dynamic> body) async =>
      Issue.fromJson(await _api.post('/api/v1/issues', body: body) as Map<String, dynamic>);

  Future<Issue> updateIssue(String id, Map<String, dynamic> patch) async =>
      Issue.fromJson(
          await _api.patch('/api/v1/issues/$id', body: patch) as Map<String, dynamic>);

  Future<void> deleteIssue(String id) => _api.delete('/api/v1/issues/$id');

  Future<List<IssueActivity>> issueActivity(String issueId) async =>
      ((await _api.get('/api/v1/issues/$issueId/activity')) as List<dynamic>)
          .map((a) => IssueActivity.fromJson(a as Map<String, dynamic>))
          .toList();

  Future<List<IssueComment>> comments(String issueId) async =>
      ((await _api.get('/api/v1/issues/$issueId/comments')) as List<dynamic>)
          .map((c) => IssueComment.fromJson(c as Map<String, dynamic>))
          .toList();

  Future<IssueComment> addComment(String issueId, String text) async =>
      IssueComment.fromJson(await _api.post('/api/v1/issues/$issueId/comments',
          body: {'text': text}) as Map<String, dynamic>);

  Future<Issue> uploadAttachment(String issueId, MultipartFile file) async =>
      Issue.fromJson(await _api.upload('/api/v1/issues/$issueId/attachments', file)
          as Map<String, dynamic>);

  // --- Boards ---------------------------------------------------------------

  Future<List<AgileBoard>> boards({String? projectId}) async =>
      ((await _api.get('/api/v1/boards',
              query: {'projectId': ?projectId})) as List<dynamic>)
          .map((b) => AgileBoard.fromJson(b as Map<String, dynamic>))
          .toList();

  Future<AgileBoard> createBoard(String name, List<String> projectIds) async =>
      AgileBoard.fromJson(await _api.post('/api/v1/boards',
          body: {'name': name, 'projectIds': projectIds}) as Map<String, dynamic>);

  Future<BoardView> boardView(String boardId, {String? sprintId}) async =>
      BoardView.fromJson(await _api.get('/api/v1/boards/$boardId',
          query: {'sprintId': ?sprintId}) as Map<String, dynamic>);

  // --- Time tracking --------------------------------------------------------

  Future<List<WorkItem>> workItems(String issueId) async =>
      ((await _api.get('/api/v1/issues/$issueId/work-items')) as List<dynamic>)
          .map((w) => WorkItem.fromJson(w as Map<String, dynamic>))
          .toList();

  Future<WorkItem> addWorkItem(String issueId,
      {required int minutes, String? activityType, String? description, DateTime? date}) async {
    return WorkItem.fromJson(await _api.post('/api/v1/issues/$issueId/work-items', body: {
      'durationMinutes': minutes,
      'activityType': ?activityType,
      'description': ?description,
      if (date != null) 'date': date.toIso8601String().substring(0, 10),
    }) as Map<String, dynamic>);
  }

  Future<List<TimesheetRow>> timesheet(DateTime from, DateTime to,
      {String? userId, String? projectId}) async {
    final data = await _api.get('/api/v1/timesheet', query: {
      'from': from.toIso8601String().substring(0, 10),
      'to': to.toIso8601String().substring(0, 10),
      'userId': ?userId,
      'projectId': ?projectId,
    }) as List<dynamic>;
    return data.map((r) => TimesheetRow.fromJson(r as Map<String, dynamic>)).toList();
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
      SearchApiResponse.fromJson(await _api.get('/api/v1/search', query: {
        'q': ?(query.trim().isEmpty ? null : query.trim()),
        'scope': ?scope,
      }) as Map<String, dynamic>);

  // --- Knowledge base -------------------------------------------------------

  Future<List<Article>> articles({String? projectId}) async =>
      ((await _api.get('/api/v1/articles',
              query: {'projectId': ?projectId})) as List<dynamic>)
          .map((a) => Article.fromJson(a as Map<String, dynamic>))
          .toList();

  Future<Article> article(String id) async =>
      Article.fromJson(await _api.get('/api/v1/articles/$id') as Map<String, dynamic>);

  Future<Article> saveArticle({
    String? id,
    required String title,
    String? content,
    String? projectId,
    String? parentId,
  }) async {
    final body = {
      'title': title,
      'content': ?content,
      'projectId': ?projectId,
      'parentId': ?parentId,
    };
    final data = id == null
        ? await _api.post('/api/v1/articles', body: body)
        : await _api.patch('/api/v1/articles/$id', body: body);
    return Article.fromJson(data as Map<String, dynamic>);
  }

  // --- Dashboard, reports, notifications ------------------------------------

  Future<DashboardData> dashboard() async =>
      DashboardData.fromJson(await _api.get('/api/v1/dashboard') as Map<String, dynamic>);

  Future<Map<String, int>> report(String name, Map<String, dynamic> query) async =>
      ((await _api.get('/api/v1/reports/$name', query: query)) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toInt()));

  /// Fetches the configured organization logo through the server-side proxy
  /// (`/api/v1/meta/logo`) so it is delivered same-origin (no browser CORS).
  /// Returns the raw bytes plus whether the payload is SVG, or null when no
  /// logo is configured / reachable.
  Future<({List<int> bytes, bool isSvg})?> organizationLogo() async {
    final result = await _api.getBytes('/api/v1/meta/logo');
    if (result == null) return null;
    final head = String.fromCharCodes(result.bytes.take(256))
        .toLowerCase();
    final isSvg = result.contentType.contains('svg') ||
        head.contains('<svg') ||
        head.contains('<?xml');
    return (bytes: result.bytes, isSvg: isSvg);
  }

  /// Daily created/resolved counts for a project over the last [days] —
  /// the basis for the burndown (cumulative remaining) trend.
  Future<List<TrendPoint>> createdVsResolved(String projectId,
          {int days = 30}) async =>
      ((await _api.get('/api/v1/reports/created-vs-resolved',
                  query: {'projectId': projectId, 'days': '$days'}))
              as List<dynamic>)
          .map((e) => TrendPoint.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<List<AppNotification>> notifications({int page = 0}) async {
    final data = await _api.get('/api/v1/notifications', query: {'page': page})
        as Map<String, dynamic>;
    return ((data['content'] as List<dynamic>?) ?? [])
        .map((n) => AppNotification.fromJson(n as Map<String, dynamic>))
        .toList();
  }

  Future<int> unreadNotifications() async =>
      ((await _api.get('/api/v1/notifications/unread-count'))
          as Map<String, dynamic>)['count'] as int? ?? 0;

  Future<void> markNotificationRead(String id) =>
      _api.post('/api/v1/notifications/$id/read');

  /// Marks every supplied notification id as read. The backend exposes no bulk
  /// endpoint, so we fan the per-id calls out concurrently.
  Future<void> markNotificationsRead(Iterable<String> ids) =>
      Future.wait(ids.map(markNotificationRead));

  // --- Admin ----------------------------------------------------------------

  Future<Map<String, dynamic>> adminSettings() async =>
      await _api.get('/api/v1/admin/settings') as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateAdminSettings(Map<String, dynamic> settings) async =>
      await _api.put('/api/v1/admin/settings', body: settings) as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> adminUsers() async =>
      ((await _api.get('/api/v1/admin/users')) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<void> adminCreateUser(Map<String, dynamic> body) =>
      _api.post('/api/v1/admin/users', body: body);

  Future<void> adminUpdateUser(String id, Map<String, dynamic> patch) =>
      _api.patch('/api/v1/admin/users/$id', body: patch);

  Future<void> adminDeleteUser(String id) =>
      _api.delete('/api/v1/admin/users/$id');
}
