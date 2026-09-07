import '../api/api_client.dart';
import '../blocs/paged_cubit.dart';
import '../models/time_models.dart';
import '../models/work_models.dart';

/// The extended time-tracking module: the running timer and the personal list
/// of entries.
///
/// Every route here is behind the server's `advanced_time_tracking` flag, so
/// with the module off they answer 404 `error.feature.disabled` — which the app
/// reads as "our idea of the flag is stale" and re-reads `/meta`, rather than
/// showing a not-found page (see `core/api/feature_gate.dart`).
///
/// Editing and deleting deliberately go through `/time/entries/{id}` rather
/// than the 1.x `/work-items/{id}`: same service and same rules on the server,
/// but the module's own route, so an entry edited from this screen behaves the
/// same as one edited anywhere else in the module once later stages add a lock
/// date and approvals.
class TimeRepository {
  TimeRepository(this._api);

  final ApiClient _api;

  // --- the timer -------------------------------------------------------------

  /// The running timer, or null when none is. A 204 carries no body.
  Future<RunningTimer?> timer() async {
    final data = await _api.get('/api/v1/me/timer');
    if (data is! Map<String, dynamic>) return null;
    return RunningTimer.fromJson(data);
  }

  /// Starts one. Throws with status 409 when a timer is already running.
  Future<RunningTimer> startTimer({
    String? projectId,
    String? issueId,
    String? description,
    String? activityType,
    List<String> tags = const [],
    bool? billable,
  }) async {
    final data =
        await _api.post(
              '/api/v1/me/timer/start',
              body: {
                'projectId': ?projectId,
                'issueId': ?issueId,
                'description': ?description,
                'activityType': ?activityType,
                'tags': tags,
                'billable': ?billable,
              },
            )
            as Map<String, dynamic>;
    return RunningTimer.fromJson(data);
  }

  /// Renames or re-files a timer that is still running.
  Future<RunningTimer> patchTimer({
    String? projectId,
    String? issueId,
    String? description,
    String? activityType,
    List<String>? tags,
    bool? billable,
  }) async {
    final data =
        await _api.patch(
              '/api/v1/me/timer',
              // The timer's whole editable state, not a diff: the server reads
              // an absent field and an explicit null the same way — as cleared —
              // so every field is named on every patch, and the caller is the
              // one that carries forward what it does not mean to change (see
              // TimerCubit.patch).
              body: {
                'projectId': projectId,
                'issueId': issueId,
                'description': description,
                'activityType': activityType,
                'tags': tags ?? const <String>[],
                'billable': billable ?? false,
              },
            )
            as Map<String, dynamic>;
    return RunningTimer.fromJson(data);
  }

  /// Stops it and returns the entry it became.
  ///
  /// Safe to repeat: the server files the entry under the timer's own id, so a
  /// retry answers with the entry the first attempt created rather than making
  /// a second one.
  Future<SavedTimeEntry> stopTimer({
    String? timerId,
    String? projectId,
    String? issueId,
    String? description,
    String? activityType,
    List<String>? tags,
    bool? billable,
  }) async {
    final data =
        await _api.post(
              '/api/v1/me/timer/stop',
              body: {
                // Which timer this ends. Without it the server stops whatever is
                // running now — so a stop that timed out on a flaky link and was
                // pressed again after a new timer had been started would end the
                // new one. Named, the retry answers with the entry the first
                // attempt filed.
                'timerId': ?timerId,
                'projectId': ?projectId,
                'issueId': ?issueId,
                'description': ?description,
                'activityType': ?activityType,
                'tags': ?tags,
                'billable': ?billable,
              },
            )
            as Map<String, dynamic>;
    return SavedTimeEntry.fromJson(data);
  }

  /// Throws the running timer away; nothing is recorded.
  Future<void> discardTimer() => _api.post('/api/v1/me/timer/discard');

  // --- entries ---------------------------------------------------------------

  /// One page of the caller's own entries, newest first.
  Future<PageResult<WorkItem>> entries({
    TimeEntryFilter filter = const TimeEntryFilter(),
    int page = 0,
    int size = 50,
  }) async {
    final data =
        await _api.get(
              '/api/v1/time/entries',
              query: {...filter.toQuery(), 'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? const [])
          .map((e) => WorkItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  Future<SavedTimeEntry> create(TimeEntryDraft draft) async {
    final data =
        await _api.post('/api/v1/time/entries', body: draft.toCreateJson())
            as Map<String, dynamic>;
    return SavedTimeEntry.fromJson(data);
  }

  Future<SavedTimeEntry> update(String id, TimeEntryDraft draft) async {
    final data =
        await _api.patch('/api/v1/time/entries/$id', body: draft.toPatchJson())
            as Map<String, dynamic>;
    return SavedTimeEntry.fromJson(data);
  }

  Future<void> delete(String id) => _api.delete('/api/v1/time/entries/$id');

  /// Starts a timer carrying an existing entry's description and placement.
  Future<RunningTimer> continueEntry(String id) async {
    final data =
        await _api.post('/api/v1/time/entries/$id/continue')
            as Map<String, dynamic>;
    return RunningTimer.fromJson(data);
  }
}
