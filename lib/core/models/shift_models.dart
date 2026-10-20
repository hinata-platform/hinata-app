/// The shift planning module's domain models (HIN-27).
///
/// Mirrors the server's `shifts.ShiftReads` records. Every field a later
/// stage adds is read leniently: a missing one falls back to a neutral value
/// instead of failing the whole page, so an app a release ahead of its server
/// (or behind it) still draws what it has.
///
/// Times come twice: [Shift.startsAt] is the instant, [Shift.startsLocal] is
/// the wall clock in the event's own zone as the server computed it. The app
/// shows the second and never converts, so it carries no zone database.
library;

import 'package:equatable/equatable.dart';

import '../util/dates.dart';

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? [for (final item in value) _map(item)]
    : const <Map<String, dynamic>>[];

int _int(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

int? _intOrNull(Object? value) => value is num ? value.toInt() : null;

bool _bool(Object? value, [bool fallback = false]) =>
    value is bool ? value : fallback;

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// A wall-clock time as the server wrote it (`2026-10-24T18:00:00`), kept
/// naive: no zone, no conversion. Null for anything else.
DateTime? parseLocalWallClock(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  // A stray offset would make Dart convert it; keep only what the string says.
  return DateTime(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
  );
}

/// What a person's place on a shift currently is.
enum ShiftAssignmentStatus {
  /// Put on the shift by a planner, not yet confirmed.
  assigned,

  /// Confirmed by the person, or signed up by themselves.
  confirmed,

  /// Said no to a planner's assignment.
  declined,

  /// Given up, or taken off by a planner.
  released,

  /// On the waiting list (HIN-162).
  waiting,

  /// A status this app does not know yet.
  unknown;

  static ShiftAssignmentStatus parse(Object? value) => switch (value) {
    'ASSIGNED' => assigned,
    'CONFIRMED' => confirmed,
    'DECLINED' => declined,
    'RELEASED' => released,
    'WAITING' => waiting,
    _ => unknown,
  };

  String get wire => name.toUpperCase();

  /// Whether the person holds the place.
  bool get active => this == assigned || this == confirmed;
}

/// The four ways a shift can be staffed, as the coverage hex draws them.
enum CoverageState {
  /// Fewer people than needed.
  under,

  /// Exactly as many as needed.
  met,

  /// More than needed, below the upper limit.
  over,

  /// At the upper limit: nobody else can join.
  full,
}

/// How many people a shift has, needs and takes.
class Coverage extends Equatable {
  const Coverage({required this.assigned, required this.required, this.max});

  final int assigned;
  final int required;

  /// The upper limit; null means open.
  final int? max;

  CoverageState get state {
    final cap = max;
    if (cap != null && assigned >= cap) return CoverageState.full;
    if (assigned < required) return CoverageState.under;
    if (assigned > required) return CoverageState.over;
    return CoverageState.met;
  }

  /// People still missing towards the need.
  int get missing => (required - assigned).clamp(0, required);

  /// How full the cell is drawn, 0 to 1. A need of zero is a full cell.
  double get fill =>
      required <= 0 ? 1.0 : (assigned / required).clamp(0.0, 1.0);

  @override
  List<Object?> get props => [assigned, required, max];
}

/// A person named once per answer (`users` map).
class ShiftUser extends Equatable {
  const ShiftUser({required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;

  factory ShiftUser.fromJson(Map<String, dynamic> json) => ShiftUser(
    name: _text(json['name']) ?? '',
    avatarUrl: _text(json['avatarUrl']),
  );

  static Map<String, ShiftUser> mapFromJson(Object? value) => {
    for (final entry in _map(value).entries)
      if (entry.value is Map<String, dynamic>)
        entry.key: ShiftUser.fromJson(entry.value as Map<String, dynamic>),
  };

  @override
  List<Object?> get props => [name, avatarUrl];
}

/// One shift (`ShiftResponse`).
class Shift extends Equatable {
  const Shift({
    required this.id,
    required this.eventId,
    required this.projectId,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.startsLocal,
    required this.endsLocal,
    required this.requiredHelpers,
    this.maxHelpers,
    required this.assignedCount,
    this.understaffed = false,
    this.full = false,
    this.mine = false,
    this.cancelled = false,
    this.assigneeIds = const [],
    this.myAssignmentId,
    this.myStatus,
  });

  final String id;
  final String eventId;
  final String projectId;
  final String title;

  /// The instants, in the device's zone (for "in 18 hours").
  final DateTime startsAt;
  final DateTime endsAt;

  /// The wall clock in the event's zone, as the server computed it.
  final DateTime startsLocal;
  final DateTime endsLocal;

  final int requiredHelpers;
  final int? maxHelpers;
  final int assignedCount;
  final bool understaffed;
  final bool full;
  final bool mine;
  final bool cancelled;

  /// Who is on it, in detail answers only (lists carry the count).
  final List<String> assigneeIds;

  /// The caller's own place on it, where the server says so. Optional on the
  /// wire; see [ShiftDetail.myAssignment].
  final String? myAssignmentId;
  final ShiftAssignmentStatus? myStatus;

  Coverage get coverage => Coverage(
    assigned: assignedCount,
    required: requiredHelpers,
    max: maxHelpers,
  );

  Duration get duration => endsAt.difference(startsAt);

  factory Shift.fromJson(Map<String, dynamic> json) {
    final startsAt = parseInstant(json['startsAt']) ?? DateTime(1970);
    final endsAt = parseInstant(json['endsAt']) ?? startsAt;
    final my = _map(json['myAssignment']);
    return Shift(
      id: json['id'] as String? ?? '',
      eventId: json['eventId'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      startsAt: startsAt,
      endsAt: endsAt,
      startsLocal: parseLocalWallClock(json['startsLocal']) ?? startsAt,
      endsLocal: parseLocalWallClock(json['endsLocal']) ?? endsAt,
      requiredHelpers: _int(json['requiredHelpers'], 1),
      maxHelpers: _intOrNull(json['maxHelpers']),
      assignedCount: _int(json['assignedCount']),
      understaffed: _bool(json['understaffed']),
      full: _bool(json['full']),
      mine: _bool(json['mine']),
      cancelled: _bool(json['cancelled']),
      assigneeIds: [
        for (final id in (json['assigneeIds'] as List?) ?? const [])
          if (id is String) id,
      ],
      myAssignmentId: _text(json['myAssignmentId']) ?? _text(my['id']),
      myStatus: json['myStatus'] != null || my['status'] != null
          ? ShiftAssignmentStatus.parse(json['myStatus'] ?? my['status'])
          : null,
    );
  }

  /// What the offline snapshot keeps: no ids of other people.
  Map<String, dynamic> toSnapshotJson() => {
    'id': id,
    'eventId': eventId,
    'projectId': projectId,
    'title': title,
    'startsAt': startsAt.toUtc().toIso8601String(),
    'endsAt': endsAt.toUtc().toIso8601String(),
    'startsLocal': _wallClock(startsLocal),
    'endsLocal': _wallClock(endsLocal),
    'requiredHelpers': requiredHelpers,
    'maxHelpers': maxHelpers,
    'assignedCount': assignedCount,
    'understaffed': understaffed,
    'full': full,
    'mine': mine,
    'cancelled': cancelled,
  };

  Shift copyWith({
    int? assignedCount,
    bool? understaffed,
    bool? full,
    bool? mine,
    String? myAssignmentId,
    ShiftAssignmentStatus? myStatus,
    bool clearMine = false,
  }) => Shift(
    id: id,
    eventId: eventId,
    projectId: projectId,
    title: title,
    startsAt: startsAt,
    endsAt: endsAt,
    startsLocal: startsLocal,
    endsLocal: endsLocal,
    requiredHelpers: requiredHelpers,
    maxHelpers: maxHelpers,
    assignedCount: assignedCount ?? this.assignedCount,
    understaffed: understaffed ?? this.understaffed,
    full: full ?? this.full,
    mine: mine ?? this.mine,
    cancelled: cancelled,
    assigneeIds: assigneeIds,
    myAssignmentId: clearMine ? null : (myAssignmentId ?? this.myAssignmentId),
    myStatus: clearMine ? null : (myStatus ?? this.myStatus),
  );

  @override
  List<Object?> get props => [
    id,
    eventId,
    projectId,
    title,
    startsAt,
    endsAt,
    startsLocal,
    endsLocal,
    requiredHelpers,
    maxHelpers,
    assignedCount,
    understaffed,
    full,
    mine,
    cancelled,
    assigneeIds,
    myAssignmentId,
    myStatus,
  ];
}

String _wallClock(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// What a row pointing at an event needs (`EventHead`).
class ShiftEventHead extends Equatable {
  const ShiftEventHead({
    required this.id,
    required this.title,
    this.location,
    this.timezone,
    this.selfAssignable = true,
    this.cancelled = false,
  });

  final String id;
  final String title;
  final String? location;
  final String? timezone;
  final bool selfAssignable;
  final bool cancelled;

  factory ShiftEventHead.fromJson(Map<String, dynamic> json) => ShiftEventHead(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    location: _text(json['location']),
    timezone: _text(json['timezone']),
    selfAssignable: _bool(json['selfAssignable'], true),
    cancelled: _bool(json['cancelled']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'location': location,
    'timezone': timezone,
    'selfAssignable': selfAssignable,
    'cancelled': cancelled,
  };

  @override
  List<Object?> get props => [
    id,
    title,
    location,
    timezone,
    selfAssignable,
    cancelled,
  ];
}

/// An event in a list (`EventSummary`).
class ShiftEventSummary extends Equatable {
  const ShiftEventSummary({
    required this.id,
    required this.projectId,
    required this.title,
    this.description,
    this.location,
    required this.startsAt,
    required this.endsAt,
    required this.startsLocal,
    required this.endsLocal,
    this.timezone,
    this.cancelled = false,
    this.selfAssignable = true,
    this.placesRequired = 0,
    this.placesTaken = 0,
    this.shiftsUnderstaffed = 0,
    this.mineCount = 0,
    this.canPlan = false,
  });

  final String id;
  final String projectId;
  final String title;
  final String? description;
  final String? location;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime startsLocal;
  final DateTime endsLocal;
  final String? timezone;
  final bool cancelled;
  final bool selfAssignable;

  /// Places the live shifts need, and those taken towards it (a shift over its
  /// need counts as met, not as more).
  final int placesRequired;
  final int placesTaken;
  final int shiftsUnderstaffed;
  final int mineCount;
  final bool canPlan;

  Coverage get coverage =>
      Coverage(assigned: placesTaken, required: placesRequired);

  factory ShiftEventSummary.fromJson(Map<String, dynamic> json) {
    final startsAt = parseInstant(json['startsAt']) ?? DateTime(1970);
    final endsAt = parseInstant(json['endsAt']) ?? startsAt;
    return ShiftEventSummary(
      id: json['id'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: _text(json['description']),
      location: _text(json['location']),
      startsAt: startsAt,
      endsAt: endsAt,
      startsLocal: parseLocalWallClock(json['startsLocal']) ?? startsAt,
      endsLocal: parseLocalWallClock(json['endsLocal']) ?? endsAt,
      timezone: _text(json['timezone']),
      cancelled: _bool(json['cancelled']),
      selfAssignable: _bool(json['selfAssignable'], true),
      placesRequired: _int(json['placesRequired']),
      placesTaken: _int(json['placesTaken']),
      shiftsUnderstaffed: _int(json['shiftsUnderstaffed']),
      mineCount: _int(json['mineCount']),
      canPlan: _bool(json['canPlan']),
    );
  }

  @override
  List<Object?> get props => [
    id,
    projectId,
    title,
    description,
    location,
    startsAt,
    endsAt,
    startsLocal,
    endsLocal,
    timezone,
    cancelled,
    selfAssignable,
    placesRequired,
    placesTaken,
    shiftsUnderstaffed,
    mineCount,
    canPlan,
  ];
}

/// An event with its shifts and the people on them (`EventResponse`).
class ShiftEventDetail extends Equatable {
  const ShiftEventDetail({
    required this.summary,
    this.shifts = const [],
    this.users = const {},
  });

  final ShiftEventSummary summary;
  final List<Shift> shifts;
  final Map<String, ShiftUser> users;

  factory ShiftEventDetail.fromJson(Map<String, dynamic> json) =>
      ShiftEventDetail(
        summary: ShiftEventSummary.fromJson(json),
        shifts: [for (final s in _maps(json['shifts'])) Shift.fromJson(s)],
        users: ShiftUser.mapFromJson(json['users']),
      );

  ShiftEventDetail withShift(Shift shift) => ShiftEventDetail(
    summary: summary,
    shifts: [for (final s in shifts) s.id == shift.id ? shift : s],
    users: users,
  );

  @override
  List<Object?> get props => [summary, shifts, users];
}

/// The caller's own place on a shift, as a detail answer may carry it.
class ShiftAssignmentRef extends Equatable {
  const ShiftAssignmentRef({required this.id, required this.status});

  final String id;
  final ShiftAssignmentStatus status;

  static ShiftAssignmentRef? fromJson(Object? value) {
    final json = _map(value);
    final id = _text(json['id']) ?? _text(json['assignmentId']);
    if (id == null) return null;
    return ShiftAssignmentRef(
      id: id,
      status: ShiftAssignmentStatus.parse(json['status']),
    );
  }

  @override
  List<Object?> get props => [id, status];
}

/// One shift with its event and the people on it (`ShiftDetail`).
class ShiftDetail extends Equatable {
  const ShiftDetail({
    required this.shift,
    required this.event,
    this.users = const {},
    this.canPlan = false,
    this.myAssignment,
  });

  final Shift shift;
  final ShiftEventHead event;
  final Map<String, ShiftUser> users;
  final bool canPlan;

  /// The caller's own place, when the server names it. Falls back to what the
  /// shift row says ([Shift.myAssignmentId]).
  final ShiftAssignmentRef? myAssignment;

  factory ShiftDetail.fromJson(Map<String, dynamic> json) {
    final shift = Shift.fromJson(_map(json['shift']));
    final mine =
        ShiftAssignmentRef.fromJson(json['myAssignment']) ??
        (shift.myAssignmentId == null
            ? null
            : ShiftAssignmentRef(
                id: shift.myAssignmentId!,
                status: shift.myStatus ?? ShiftAssignmentStatus.unknown,
              ));
    return ShiftDetail(
      shift: shift,
      event: ShiftEventHead.fromJson(_map(json['event'])),
      users: ShiftUser.mapFromJson(json['users']),
      canPlan: _bool(json['canPlan']),
      myAssignment: mine,
    );
  }

  @override
  List<Object?> get props => [shift, event, users, canPlan, myAssignment];
}

/// One of the caller's own places (`MyShiftResponse`).
class MyShift extends Equatable {
  const MyShift({
    required this.assignmentId,
    required this.status,
    this.assignedBy,
    required this.shift,
    required this.event,
  });

  final String assignmentId;
  final ShiftAssignmentStatus status;

  /// Who put the person on it; null when they signed up themselves.
  final String? assignedBy;
  final Shift shift;
  final ShiftEventHead event;

  factory MyShift.fromJson(Map<String, dynamic> json) => MyShift(
    assignmentId: json['assignmentId'] as String? ?? '',
    status: ShiftAssignmentStatus.parse(json['status']),
    assignedBy: _text(json['assignedBy']),
    shift: Shift.fromJson(_map(json['shift'])),
    event: ShiftEventHead.fromJson(_map(json['event'])),
  );

  /// The snapshot form: nobody else's id, not even who assigned it.
  Map<String, dynamic> toSnapshotJson() => {
    'assignmentId': assignmentId,
    'status': status.wire,
    'shift': shift.toSnapshotJson(),
    'event': event.toJson(),
  };

  MyShift copyWith({ShiftAssignmentStatus? status, Shift? shift}) => MyShift(
    assignmentId: assignmentId,
    status: status ?? this.status,
    assignedBy: assignedBy,
    shift: shift ?? this.shift,
    event: event,
  );

  @override
  List<Object?> get props => [assignmentId, status, assignedBy, shift, event];
}

/// What signing up returned: the shift with its new count, the place, and the
/// hints for whoever asked (`absent` when the person is away that day).
class ShiftAssignResult extends Equatable {
  const ShiftAssignResult({
    required this.shift,
    this.assignment,
    this.warnings = const [],
  });

  final Shift shift;
  final ShiftAssignmentRef? assignment;
  final List<String> warnings;

  /// The person is entered as absent on that day (shown only to whoever may
  /// see the absence, which the server decides).
  bool get absent => warnings.contains('absent');

  factory ShiftAssignResult.fromJson(Map<String, dynamic> json) {
    final assignment = ShiftAssignmentRef.fromJson(json['assignment']);
    // The shift either sits under `shift` or is the body itself.
    final shiftJson = json['shift'] is Map<String, dynamic>
        ? json['shift'] as Map<String, dynamic>
        : json;
    final shift = Shift.fromJson(shiftJson);
    return ShiftAssignResult(
      // The caller's place rides on the shift while it is held; a release or
      // a decline answers with the same shape and a place that is gone.
      shift: assignment == null
          ? shift
          : assignment.status.active
          ? shift.copyWith(
              mine: true,
              myAssignmentId: assignment.id,
              myStatus: assignment.status,
            )
          : shift.copyWith(mine: false, clearMine: true),
      assignment: assignment,
      warnings: [
        for (final w in (json['warnings'] as List?) ?? const [])
          if (w is String) w,
      ],
    );
  }

  @override
  List<Object?> get props => [shift, assignment, warnings];
}

/// Shifts in a window with their events named once (`CalendarResponse`).
class ShiftCalendar extends Equatable {
  const ShiftCalendar({
    this.shifts = const [],
    this.events = const {},
    this.truncated = false,
  });

  final List<Shift> shifts;
  final Map<String, ShiftEventHead> events;
  final bool truncated;

  factory ShiftCalendar.fromJson(Map<String, dynamic> json) => ShiftCalendar(
    shifts: [for (final s in _maps(json['shifts'])) Shift.fromJson(s)],
    events: {
      for (final entry in _map(json['events']).entries)
        if (entry.value is Map<String, dynamic>)
          entry.key: ShiftEventHead.fromJson(
            entry.value as Map<String, dynamic>,
          ),
    },
    truncated: _bool(json['truncated']),
  );

  @override
  List<Object?> get props => [shifts, events, truncated];
}

/// One person who may plan a project's shifts (`shift_planners`).
class ShiftPlanner extends Equatable {
  const ShiftPlanner({required this.userId, this.grantedBy, this.createdAt});

  final String userId;
  final String? grantedBy;
  final DateTime? createdAt;

  factory ShiftPlanner.fromJson(Map<String, dynamic> json) => ShiftPlanner(
    userId: json['userId'] as String? ?? json['id'] as String? ?? '',
    grantedBy: _text(json['grantedBy']),
    createdAt: parseInstant(json['createdAt']),
  );

  @override
  List<Object?> get props => [userId, grantedBy, createdAt];
}

/// A project's planners and their names.
class ShiftPlanners extends Equatable {
  const ShiftPlanners({this.planners = const [], this.users = const {}});

  final List<ShiftPlanner> planners;
  final Map<String, ShiftUser> users;

  /// Reads a bare list, or an object with the list under `planners`, `items`
  /// or `content` beside an optional `users` map.
  factory ShiftPlanners.fromJson(Object? body) {
    if (body is List) {
      return ShiftPlanners(
        planners: [for (final p in _maps(body)) ShiftPlanner.fromJson(p)],
      );
    }
    final json = _map(body);
    final list = json['planners'] ?? json['items'] ?? json['content'];
    return ShiftPlanners(
      planners: [
        for (final p in _maps(list))
          if (p['userId'] != null || p['id'] != null) ShiftPlanner.fromJson(p),
      ],
      users: ShiftUser.mapFromJson(json['users']),
    );
  }

  @override
  List<Object?> get props => [planners, users];
}
