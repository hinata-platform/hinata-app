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

  Future<IssueTimeUsage> issue(String issueIdOrKey) async {
    final data =
        await _api.get('/api/v1/issues/$issueIdOrKey/time-usage')
            as Map<String, dynamic>;
    return IssueTimeUsage.fromJson(data);
  }
}
