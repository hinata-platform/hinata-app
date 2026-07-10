import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../models/deletion_models.dart';
import '../models/work_models.dart';

/// Projects: CRUD, workflow/label settings support, the Gantt aggregate, and
/// cascading deletion.
class ProjectRepository {
  ProjectRepository(this._api);

  final ApiClient _api;

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

  Future<List<GanttTask>> gantt(String projectId) async =>
      ((await _api.get('/api/v1/projects/$projectId/gantt')) as List<dynamic>)
          .map((t) => GanttTask.fromJson(t as Map<String, dynamic>))
          .toList();

  /// Affected boards/issues/etc. + the projects issues could migrate into.
  Future<ProjectDeletionImpact> projectDeletionImpact(String projectId) async =>
      ProjectDeletionImpact.fromJson(
        await _api.get('/api/v1/projects/$projectId/deletion-impact')
            as Map<String, dynamic>,
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
}
