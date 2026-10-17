import '../api/api_client.dart';
import '../models/report_overview_models.dart';
import '../models/content_models.dart';

/// The dashboard aggregate, its personalisation prefs, and report queries.
class DashboardRepository {
  DashboardRepository(this._api);

  final ApiClient _api;

  /// The dashboard aggregate. Pass [override] to preview a scope/board that
  /// hasn't been saved yet (edit mode); with no override the caller's saved
  /// [DashboardPrefs] drive the view server-side.
  Future<DashboardData> dashboard({DashboardPrefs? override}) async {
    final query = <String, dynamic>{};
    if (override != null) {
      // Always send the keys (even when empty) so the server treats this as a
      // preview and applies exactly this scope instead of the saved prefs.
      query['boardId'] = override.boardId ?? '';
      query['projectIds'] = override.projectIds;
      query['teamIds'] = override.teamIds;
    }
    return DashboardData.fromJson(
      await _api.get('/api/v1/dashboard', query: query.isEmpty ? null : query)
          as Map<String, dynamic>,
    );
  }

  /// Persist the caller's dashboard personalisation; returns the stored value.
  Future<DashboardPrefs> saveDashboardPrefs(DashboardPrefs prefs) async =>
      DashboardPrefs.fromJson(
        await _api.put('/api/v1/dashboard/prefs', body: prefs.toJson())
            as Map<String, dynamic>,
      );

  /// The report overview of one project in one call (HIN-157).
  Future<ReportOverview> overview(String projectId, {int days = 30}) async =>
      ReportOverview.fromJson(
        await _api.get(
              '/api/v1/reports/overview',
              query: {'projectId': projectId, 'days': '$days'},
            )
            as Map<String, dynamic>,
      );
}
