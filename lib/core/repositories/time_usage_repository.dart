import '../api/api_client.dart';
import '../models/time_usage_models.dart';

/// Budget and estimate usage (HIN-152): what a project or an issue has used,
/// read for the bars, capsules and rings that show it.
///
/// Separate from [TimeRepository] because it is read by surfaces that know
/// nothing else about time tracking: a board head, the project list, the
/// dashboard.
class TimeUsageRepository {
  TimeUsageRepository(this._api);

  final ApiClient _api;

  /// How many projects one call answers; the server refuses more.
  static const batchMax = 100;

  Future<ProjectTimeUsage> project(String projectId) async {
    final data =
        await _api.get('/api/v1/projects/$projectId/time-usage')
            as Map<String, dynamic>;
    return ProjectTimeUsage.fromJson(data);
  }

  /// The usage of each project in [projectIds] the caller can see, keyed by
  /// project. Asked in steps of [batchMax].
  Future<Map<String, ProjectTimeUsage>> projects(
    Iterable<String> projectIds,
  ) async {
    final ids = projectIds.toSet().toList();
    final found = <String, ProjectTimeUsage>{};
    for (var start = 0; start < ids.length; start += batchMax) {
      final step = ids.sublist(
        start,
        start + batchMax > ids.length ? ids.length : start + batchMax,
      );
      final data =
          await _api.get(
                '/api/v1/projects/time-usage',
                query: {'ids': step.join(',')},
              )
              as List<dynamic>;
      for (final row in data.cast<Map<String, dynamic>>()) {
        final usage = ProjectTimeUsage.fromJson(row);
        found[usage.projectId] = usage;
      }
    }
    return found;
  }

  /// The fullest budgets the reader sees, at most [limit], optionally only
  /// among [projectIds] (the dashboard's own scope).
  Future<TopBudgets> top({
    int limit = 3,
    List<String> projectIds = const [],
  }) async {
    final data =
        await _api.get(
              '/api/v1/projects/time-usage/top',
              query: {
                'limit': '$limit',
                if (projectIds.isNotEmpty) 'projectIds': projectIds.join(','),
              },
            )
            as Map<String, dynamic>;
    return TopBudgets.fromJson(data);
  }

  /// Recorded minutes per day for the burn-down (HIN-156); the server's
  /// default span, the last 90 days, unless [from] and [to] say otherwise.
  Future<BudgetHistory> history(
    String projectId, {
    DateTime? from,
    DateTime? to,
  }) async {
    String day(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final data =
        await _api.get(
              '/api/v1/projects/$projectId/time-usage/history',
              query: {
                'from': ?(from == null ? null : day(from)),
                'to': ?(to == null ? null : day(to)),
              },
            )
            as Map<String, dynamic>;
    return BudgetHistory.fromJson(data);
  }

  Future<BudgetForecast> forecast(String projectId) async {
    final data =
        await _api.get('/api/v1/projects/$projectId/time-usage/forecast')
            as Map<String, dynamic>;
    return BudgetForecast.fromJson(data);
  }

  Future<SprintTimeUsage> sprint(String sprintId) async {
    final data =
        await _api.get('/api/v1/sprints/$sprintId/time-usage')
            as Map<String, dynamic>;
    return SprintTimeUsage.fromJson(data);
  }

  /// Sets or, with null, removes a sprint's budget.
  Future<SprintTimeUsage> setSprintBudget(String sprintId, int? minutes) async {
    final data =
        await _api.put(
              '/api/v1/sprints/$sprintId/time-settings',
              body: {'budgetMinutes': minutes},
            )
            as Map<String, dynamic>;
    return SprintTimeUsage.fromJson(data);
  }

  Future<IssueTimeUsage> issue(String issueIdOrKey) async {
    final data =
        await _api.get('/api/v1/issues/$issueIdOrKey/time-usage')
            as Map<String, dynamic>;
    return IssueTimeUsage.fromJson(data);
  }
}
