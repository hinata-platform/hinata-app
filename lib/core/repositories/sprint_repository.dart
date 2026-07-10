import '../api/api_client.dart';
import '../models/work_models.dart';
import 'board_repository.dart';

/// Sprints: lifecycle (create → start → complete), scope, and the server-side
/// sprint report.
class SprintRepository {
  SprintRepository(this._api, {required BoardRepository boards})
    : _boards = boards;

  final ApiClient _api;
  final BoardRepository _boards;

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
    final boardList = await _boards.boards(projectId: projectId);
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
}
