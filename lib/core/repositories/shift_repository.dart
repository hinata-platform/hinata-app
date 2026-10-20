import '../api/api_client.dart';
import '../blocs/paged_cubit.dart';
import '../models/shift_models.dart';

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
}
