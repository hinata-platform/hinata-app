import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../models/work_models.dart';

/// Issues: search/CRUD, hierarchy, relationship links, change history,
/// attachments, and time-tracking work items.
class IssueRepository {
  IssueRepository(this._api);

  final ApiClient _api;

  /// The configured backend base URL — used to derive shareable web links to
  /// issues (copy-link, smart links).
  String get apiBaseUrl => _api.baseUrl;

  Future<({List<Issue> issues, int total})> issues({
    String? projectId,
    String? state,
    String? assigneeId,
    String? sprintId,
    String? type,
    String? query,
    bool noSprint = false,
    bool archived = false,
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
                'type': ?type,
                if (noSprint) 'noSprint': true,
                if (archived) 'archived': true,
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
    bool archived = false,
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
        archived: archived,
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

  /// Soft delete — any project member may archive; the issue disappears from
  /// all default listings but stays restorable.
  Future<Issue> archiveIssue(String id) async => Issue.fromJson(
    await _api.post('/api/v1/issues/$id/archive') as Map<String, dynamic>,
  );

  /// Restores an archived issue (and its archived sub-tasks).
  Future<Issue> unarchiveIssue(String id) async => Issue.fromJson(
    await _api.post('/api/v1/issues/$id/unarchive') as Map<String, dynamic>,
  );

  /// Whether the current user may hard-delete the issue (platform admin,
  /// project lead, or Team-Admin of a team owning the project).
  Future<bool> canDeleteIssue(String id) async {
    final data =
        await _api.get('/api/v1/issues/$id/permissions')
            as Map<String, dynamic>;
    return data['canDelete'] as bool? ?? false;
  }

  // --- Issue links (typed relationships) -------------------------------------

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

  // --- Attachments ------------------------------------------------------------

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

  /// Raw SSE byte stream of attachment changes for an issue (parse with
  /// [parseSse]). Cancel via [cancelToken] when the view is disposed.
  Future<Stream<List<int>>> attachmentEventStream(
    String issueId, {
    CancelToken? cancelToken,
  }) => _api.openEventStream(
    '/api/v1/issues/$issueId/attachments/stream',
    cancelToken: cancelToken,
  );

  // --- Time tracking ----------------------------------------------------------

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
}
