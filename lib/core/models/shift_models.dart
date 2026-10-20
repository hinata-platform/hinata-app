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
    this.waitingCount = 0,
    this.myWaitPosition,
    this.myWaitAssignmentId,
    this.waitingIds = const [],
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

  /// How many people wait for a place (HIN-162), told to everybody who sees
  /// the shift.
  final int waitingCount;

  /// The caller's rank on the waiting list (1 is next), or null when they do
  /// not wait. A waiting person is never [mine].
  final int? myWaitPosition;

  /// The caller's waiting place, for leaving the list.
  final String? myWaitAssignmentId;

  /// Who waits, in order: only for a planner and only in detail answers; the
  /// names are in the answer's `users`.
  final List<String> waitingIds;

  /// The caller is on the waiting list.
  bool get waiting => myWaitPosition != null;

  Coverage get coverage => Coverage(
    assigned: assignedCount,
    required: requiredHelpers,
    max: maxHelpers,
  );

  /// Somebody is still missing. A cancelled shift never is: nobody is going
  /// to fill it. The one rule for every filter and list in the app.
  bool get isShort => coverage.state == CoverageState.under && !cancelled;

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
      myAssignmentId: _text(my['id']),
      myStatus: my['status'] != null
          ? ShiftAssignmentStatus.parse(my['status'])
          : null,
      waitingCount: _int(json['waitingCount']),
      myWaitPosition: _intOrNull(json['myWaitPosition']),
      myWaitAssignmentId: _text(json['myWaitAssignmentId']),
      waitingIds: [
        for (final id in (json['waitingIds'] as List?) ?? const [])
          if (id is String) id,
      ],
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
    'waitingCount': waitingCount,
    'myWaitPosition': myWaitPosition,
    'myWaitAssignmentId': myWaitAssignmentId,
  };

  Shift copyWith({
    int? assignedCount,
    bool? understaffed,
    bool? full,
    bool? mine,
    String? myAssignmentId,
    ShiftAssignmentStatus? myStatus,
    bool clearMine = false,
    int? waitingCount,
    int? myWaitPosition,
    String? myWaitAssignmentId,
    bool clearWait = false,
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
    waitingCount: waitingCount ?? this.waitingCount,
    myWaitPosition: clearWait ? null : (myWaitPosition ?? this.myWaitPosition),
    myWaitAssignmentId: clearWait
        ? null
        : (myWaitAssignmentId ?? this.myWaitAssignmentId),
    waitingIds: waitingIds,
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
    waitingCount,
    myWaitPosition,
    myWaitAssignmentId,
    waitingIds,
  ];
}

String _wallClock(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// Which occurrences of a series a write applies to (HIN-161). Every write to
/// an event with a series names one; the server refuses it otherwise.
enum ShiftScope {
  /// Only this occurrence, which then no longer follows its series.
  single('this'),

  /// This occurrence and every later one: the series is split here.
  future('future');

  const ShiftScope(this.wire);

  /// The value of the `scope` query parameter.
  final String wire;
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
    this.seriesId,
    this.recurrenceLabel,
    this.detached = false,
    this.projectId,
    this.startsAt,
    this.endsAt,
    this.startsLocal,
    this.endsLocal,
  });

  final String id;
  final String title;
  final String? location;
  final String? timezone;
  final bool selfAssignable;
  final bool cancelled;

  /// The event's project and span (HIN-166), so the calendar can tell which
  /// event a new shift falls into. Null from a server before it.
  final String? projectId;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// [startsAt] and [endsAt] as wall clocks in the event's zone.
  final DateTime? startsLocal;
  final DateTime? endsLocal;

  /// Whether the head names the event's project and span (HIN-166).
  bool get hasSpan => projectId != null && startsAt != null && endsAt != null;

  /// The series the event is an occurrence of (HIN-161), or null.
  final String? seriesId;

  /// The series' rule in the reader's words, as the server wrote it.
  final String? recurrenceLabel;

  /// An occurrence that no longer follows its series.
  final bool detached;

  /// Whether every write to it has to say its scope ([ShiftScope]).
  bool get inSeries => seriesId != null;

  factory ShiftEventHead.fromJson(Map<String, dynamic> json) => ShiftEventHead(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    location: _text(json['location']),
    timezone: _text(json['timezone']),
    selfAssignable: _bool(json['selfAssignable'], true),
    cancelled: _bool(json['cancelled']),
    seriesId: _text(json['seriesId']),
    recurrenceLabel: _text(json['recurrenceLabel']),
    detached: _bool(json['detached']),
    projectId: _text(json['projectId']),
    startsAt: parseInstant(json['startsAt']),
    endsAt: parseInstant(json['endsAt']),
    startsLocal: parseLocalWallClock(json['startsLocal']),
    endsLocal: parseLocalWallClock(json['endsLocal']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'location': location,
    'timezone': timezone,
    'selfAssignable': selfAssignable,
    'cancelled': cancelled,
    'seriesId': seriesId,
    'recurrenceLabel': recurrenceLabel,
    'detached': detached,
    if (projectId != null) 'projectId': projectId,
    if (startsAt != null) 'startsAt': startsAt!.toUtc().toIso8601String(),
    if (endsAt != null) 'endsAt': endsAt!.toUtc().toIso8601String(),
    if (startsLocal != null) 'startsLocal': _wallClock(startsLocal!),
    if (endsLocal != null) 'endsLocal': _wallClock(endsLocal!),
  };

  /// The head as the editors take an event (HIN-166); null without a span.
  /// [canPlan] is the caller's right on its project, which the head does not
  /// carry.
  ShiftEventSummary? toSummary({required bool canPlan}) {
    final project = projectId;
    final start = startsAt;
    final end = endsAt;
    if (project == null || start == null || end == null) return null;
    return ShiftEventSummary(
      id: id,
      projectId: project,
      title: title,
      location: location,
      startsAt: start,
      endsAt: end,
      startsLocal: startsLocal ?? start,
      endsLocal: endsLocal ?? end,
      timezone: timezone,
      cancelled: cancelled,
      selfAssignable: selfAssignable,
      canPlan: canPlan,
      seriesId: seriesId,
      recurrenceLabel: recurrenceLabel,
      detached: detached,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    location,
    timezone,
    selfAssignable,
    cancelled,
    seriesId,
    recurrenceLabel,
    detached,
    projectId,
    startsAt,
    endsAt,
    startsLocal,
    endsLocal,
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
    this.seriesId,
    this.recurrenceLabel,
    this.detached = false,
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

  /// See [ShiftEventHead.seriesId], [ShiftEventHead.recurrenceLabel] and
  /// [ShiftEventHead.detached].
  final String? seriesId;
  final String? recurrenceLabel;
  final bool detached;

  bool get inSeries => seriesId != null;

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
      seriesId: _text(json['seriesId']),
      recurrenceLabel: _text(json['recurrenceLabel']),
      detached: _bool(json['detached']),
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
    seriesId,
    recurrenceLabel,
    detached,
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
  const ShiftAssignmentRef({
    required this.id,
    required this.status,
    this.userId,
    this.confirmByLocal,
  });

  final String id;
  final ShiftAssignmentStatus status;

  /// Whose place it is, where the answer says (a write does).
  final String? userId;

  /// Until when a place that came off the waiting list has to be confirmed,
  /// as a wall clock in the event's zone (HIN-162); null otherwise.
  final DateTime? confirmByLocal;

  /// The place came off the waiting list and waits for a confirmation.
  bool get promoted =>
      status == ShiftAssignmentStatus.assigned && confirmByLocal != null;

  static ShiftAssignmentRef? fromJson(Object? value) {
    final json = _map(value);
    final id = _text(json['id']) ?? _text(json['assignmentId']);
    if (id == null) return null;
    return ShiftAssignmentRef(
      id: id,
      status: ShiftAssignmentStatus.parse(json['status']),
      userId: _text(json['userId']),
      confirmByLocal: parseLocalWallClock(json['confirmByLocal']),
    );
  }

  @override
  List<Object?> get props => [id, status, userId, confirmByLocal];
}

/// One shift with its event and the people on it (`ShiftDetail`).
class ShiftDetail extends Equatable {
  const ShiftDetail({
    required this.shift,
    required this.event,
    this.users = const {},
    this.canPlan = false,
    this.myAssignment,
    this.places = const [],
  });

  final Shift shift;
  final ShiftEventHead event;
  final Map<String, ShiftUser> users;
  final bool canPlan;

  /// Every active place with its id, for a planner to take somebody off the
  /// shift (HIN-160). The server sends `assignments` to planners only; for
  /// everybody else this is empty.
  final List<ShiftPlace> places;

  /// The place [userId] holds, or null.
  ShiftPlace? placeOf(String userId) {
    for (final place in places) {
      if (place.userId == userId) return place;
    }
    return null;
  }

  /// The caller's own place, from the shift's `myAssignment`.
  final ShiftAssignmentRef? myAssignment;

  factory ShiftDetail.fromJson(Map<String, dynamic> json) {
    final shift = Shift.fromJson(_map(json['shift']));
    final mine = shift.myAssignmentId == null
        ? null
        : ShiftAssignmentRef(
            id: shift.myAssignmentId!,
            status: shift.myStatus ?? ShiftAssignmentStatus.unknown,
          );
    return ShiftDetail(
      shift: shift,
      event: ShiftEventHead.fromJson(_map(json['event'])),
      users: ShiftUser.mapFromJson(json['users']),
      canPlan: _bool(json['canPlan']),
      myAssignment: mine,
      places: [
        for (final p in _maps(json['assignments'])) ?ShiftPlace.fromJson(p),
      ],
    );
  }

  @override
  List<Object?> get props => [
    shift,
    event,
    users,
    canPlan,
    myAssignment,
    places,
  ];
}

/// One of the caller's own places (`MyShiftResponse`).
class MyShift extends Equatable {
  const MyShift({
    required this.assignmentId,
    required this.status,
    this.assignedBy,
    required this.shift,
    required this.event,
    this.confirmBy,
    this.confirmByLocal,
  });

  final String assignmentId;
  final ShiftAssignmentStatus status;

  /// Who put the person on it; null when they signed up themselves.
  final String? assignedBy;
  final Shift shift;
  final ShiftEventHead event;

  /// Until when a place that came off the waiting list has to be confirmed
  /// (HIN-162): the instant, and the wall clock in the event's zone to show.
  final DateTime? confirmBy;
  final DateTime? confirmByLocal;

  /// The place came off the waiting list and waits for a confirmation.
  bool get promoted =>
      status == ShiftAssignmentStatus.assigned &&
      (confirmBy != null || confirmByLocal != null);

  /// The place as a reference, for the sheet.
  ShiftAssignmentRef get ref => ShiftAssignmentRef(
    id: assignmentId,
    status: status,
    confirmByLocal: promoted ? (confirmByLocal ?? confirmBy) : null,
  );

  factory MyShift.fromJson(Map<String, dynamic> json) {
    final confirmBy = parseInstant(json['confirmBy']);
    return MyShift(
      assignmentId: json['assignmentId'] as String? ?? '',
      status: ShiftAssignmentStatus.parse(json['status']),
      assignedBy: _text(json['assignedBy']),
      shift: Shift.fromJson(_map(json['shift'])),
      event: ShiftEventHead.fromJson(_map(json['event'])),
      confirmBy: confirmBy,
      confirmByLocal: parseLocalWallClock(json['confirmByLocal']) ?? confirmBy,
    );
  }

  /// The snapshot form: nobody else's id, not even who assigned it.
  Map<String, dynamic> toSnapshotJson() => {
    'assignmentId': assignmentId,
    'status': status.wire,
    'shift': shift.toSnapshotJson(),
    'event': event.toJson(),
    'confirmBy': confirmBy?.toUtc().toIso8601String(),
    'confirmByLocal': confirmByLocal == null
        ? null
        : _wallClock(confirmByLocal!),
  };

  /// A confirmation ends the deadline; [clearConfirmBy] says so.
  MyShift copyWith({
    ShiftAssignmentStatus? status,
    Shift? shift,
    bool clearConfirmBy = false,
  }) => MyShift(
    assignmentId: assignmentId,
    status: status ?? this.status,
    assignedBy: assignedBy,
    shift: shift ?? this.shift,
    event: event,
    confirmBy: clearConfirmBy ? null : confirmBy,
    confirmByLocal: clearConfirmBy ? null : confirmByLocal,
  );

  @override
  List<Object?> get props => [
    assignmentId,
    status,
    assignedBy,
    shift,
    event,
    confirmBy,
    confirmByLocal,
  ];
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

  /// The shift was full, or somebody already waited: the caller is on the
  /// waiting list now instead of on the shift (HIN-162).
  bool get waitlisted => assignment?.status == ShiftAssignmentStatus.waiting;

  /// A planner's answer for putting somebody else on a shift: the shift as the
  /// server drew it for the caller, untouched — the place is not the caller's.
  factory ShiftAssignResult.forOther(Map<String, dynamic> json) =>
      ShiftAssignResult(
        shift: Shift.fromJson(_map(json['shift'])),
        assignment: ShiftAssignmentRef.fromJson(json['assignment']),
        warnings: [
          for (final w in (json['warnings'] as List?) ?? const [])
            if (w is String) w,
        ],
      );

  factory ShiftAssignResult.fromJson(Map<String, dynamic> json) {
    final assignment = ShiftAssignmentRef.fromJson(json['assignment']);
    final shift = Shift.fromJson(_map(json['shift']));
    return ShiftAssignResult(
      // The caller's place rides on the shift while it is held; a release or
      // a decline answers with the same shape and a place that is gone. A
      // place on the waiting list is not held: the shift names the rank.
      shift: assignment == null
          ? shift
          : assignment.status == ShiftAssignmentStatus.waiting
          ? shift.copyWith(
              mine: false,
              clearMine: true,
              myWaitAssignmentId: assignment.id,
            )
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

/// What the month view marks on one day (`/shifts/calendar/marks`): counts,
/// never shifts. The day is the shift's first day in the caller's zone.
class ShiftDayMarks extends Equatable {
  const ShiftDayMarks({
    required this.date,
    this.mine = 0,
    this.open = 0,
    this.understaffed = 0,
  });

  /// Midnight of the day, as a local date.
  final DateTime date;

  /// The caller's own active places that day.
  final int mine;

  /// Shifts the caller could still sign up for.
  final int open;

  /// Shifts still missing somebody; a cancelled shift never counts.
  final int understaffed;

  static ShiftDayMarks? fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['date'] as String? ?? '');
    if (date == null) return null;
    return ShiftDayMarks(
      date: DateTime(date.year, date.month, date.day),
      mine: _int(json['mine']),
      open: _int(json['open']),
      understaffed: _int(json['understaffed']),
    );
  }

  /// Reads `{days: [...]}`.
  static List<ShiftDayMarks> listFromJson(Object? body) => [
    for (final day in _maps(_map(body)['days'])) ?ShiftDayMarks.fromJson(day),
  ];

  @override
  List<Object?> get props => [date, mine, open, understaffed];
}

/// What the month view reads (`/shifts/calendar/marks`): counts per day, and
/// the projects of the window the caller plans (HIN-166), for its "+".
class ShiftCalendarMarks extends Equatable {
  const ShiftCalendarMarks({
    this.days = const [],
    this.plannableProjectIds = const {},
  });

  final List<ShiftDayMarks> days;
  final Set<String> plannableProjectIds;

  factory ShiftCalendarMarks.fromJson(Object? body) => ShiftCalendarMarks(
    days: ShiftDayMarks.listFromJson(body),
    plannableProjectIds: {
      for (final id in (_map(body)['plannableProjectIds'] as List?) ?? const [])
        if (id is String) id,
    },
  );

  @override
  List<Object?> get props => [days, plannableProjectIds];
}

/// Shifts in a window with their events named once (`CalendarResponse`).
class ShiftCalendar extends Equatable {
  const ShiftCalendar({
    this.shifts = const [],
    this.events = const {},
    this.truncated = false,
    this.plannableProjectIds = const {},
  });

  final List<Shift> shifts;
  final Map<String, ShiftEventHead> events;
  final bool truncated;

  /// The projects of the window the caller may plan (HIN-45): where the
  /// calendar offers moving a block.
  final Set<String> plannableProjectIds;

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
    plannableProjectIds: {
      for (final id in (json['plannableProjectIds'] as List?) ?? const [])
        if (id is String) id,
    },
  );

  @override
  List<Object?> get props => [shifts, events, truncated, plannableProjectIds];
}

/// One person who may plan a project's shifts (`shift_planners`).
class ShiftPlanner extends Equatable {
  const ShiftPlanner({required this.userId, this.grantedBy, this.createdAt});

  final String userId;
  final String? grantedBy;
  final DateTime? createdAt;

  factory ShiftPlanner.fromJson(Map<String, dynamic> json) => ShiftPlanner(
    userId: json['userId'] as String? ?? '',
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

  /// Reads `PlannersResponse {planners, users}`.
  factory ShiftPlanners.fromJson(Object? body) {
    final json = _map(body);
    return ShiftPlanners(
      planners: [
        for (final p in _maps(json['planners']))
          if (p['userId'] != null) ShiftPlanner.fromJson(p),
      ],
      users: ShiftUser.mapFromJson(json['users']),
    );
  }

  @override
  List<Object?> get props => [planners, users];
}

/// One active place on a shift with its id (HIN-160), for taking somebody
/// off it.
class ShiftPlace extends Equatable {
  const ShiftPlace({
    required this.id,
    required this.userId,
    this.status = ShiftAssignmentStatus.assigned,
  });

  final String id;
  final String userId;
  final ShiftAssignmentStatus status;

  static ShiftPlace? fromJson(Map<String, dynamic> json) {
    final id = _text(json['id']) ?? _text(json['assignmentId']);
    final userId = _text(json['userId']);
    if (id == null || userId == null) return null;
    return ShiftPlace(
      id: id,
      userId: userId,
      status: ShiftAssignmentStatus.parse(json['status']),
    );
  }

  @override
  List<Object?> get props => [id, userId, status];
}

/// Somebody whose places now overlap after a move (`Warning`): their place on
/// [shiftId] and the one it collides with, named only where the caller may
/// see that project.
class ShiftWarning extends Equatable {
  const ShiftWarning({
    required this.userId,
    this.shiftId,
    this.conflictingShiftId,
  });

  final String userId;
  final String? shiftId;
  final String? conflictingShiftId;

  static List<ShiftWarning> listFromJson(Object? value) => [
    for (final w in _maps(value))
      if (_text(w['userId']) case final userId?)
        ShiftWarning(
          userId: userId,
          shiftId: _text(w['shiftId']),
          conflictingShiftId: _text(w['conflictingShiftId']),
        ),
  ];

  /// How many different people the warnings are about.
  static int people(List<ShiftWarning> warnings) =>
      {for (final w in warnings) w.userId}.length;

  @override
  List<Object?> get props => [userId, shiftId, conflictingShiftId];
}

/// A changed event and who now collides because of it (`EventChange`).
class ShiftEventChange extends Equatable {
  const ShiftEventChange({required this.event, this.warnings = const []});

  final ShiftEventDetail event;
  final List<ShiftWarning> warnings;

  factory ShiftEventChange.fromJson(Map<String, dynamic> json) =>
      ShiftEventChange(
        event: ShiftEventDetail.fromJson(
          json['event'] is Map<String, dynamic>
              ? json['event'] as Map<String, dynamic>
              : json,
        ),
        warnings: ShiftWarning.listFromJson(json['warnings']),
      );

  @override
  List<Object?> get props => [event, warnings];
}

/// A changed shift and who now collides because of it (`ShiftChange`).
class ShiftEdit extends Equatable {
  const ShiftEdit({required this.shift, this.warnings = const []});

  final Shift shift;
  final List<ShiftWarning> warnings;

  factory ShiftEdit.fromJson(Map<String, dynamic> json) => ShiftEdit(
    shift: Shift.fromJson(
      json['shift'] is Map<String, dynamic>
          ? json['shift'] as Map<String, dynamic>
          : json,
    ),
    warnings: ShiftWarning.listFromJson(json['warnings']),
  );

  @override
  List<Object?> get props => [shift, warnings];
}

/// What an event is made of, for creating one (`EventDraft`) or changing one
/// (`EventPatch`).
class ShiftEventInput extends Equatable {
  const ShiftEventInput({
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.description,
    this.location,
    this.timezone,
    this.selfAssignable = true,
  });

  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? description;
  final String? location;

  /// The IANA zone the wall clock was entered in; null lets the server take
  /// the creator's.
  final String? timezone;
  final bool selfAssignable;

  /// The body of a new event.
  Map<String, dynamic> toDraftJson() => {
    'title': title.trim(),
    'startsAt': startsAt.toUtc().toIso8601String(),
    'endsAt': endsAt.toUtc().toIso8601String(),
    'description': ?_text(description?.trim()),
    'location': ?_text(location?.trim()),
    'timezone': ?timezone,
    'selfAssignable': selfAssignable,
  };

  /// What differs from [before], as a patch: an emptied description or place
  /// is sent blank, which clears it on the server; anything unchanged is left
  /// out.
  Map<String, dynamic> toPatchJson(ShiftEventInput before) => {
    if (title.trim() != before.title) 'title': title.trim(),
    if (!startsAt.isAtSameMomentAs(before.startsAt) ||
        !endsAt.isAtSameMomentAs(before.endsAt)) ...{
      'startsAt': startsAt.toUtc().toIso8601String(),
      'endsAt': endsAt.toUtc().toIso8601String(),
    },
    if ((description?.trim() ?? '') != (before.description ?? ''))
      'description': description?.trim() ?? '',
    if ((location?.trim() ?? '') != (before.location ?? ''))
      'location': location?.trim() ?? '',
    if (timezone != null && timezone != before.timezone) 'timezone': timezone,
    if (selfAssignable != before.selfAssignable)
      'selfAssignable': selfAssignable,
  };

  @override
  List<Object?> get props => [
    title,
    startsAt,
    endsAt,
    description,
    location,
    timezone,
    selfAssignable,
  ];
}

/// What a shift is made of (`ShiftDraft`, `ShiftPatch`).
class ShiftInput extends Equatable {
  const ShiftInput({
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.requiredHelpers = 1,
    this.maxHelpers,
  });

  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final int requiredHelpers;

  /// Null: no upper limit.
  final int? maxHelpers;

  Map<String, dynamic> toDraftJson() => {
    'title': ?_text(title.trim()),
    'startsAt': startsAt.toUtc().toIso8601String(),
    'endsAt': endsAt.toUtc().toIso8601String(),
    'requiredHelpers': requiredHelpers,
    'maxHelpers': ?maxHelpers,
  };

  /// What differs from [before]; removing the upper limit is said in so many
  /// words (`clearMaxHelpers`), because a missing field means "unchanged".
  Map<String, dynamic> toPatchJson(ShiftInput before) => {
    if (title.trim() != before.title) 'title': title.trim(),
    if (!startsAt.isAtSameMomentAs(before.startsAt) ||
        !endsAt.isAtSameMomentAs(before.endsAt)) ...{
      'startsAt': startsAt.toUtc().toIso8601String(),
      'endsAt': endsAt.toUtc().toIso8601String(),
    },
    if (requiredHelpers != before.requiredHelpers)
      'requiredHelpers': requiredHelpers,
    if (maxHelpers != before.maxHelpers)
      if (maxHelpers == null)
        'clearMaxHelpers': true
      else
        'maxHelpers': maxHelpers,
  };

  @override
  List<Object?> get props => [
    title,
    startsAt,
    endsAt,
    requiredHelpers,
    maxHelpers,
  ];
}

/// Whether the caller has a personal shift feed (HIN-47). Never the address:
/// that is shown once, when it is made.
class ShiftFeedStatus extends Equatable {
  const ShiftFeedStatus({this.exists = false, this.createdAt, this.lastUsedAt});

  final bool exists;
  final DateTime? createdAt;

  /// When a calendar last fetched it; null until the first time.
  final DateTime? lastUsedAt;

  factory ShiftFeedStatus.fromJson(Object? body) {
    final json = _map(body);
    return ShiftFeedStatus(
      exists: _bool(json['exists']),
      createdAt: parseInstant(json['createdAt']),
      lastUsedAt: parseInstant(json['lastUsedAt']),
    );
  }

  @override
  List<Object?> get props => [exists, createdAt, lastUsedAt];
}

/// A new feed's address, in the one answer that carries it.
class ShiftFeedAddress extends Equatable {
  const ShiftFeedAddress({required this.url, required this.webcalUrl});

  /// The `https://` address, the one to copy.
  final String url;

  /// The `webcal://` address, for "open in calendar".
  final String webcalUrl;

  factory ShiftFeedAddress.fromJson(Object? body) {
    final json = _map(body);
    final url = _text(json['url']) ?? '';
    return ShiftFeedAddress(
      url: url,
      webcalUrl:
          _text(json['webcalUrl']) ??
          url.replaceFirst(RegExp('^https?://'), 'webcal://'),
    );
  }

  @override
  List<Object?> get props => [url, webcalUrl];
}

/// One person a planner can put on a project's shifts (`candidates`).
class ShiftCandidate extends Equatable {
  const ShiftCandidate({
    required this.userId,
    required this.name,
    this.avatarUrl,
  });

  final String userId;
  final String name;
  final String? avatarUrl;

  @override
  List<Object?> get props => [userId, name, avatarUrl];
}

/// The people who may be put on a project's shifts (HIN-162): active
/// accounts that reach the project, directly or through a team, by name.
/// [truncated] when there are more than were asked for.
class ShiftCandidates extends Equatable {
  const ShiftCandidates({this.candidates = const [], this.truncated = false});

  final List<ShiftCandidate> candidates;
  final bool truncated;

  factory ShiftCandidates.fromJson(Object? body) {
    final json = _map(body);
    return ShiftCandidates(
      candidates: [
        for (final c in _maps(json['candidates']))
          if (_text(c['userId']) case final userId?)
            ShiftCandidate(
              userId: userId,
              name: _text(c['name']) ?? '',
              avatarUrl: _text(c['avatarUrl']),
            ),
      ],
      truncated: _bool(json['truncated']),
    );
  }

  @override
  List<Object?> get props => [candidates, truncated];
}
