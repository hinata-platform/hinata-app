import '../api/api_client.dart';
import '../models/weekly_summary_models.dart';

/// The caller's Weekly Summary aggregate (the team's week behind + the caller's
/// week ahead), backing the Weekly Summary page.
class WeeklySummaryRepository {
  WeeklySummaryRepository(this._api);

  final ApiClient _api;

  Future<WeeklySummary> summary() async => WeeklySummary.fromJson(
    await _api.get('/api/v1/weekly-summary') as Map<String, dynamic>,
  );
}
