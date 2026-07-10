import '../api/api_client.dart';
import '../models/work_models.dart';

/// The cross-project timesheet aggregate.
class TimesheetRepository {
  TimesheetRepository(this._api);

  final ApiClient _api;

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
}
