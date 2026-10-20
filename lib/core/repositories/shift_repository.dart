import '../api/api_client.dart';
import '../blocs/paged_cubit.dart';
import '../models/shift_models.dart';
import '../models/shift_plan_export.dart';
import '../models/shift_series.dart';

/// The shift planning module's data (HIN-27), behind `shift_planning`.
///
/// Abstract so the cubits and the screens can be tested against a fake; the
/// one implementation is [ApiShiftRepository]. Every route sits under one of
/// the module's gated prefixes, so with the flag off none of them is ever
/// asked: the screens that call these do not exist then.
abstract class ShiftRepository {
  /// The caller's own places from now on, oldest first.
  Future<PageResult<MyShift>> myShifts({int page = 0, int size = 25});

  /// The caller's next place, or null when there is none.
  Future<MyShift?> nextShift();

  /// The caller's places on waiting lists (HIN-162), by start, at most 50.
  Future<List<MyShift>> myWaitingShifts();

  /// Events touching [from] to [to], across every visible project or within
  /// [projectId].
  Future<PageResult<ShiftEventSummary>> events({
    required DateTime from,
    required DateTime to,
    String? projectId,
    int page = 0,
    int size = 25,
  });

  /// One event with its shifts.
  Future<ShiftEventDetail> event(String id);

  /// One shift with its event and the people on it.
  Future<ShiftDetail> shift(String id);

  /// Shifts in the caller's projects that still need people and take
  /// sign-ups, between [from] and [to], at most [limit].
  Future<ShiftCalendar> openShifts({
    required DateTime from,
    required DateTime to,
    int limit = 3,
  });

  /// Signs the caller up for [shiftId].
  Future<ShiftAssignResult> selfAssign(String shiftId);

  /// Confirms a planner's assignment.
  Future<MyShift> confirm(String assignmentId);

  /// Says no to a planner's assignment. The shift as it now stands, or null
  /// when the server answered without one.
  Future<ShiftAssignResult?> decline(String assignmentId);

  /// Gives a place up ("Abgeben"); answers like [decline].
  Future<ShiftAssignResult?> release(String assignmentId);

  /// Who may plan [projectId]'s shifts besides its leads.
  Future<ShiftPlanners> planners(String projectId);

  Future<void> addPlanner(String projectId, String userId);

  Future<void> removePlanner(String projectId, String userId);

  // --- planning (HIN-160) ---------------------------------------------------

  /// Every shift touching [from] to [to] (at most 62 days), across every
  /// visible project or within [projectId], with the projects the caller
  /// plans.
  Future<ShiftCalendar> calendar({
    required DateTime from,
    required DateTime to,
    String? projectId,
  });

  /// The projects the caller may plan, as far as the server says for a day's
  /// window. Empty for a helper.
  Future<Set<String>> plannableProjectIds();

  Future<ShiftEventDetail> createEvent(String projectId, ShiftEventInput input);

  // Every write below takes a [ShiftScope]; it is required (the server says
  // 400 `seriesScopeRequired` otherwise) as soon as the event is an
  // occurrence of a series, and ignored for any other event.

  /// Changes an event; [patch] holds only what changed. With
  /// [ShiftScope.future] the series is split here, and the answer carries the
  /// occurrence with its new `seriesId`.
  Future<ShiftEventChange> updateEvent(
    String id,
    Map<String, dynamic> patch, {
    ShiftScope? scope,
  });

  Future<ShiftEventDetail> cancelEvent(String id, {ShiftScope? scope});

  Future<void> deleteEvent(String id, {ShiftScope? scope});

  /// The same shift on each of [days] (wall-clock dates in the event's zone),
  /// all or none. A refusal names each failed day in its details. Only ever
  /// [ShiftScope.single]: a batch cannot change a series.
  Future<List<Shift>> createShifts(
    String eventId,
    ShiftInput template,
    List<DateTime> days, {
    ShiftScope? scope,
  });

  /// One new shift; with [ShiftScope.future] it also becomes a template of
  /// the series from this occurrence on.
  Future<Shift> createShift(
    String eventId,
    ShiftInput input, {
    ShiftScope? scope,
  });

  /// Changes a shift; [patch] holds only what changed.
  Future<ShiftEdit> updateShift(
    String id,
    Map<String, dynamic> patch, {
    ShiftScope? scope,
  });

  Future<void> deleteShift(String id, {ShiftScope? scope});

  // --- series (HIN-161) -----------------------------------------------------

  /// Creates a series and its occurrences of the first horizon.
  Future<ShiftSeries> createSeries(String projectId, SeriesDraft draft);

  /// What [draft] would make, in words and as the next five dates. Nothing is
  /// saved.
  Future<SeriesPreview> previewSeries(String projectId, SeriesDraft draft);

  /// One series with its next five occurrences.
  Future<ShiftSeries> series(String id);

  /// A planner puts [userId] on [shiftId]. Somebody waiting for it moves up
  /// ("Jetzt zuteilen", HIN-162).
  Future<ShiftAssignResult> assign(String shiftId, String userId);

  /// Who a planner can put on [projectId]'s shifts, matching [query] by name,
  /// at most [limit] (the server caps it at 50).
  Future<ShiftCandidates> candidates(
    String projectId, {
    String query = '',
    int limit = 50,
  });

  // --- export (HIN-163) -----------------------------------------------------

  /// The event's shift plan as a file in memory. [names] adds the people on
  /// each shift; only a planner may ask for it (403 otherwise).
  Future<ShiftPlanFile> exportPlan(
    String eventId,
    ShiftPlanFormat format, {
    bool names = false,
  });

  /// The same file written straight to [path]. Answers whether the server
  /// stopped at the format's ceiling.
  Future<bool> exportPlanTo(
    String eventId,
    ShiftPlanFormat format,
    String path, {
    bool names = false,
  });

  // --- the personal feed (HIN-47) -------------------------------------------

  Future<ShiftFeedStatus> feed();

  /// Makes a new feed address; an existing one stops working in the same step.
  Future<ShiftFeedAddress> createFeed();

  Future<void> deleteFeed();
}

/// [ShiftRepository] over the app's [ApiClient].
class ApiShiftRepository implements ShiftRepository {
  ApiShiftRepository(this._api);

  final ApiClient _api;

  static PageResult<T> _page<T>(
    Object? body,
    T Function(Map<String, dynamic>) read,
  ) {
    final json = body is Map<String, dynamic> ? body : const {};
    final rows = json['content'];
    final items = [
      if (rows is List)
        for (final row in rows)
          if (row is Map<String, dynamic>) read(row),
    ];
    return (
      items: items,
      total: (json['totalElements'] as num?)?.toInt() ?? items.length,
    );
  }

  static String _instant(DateTime t) => t.toUtc().toIso8601String();

  @override
  Future<PageResult<MyShift>> myShifts({int page = 0, int size = 25}) async =>
      _page(
        await _api.get(
          '/api/v1/me/shifts',
          query: {'page': page, 'size': size},
        ),
        MyShift.fromJson,
      );

  @override
  Future<MyShift?> nextShift() async {
    // 204 when there is none: no body at all.
    final body = await _api.get('/api/v1/me/shifts/next');
    if (body is! Map<String, dynamic> || body.isEmpty) return null;
    return MyShift.fromJson(body);
  }

  @override
  Future<List<MyShift>> myWaitingShifts() async {
    final body = await _api.get('/api/v1/me/shifts/waiting');
    return [
      if (body is List)
        for (final row in body)
          if (row is Map<String, dynamic>) MyShift.fromJson(row),
    ];
  }

  @override
  Future<PageResult<ShiftEventSummary>> events({
    required DateTime from,
    required DateTime to,
    String? projectId,
    int page = 0,
    int size = 25,
  }) async => _page(
    await _api.get(
      projectId == null
          ? '/api/v1/shifts/events'
          : '/api/v1/projects/${Uri.encodeComponent(projectId)}/shifts/events',
      query: {
        'from': _instant(from),
        'to': _instant(to),
        'page': page,
        'size': size,
      },
    ),
    ShiftEventSummary.fromJson,
  );

  @override
  Future<ShiftEventDetail> event(String id) async => ShiftEventDetail.fromJson(
    await _api.get('/api/v1/shifts/events/${Uri.encodeComponent(id)}')
        as Map<String, dynamic>,
  );

  @override
  Future<ShiftDetail> shift(String id) async => ShiftDetail.fromJson(
    await _api.get('/api/v1/shifts/shifts/${Uri.encodeComponent(id)}')
        as Map<String, dynamic>,
  );

  @override
  Future<ShiftCalendar> openShifts({
    required DateTime from,
    required DateTime to,
    int limit = 3,
  }) async => ShiftCalendar.fromJson(
    await _api.get(
          '/api/v1/shifts/calendar',
          query: {
            'from': _instant(from),
            'to': _instant(to),
            'understaffed': true,
            'selfAssignable': true,
            'limit': limit,
          },
        )
        as Map<String, dynamic>,
  );

  @override
  Future<ShiftAssignResult> selfAssign(
    String shiftId,
  ) async => ShiftAssignResult.fromJson(
    await _api.post(
          '/api/v1/shifts/shifts/${Uri.encodeComponent(shiftId)}/self-assign',
        )
        as Map<String, dynamic>,
  );

  @override
  Future<MyShift> confirm(String assignmentId) async => MyShift.fromJson(
    await _api.post(
          '/api/v1/shifts/assignments/${Uri.encodeComponent(assignmentId)}/confirm',
        )
        as Map<String, dynamic>,
  );

  @override
  Future<ShiftAssignResult?> decline(String assignmentId) async => _change(
    await _api.post(
      '/api/v1/shifts/assignments/${Uri.encodeComponent(assignmentId)}/decline',
    ),
  );

  @override
  Future<ShiftAssignResult?> release(String assignmentId) async => _change(
    await _api.post(
      '/api/v1/shifts/assignments/${Uri.encodeComponent(assignmentId)}/release',
    ),
  );

  static ShiftAssignResult? _change(Object? body) =>
      body is Map<String, dynamic> && body['shift'] is Map<String, dynamic>
      ? ShiftAssignResult.fromJson(body)
      : null;

  @override
  Future<ShiftPlanners> planners(String projectId) async =>
      ShiftPlanners.fromJson(
        await _api.get(
          '/api/v1/projects/${Uri.encodeComponent(projectId)}/shifts/planners',
        ),
      );

  @override
  Future<void> addPlanner(String projectId, String userId) => _api.post(
    '/api/v1/projects/${Uri.encodeComponent(projectId)}/shifts/planners',
    body: {'userId': userId},
  );

  @override
  Future<void> removePlanner(String projectId, String userId) => _api.delete(
    '/api/v1/projects/${Uri.encodeComponent(projectId)}/shifts/planners/'
    '${Uri.encodeComponent(userId)}',
  );

  static String _event(String id) =>
      '/api/v1/shifts/events/${Uri.encodeComponent(id)}';

  static String _shift(String id) =>
      '/api/v1/shifts/shifts/${Uri.encodeComponent(id)}';

  static String _scoped(String path, ShiftScope? scope) =>
      scope == null ? path : '$path?scope=${scope.wire}';

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Future<ShiftCalendar> calendar({
    required DateTime from,
    required DateTime to,
    String? projectId,
  }) async => ShiftCalendar.fromJson(
    await _api.get(
          '/api/v1/shifts/calendar',
          query: {
            'from': _instant(from),
            'to': _instant(to),
            'projectId': ?projectId,
          },
        )
        as Map<String, dynamic>,
  );

  @override
  Future<Set<String>> plannableProjectIds() async {
    final now = DateTime.now();
    final window = await _api.get(
      '/api/v1/shifts/calendar',
      query: {
        'from': _instant(now),
        'to': _instant(now.add(const Duration(days: 1))),
        'limit': 1,
      },
    );
    return ShiftCalendar.fromJson(
      window is Map<String, dynamic> ? window : const {},
    ).plannableProjectIds;
  }

  @override
  Future<ShiftEventDetail> createEvent(
    String projectId,
    ShiftEventInput input,
  ) async => ShiftEventDetail.fromJson(
    await _api.post(
          '/api/v1/projects/${Uri.encodeComponent(projectId)}/shifts/events',
          body: input.toDraftJson(),
        )
        as Map<String, dynamic>,
  );

  @override
  Future<ShiftEventChange> updateEvent(
    String id,
    Map<String, dynamic> patch, {
    ShiftScope? scope,
  }) async => ShiftEventChange.fromJson(
    await _api.patch(_scoped(_event(id), scope), body: patch)
        as Map<String, dynamic>,
  );

  @override
  Future<ShiftEventDetail> cancelEvent(String id, {ShiftScope? scope}) async =>
      ShiftEventDetail.fromJson(
        await _api.post(_scoped('${_event(id)}/cancel', scope))
            as Map<String, dynamic>,
      );

  @override
  Future<void> deleteEvent(String id, {ShiftScope? scope}) =>
      _api.delete(_scoped(_event(id), scope));

  @override
  Future<List<Shift>> createShifts(
    String eventId,
    ShiftInput template,
    List<DateTime> days, {
    ShiftScope? scope,
  }) async {
    final body = await _api.post(
      _scoped('${_event(eventId)}/shifts:batch', scope),
      body: {
        'template': template.toDraftJson(),
        'days': [for (final d in days) _day(d)],
      },
    );
    return [
      if (body is List)
        for (final row in body)
          if (row is Map<String, dynamic>) Shift.fromJson(row),
    ];
  }

  @override
  Future<Shift> createShift(
    String eventId,
    ShiftInput input, {
    ShiftScope? scope,
  }) async => Shift.fromJson(
    await _api.post(
          _scoped('${_event(eventId)}/shifts', scope),
          body: input.toDraftJson(),
        )
        as Map<String, dynamic>,
  );

  @override
  Future<ShiftEdit> updateShift(
    String id,
    Map<String, dynamic> patch, {
    ShiftScope? scope,
  }) async => ShiftEdit.fromJson(
    await _api.patch(_scoped(_shift(id), scope), body: patch)
        as Map<String, dynamic>,
  );

  @override
  Future<void> deleteShift(String id, {ShiftScope? scope}) =>
      _api.delete(_scoped(_shift(id), scope));

  static String _seriesOf(String projectId) =>
      '/api/v1/projects/${Uri.encodeComponent(projectId)}/shifts/series';

  @override
  Future<ShiftSeries> createSeries(String projectId, SeriesDraft draft) async =>
      ShiftSeries.fromJson(
        await _api.post(_seriesOf(projectId), body: draft.toJson())
            as Map<String, dynamic>,
      );

  @override
  Future<SeriesPreview> previewSeries(
    String projectId,
    SeriesDraft draft,
  ) async => SeriesPreview.fromJson(
    await _api.post('${_seriesOf(projectId)}:preview', body: draft.toJson())
        as Map<String, dynamic>,
  );

  @override
  Future<ShiftSeries> series(String id) async => ShiftSeries.fromJson(
    await _api.get('/api/v1/shifts/series/${Uri.encodeComponent(id)}')
        as Map<String, dynamic>,
  );

  @override
  Future<ShiftAssignResult> assign(String shiftId, String userId) async =>
      ShiftAssignResult.forOther(
        await _api.post(
              '${_shift(shiftId)}/assignments',
              body: {'userId': userId},
            )
            as Map<String, dynamic>,
      );

  @override
  Future<ShiftCandidates> candidates(
    String projectId, {
    String query = '',
    int limit = 50,
  }) async => ShiftCandidates.fromJson(
    await _api.get(
      '/api/v1/projects/${Uri.encodeComponent(projectId)}/shifts/candidates',
      query: {if (query.trim().isNotEmpty) 'q': query.trim(), 'limit': limit},
    ),
  );

  // --- export (HIN-163) -----------------------------------------------------

  static String _exportPath(
    String eventId,
    ShiftPlanFormat format,
    bool names,
  ) =>
      '/api/v1/shifts/events/${Uri.encodeComponent(eventId)}/export'
      '?format=${format.extension}&names=$names';

  @override
  Future<ShiftPlanFile> exportPlan(
    String eventId,
    ShiftPlanFormat format, {
    bool names = false,
  }) async {
    final file = await _api.getFile(
      _exportPath(eventId, format, names),
      receiveTimeout: const Duration(minutes: 3),
    );
    return ShiftPlanFile(
      bytes: file.bytes,
      truncated: file.header('x-export-truncated') == 'true',
      fileName: fileNameFromDisposition(file.header('content-disposition')),
    );
  }

  @override
  Future<bool> exportPlanTo(
    String eventId,
    ShiftPlanFormat format,
    String path, {
    bool names = false,
  }) async =>
      (await _api.downloadTo(
        _exportPath(eventId, format, names),
        path,
        receiveTimeout: const Duration(minutes: 5),
      ))('x-export-truncated') ==
      'true';

  @override
  Future<ShiftFeedStatus> feed() async =>
      ShiftFeedStatus.fromJson(await _api.get('/api/v1/me/shifts/feed'));

  @override
  Future<ShiftFeedAddress> createFeed() async =>
      ShiftFeedAddress.fromJson(await _api.post('/api/v1/me/shifts/feed'));

  @override
  Future<void> deleteFeed() => _api.delete('/api/v1/me/shifts/feed');
}
