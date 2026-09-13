import 'dart:typed_data';

import '../api/api_client.dart';
import '../blocs/paged_cubit.dart';
import '../models/time_approval_models.dart';
import '../models/time_models.dart';
import '../models/time_policy_models.dart';
import '../models/time_privacy_models.dart';
import '../models/work_models.dart';
import '../util/dates.dart';

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
  ///
  /// How it counts is settled here and nowhere else: [patchTimer] sends the
  /// timer's whole *editable* state, so a mode carried there would be cleared by
  /// every rename.
  Future<RunningTimer> startTimer({
    String? projectId,
    String? issueId,
    String? description,
    String? activityType,
    List<String> tags = const [],
    bool? billable,
    TimerMode mode = TimerMode.stopwatch,
    int? plannedMinutes,
    PomodoroConfig? pomodoro,
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
                'mode': mode.wire,
                // Only where the mode counts towards it. The server drops the
                // other two anyway; sending them would just make the request say
                // something it does not mean.
                if (mode == TimerMode.countdown)
                  'plannedMinutes': ?plannedMinutes,
                if (mode == TimerMode.pomodoro && pomodoro != null)
                  'pomodoro': pomodoro.toJson(),
              },
            )
            as Map<String, dynamic>;
    return RunningTimer.fromJson(data);
  }

  /// Ends the running pomodoro phase and answers with the one that follows.
  ///
  /// A work phase becomes an entry on the way; a break becomes nothing. Safe to
  /// repeat when [timerId] names the phase being ended: a retry that arrives
  /// after the phase has already turned answers with the phase that is running
  /// rather than skipping the next one.
  Future<RunningTimer> advancePhase({String? timerId}) async {
    final data =
        await _api.post('/api/v1/me/timer/phase', body: {'timerId': ?timerId})
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
    DateTime? endedAt,
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
                // When the button was pressed. Omitted, the server ends the
                // timer when the request lands — which is the same instant
                // unless something happened in between, and something does: a
                // stop that has to ask for a required field waits for it to be
                // typed, and the minutes spent typing are not minutes worked.
                // The server still decides the length: it clamps an end past a
                // countdown's target or past the run ceiling.
                'endedAt': ?endedAt?.toUtc().toIso8601String(),
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

  // --- the grid views --------------------------------------------------------

  /// Everything the caller logged inside a window, for the calendar to draw.
  ///
  /// A window, not a page: a grid places the whole range or places nothing. The
  /// server bounds it instead — a month wide at most, and a cap on the entries
  /// with [CalendarWindow.truncated] when it was reached.
  Future<CalendarWindow> calendar(DateTime from, DateTime to) async {
    final data =
        await _api.get(
              '/api/v1/time/calendar',
              query: {'from': formatDateOnly(from), 'to': formatDateOnly(to)},
            )
            as Map<String, dynamic>;
    return CalendarWindow.fromJson(data);
  }

  /// One page of the timesheet matrix: a row per person and project, its days
  /// as columns.
  ///
  /// The module's own route rather than the 1.x `/timesheet`, which answers with
  /// every row at once. Same scope either way — a non-admin gets their own rows
  /// and naming somebody else is refused, not quietly narrowed.
  Future<PageResult<TimesheetRow>> timesheet({
    required DateTime from,
    required DateTime to,
    String? userId,
    String? projectId,
    int page = 0,
    int size = 50,
  }) async {
    final data =
        await _api.get(
              '/api/v1/time/timesheet',
              query: {
                'from': formatDateOnly(from),
                'to': formatDateOnly(to),
                'userId': ?userId,
                'projectId': ?projectId,
                'page': page,
                'size': size,
              },
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? const [])
          .map((e) => TimesheetRow.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  // --- the rules everyone is held to -----------------------------------------

  /// What the operator's policies currently demand.
  ///
  /// Read once when the module comes up rather than per screen: it changes when
  /// an administrator saves the settings, which is rare, and every editor needs
  /// it before it can mark a field required or a day frozen.
  Future<TimePolicySnapshot> policy() async {
    final data = await _api.get('/api/v1/time/policy');
    if (data is! Map<String, dynamic>) return TimePolicySnapshot.none;
    return TimePolicySnapshot.fromJson(data);
  }

  /// What has been recorded about one entry, newest first.
  Future<PageResult<TimeEntryHistoryEntry>> history(
    String id, {
    int page = 0,
    int size = 50,
  }) async {
    final data =
        await _api.get(
              '/api/v1/time/entries/$id/history',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? const [])
          .map((e) => TimeEntryHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  // --- handing periods in ---------------------------------------------------------

  /// The periods overlapping a window, and where the reader stands in each.
  ///
  /// The app computes **no** period arithmetic of its own: which days "March" or
  /// "CW 12" covers is the server's, in one place, because two implementations
  /// would disagree on exactly one day a year and nobody would notice until a
  /// payroll period was short.
  ///
  /// [projectId] asks about one project's rhythm — which is what the filtered
  /// timesheet does; asking about none asks about the instance's.
  Future<List<ApprovalPeriod>> approvalPeriods({
    required DateTime from,
    required DateTime to,
    String? projectId,
  }) async {
    final data =
        await _api.get(
              '/api/v1/time/approvals/periods',
              query: {
                'from': formatDateOnly(from),
                'to': formatDateOnly(to),
                'projectId': ?projectId,
              },
            )
            as List<dynamic>;
    return data
        .map((p) => ApprovalPeriod.fromJson(p as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Hands a span in — one submission per project that has hours in it.
  Future<List<TimesheetApproval>> submitPeriod({
    required DateTime periodStart,
    required DateTime periodEnd,
    List<String>? projectIds,
  }) async {
    final data =
        await _api.post(
              '/api/v1/time/approvals/submit',
              body: {
                'periodStart': formatDateOnly(periodStart),
                'periodEnd': formatDateOnly(periodEnd),
                if (projectIds != null && projectIds.isNotEmpty)
                  'projectIds': projectIds,
              },
            )
            as List<dynamic>;
    return data
        .map((a) => TimesheetApproval.fromJson(a as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Takes a submission back. The submitter's own act, and only while pending.
  Future<TimesheetApproval> withdrawApproval(String id) async =>
      _approval(await _api.post('/api/v1/time/approvals/$id/withdraw'));

  /// Signs a period off. A reason is optional here and required for a rejection.
  Future<TimesheetApproval> approve(String id, {String? note}) async =>
      _approval(
        await _api.post(
          '/api/v1/time/approvals/$id/approve',
          body: {'note': ?note},
        ),
      );

  /// Sends a period back. The server refuses a blank reason, on purpose: "no" on
  /// its own is not something the person on the other end can act on.
  Future<TimesheetApproval> reject(String id, {required String note}) async =>
      _approval(
        await _api.post(
          '/api/v1/time/approvals/$id/reject',
          body: {'note': note},
        ),
      );

  /// Takes an approved period back so it can be corrected, with a reason.
  Future<TimesheetApproval> reopen(String id, {required String note}) async =>
      _approval(
        await _api.post(
          '/api/v1/time/approvals/$id/reopen',
          body: {'note': note},
        ),
      );

  /// One page of submissions: the reader's own (`mine`) or theirs to decide
  /// (`inbox`).
  Future<PageResult<TimesheetApproval>> approvals({
    String scope = 'mine',
    ApprovalStatus? status,
    int page = 0,
    int size = 25,
  }) async {
    final data =
        await _api.get(
              '/api/v1/time/approvals',
              query: {
                'scope': scope,
                'status': ?status?.name.toUpperCase(),
                'page': page,
                'size': size,
              },
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? const [])
          .map((a) => TimesheetApproval.fromJson(a as Map<String, dynamic>))
          .toList(),
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  /// The entries a submission covers — what an approver actually reads.
  Future<PageResult<WorkItem>> approvalEntries(
    String id, {
    int page = 0,
    int size = 25,
  }) async {
    final data =
        await _api.get(
              '/api/v1/time/approvals/$id/entries',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? const [])
          .map((e) => WorkItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  /// Asks for a frozen entry of one's own to be opened.
  ///
  /// Changes nothing by itself — that is the point of it. The request reaches
  /// whoever can actually lift the freeze and is recorded, so it cannot be lost
  /// in a chat.
  Future<void> requestCorrection(String entryId, String note) => _api.post(
    '/api/v1/time/entries/$entryId/correction-request',
    body: {'note': note},
  );

  /// The correction requests the reader can answer, newest first: every one for
  /// an administrator, the ones about submitted periods of their projects for a
  /// lead, none for anybody else.
  Future<PageResult<TimeCorrectionRequest>> correctionRequests({
    int page = 0,
    int size = 25,
  }) async {
    final data =
        await _api.get(
              '/api/v1/time/correction-requests',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? const [])
          .map((e) => TimeCorrectionRequest.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  /// Answers one request with a sentence the person who asked will read. Once.
  Future<TimeCorrectionRequest> answerCorrection(String id, String note) async =>
      TimeCorrectionRequest.fromJson(
        await _api.post(
              '/api/v1/time/correction-requests/$id/answer',
              body: {'note': note},
            )
            as Map<String, dynamic>,
      );

  /// Answers a request by opening the days for the person who asked, with a
  /// reason they will read. Administrators only; the days close again by
  /// themselves after two weeks.
  Future<TimeCorrectionRequest> grantCorrection(String id, String note) async =>
      TimeCorrectionRequest.fromJson(
        await _api.post(
              '/api/v1/time/correction-requests/$id/grant',
              body: {'note': note},
            )
            as Map<String, dynamic>,
      );

  /// The reader's own requests about one of their entries, newest first, with
  /// the answers — so they can read them where they look for them.
  Future<List<TimeCorrectionRequest>> entryCorrectionRequests(
    String entryId,
  ) async {
    final data =
        await _api.get('/api/v1/time/entries/$entryId/correction-requests')
            as List<dynamic>;
    return data
        .map((e) => TimeCorrectionRequest.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Asks the administrators to open days that cannot be recorded yet: beyond
  /// `maxDaysBack`, or before the lock date.
  ///
  /// There is no entry to ask a correction about, so the request names the span.
  /// Opening it stays the administrator's audited act.
  Future<void> requestBackfill({
    required DateTime from,
    required DateTime to,
    required String note,
  }) => _api.post(
    '/api/v1/time/backfill-requests',
    body: {
      'from': formatDateOnly(from),
      'to': formatDateOnly(to),
      'note': note,
    },
  );

  /// The days opened for people that are still open, newest first.
  /// Administrators only.
  Future<PageResult<TimeBackfillGrant>> backfillGrants({
    int page = 0,
    int size = 25,
  }) async {
    final data =
        await _api.get(
              '/api/v1/time/backfill-grants',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: [
        for (final raw in (data['content'] as List<dynamic>?) ?? const [])
          ?TimeBackfillGrant.fromJson(raw as Map<String, dynamic>),
      ],
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  /// Closes days opened for a person before they run out. Recorded.
  Future<void> revokeBackfillGrant(String id) =>
      _api.delete('/api/v1/time/backfill-grants/$id');

  // --- being told, and taking a copy -----------------------------------------------

  /// The privacy notice and who can see the reader's time, computed on the server.
  Future<TimePrivacy> privacy() async => TimePrivacy.fromJson(
    await _api.get('/api/v1/time/privacy') as Map<String, dynamic>,
  );

  /// Records that the reader has seen the notice. The first moment is kept.
  Future<TimePrivacy> acknowledgePrivacy() async => TimePrivacy.fromJson(
    await _api.post('/api/v1/time/privacy/acknowledge') as Map<String, dynamic>,
  );

  /// The reader's own self-hints for a window of at most 31 days.
  ///
  /// Hints of a kind this build has no words for are dropped here, so no screen
  /// has to guard against a raw key.
  Future<List<TimeHint>> hints(DateTime from, DateTime to) async {
    final data =
        await _api.get(
              '/api/v1/time/hints',
              query: {'from': formatDateOnly(from), 'to': formatDateOnly(to)},
            )
            as Map<String, dynamic>;
    return [
      for (final raw in (data['hints'] as List<dynamic>?) ?? const [])
        if (TimeHint.fromJson(raw as Map<String, dynamic>) case final hint?)
          if (hint.isKnown) hint,
    ];
  }

  /// The reader's own entries as a CSV file (UTF-8 with BOM), held in memory.
  ///
  /// For the web, which has no path to stream a file to; everywhere else
  /// [exportCsvTo] writes it straight to disk. [truncated] says the server
  /// stopped at its row limit.
  Future<({Uint8List bytes, bool truncated})> exportCsv({
    DateTime? from,
    DateTime? to,
  }) async {
    final file = await _api.getFile(
      _csvPath(from, to),
      receiveTimeout: const Duration(minutes: 2),
    );
    return (bytes: file.bytes, truncated: _truncated(file.header));
  }

  /// The same file written straight to [path], so tens of megabytes never sit in
  /// memory. Answers whether the server stopped at its row limit.
  Future<bool> exportCsvTo(String path, {DateTime? from, DateTime? to}) async {
    final header = await _api.downloadTo(
      _csvPath(from, to),
      path,
      receiveTimeout: const Duration(minutes: 5),
    );
    return _truncated(header);
  }

  static String _csvPath(DateTime? from, DateTime? to) {
    final query = [
      if (from != null) 'from=${formatDateOnly(from)}',
      if (to != null) 'to=${formatDateOnly(to)}',
    ].join('&');
    return '/api/v1/time/export.csv${query.isEmpty ? '' : '?$query'}';
  }

  /// Whether the server says the file stops at its row limit.
  static bool _truncated(String? Function(String name) header) =>
      header('x-export-truncated') == 'true';

  TimesheetApproval _approval(Object? data) =>
      TimesheetApproval.fromJson(data as Map<String, dynamic>);

  // --- the way back out of the lock date --------------------------------------------

  /// Reopens a span inside the freeze, with a reason. Administrators only.
  ///
  /// Answers with the exceptions as they now stand, so the admin screen needs no
  /// second request. There is no GET: members read them from the policy, and the
  /// admin screen already holds the stored settings block it is editing.
  Future<List<TimeLockException>> addLockException({
    required DateTime from,
    required DateTime to,
    required String note,
  }) async {
    final data =
        await _api.post(
              '/api/v1/time/lock-exceptions',
              body: {
                'from': formatDateOnly(from),
                'to': formatDateOnly(to),
                'note': note,
              },
            )
            as List<dynamic>;
    return _exceptions(data);
  }

  Future<List<TimeLockException>> removeLockException(String id) async {
    final data =
        await _api.delete('/api/v1/time/lock-exceptions/$id') as List<dynamic>;
    return _exceptions(data);
  }

  List<TimeLockException> _exceptions(List<dynamic> data) => data
      .map((e) => TimeLockException.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);

  // --- the tag catalogue -------------------------------------------------------

  /// One page of the catalogue, narrowed by a prefix.
  ///
  /// [withUsage] asks the server to count the entries carrying each tag — one
  /// count per row over the entries collection, which the admin screen needs
  /// before renaming or deleting one and the picker must never ask for.
  Future<PageResult<TimeTag>> tags({
    String? query,
    int page = 0,
    int size = 50,
    bool withUsage = false,
  }) async {
    final data =
        await _api.get(
              '/api/v1/time/tags',
              query: {
                'q': ?query,
                'page': page,
                'size': size,
                if (withUsage) 'withUsage': true,
              },
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? const [])
          .map((e) => TimeTag.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  Future<TimeTag> createTag(String name, {int? hue}) async {
    final data =
        await _api.post('/api/v1/time/tags', body: {'name': name, 'hue': ?hue})
            as Map<String, dynamic>;
    return TimeTag.fromJson(data);
  }

  /// Renames or recolours a tag. The answer carries how many entries moved with
  /// it, which is what the confirmation says.
  Future<TimeTag> updateTag(String id, {String? name, int? hue}) async {
    final data =
        await _api.patch(
              '/api/v1/time/tags/$id',
              body: {'name': ?name, 'hue': ?hue},
            )
            as Map<String, dynamic>;
    return TimeTag.fromJson(data);
  }

  Future<void> deleteTag(String id) => _api.delete('/api/v1/time/tags/$id');

  // --- one project's own settings ------------------------------------------------

  Future<ProjectTimeSettings> projectSettings(String projectId) async {
    final data = await _api.get('/api/v1/projects/$projectId/time-settings');
    if (data is! Map<String, dynamic>) return const ProjectTimeSettings();
    return ProjectTimeSettings.fromJson(data);
  }

  /// Replaces the whole block: an omitted field means "no override", and a PATCH
  /// could not say that.
  Future<ProjectTimeSettings> saveProjectSettings(
    String projectId,
    ProjectTimeSettings settings,
  ) async {
    final data =
        await _api.put(
              '/api/v1/projects/$projectId/time-settings',
              body: settings.toJson(),
            )
            as Map<String, dynamic>;
    return ProjectTimeSettings.fromJson(data);
  }

  /// Starts a timer carrying an existing entry's description and placement.
  Future<RunningTimer> continueEntry(String id) async {
    final data =
        await _api.post('/api/v1/time/entries/$id/continue')
            as Map<String, dynamic>;
    return RunningTimer.fromJson(data);
  }
}
