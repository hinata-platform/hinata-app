import 'package:equatable/equatable.dart';

import '../util/dates.dart';
import 'work_models.dart';

/// The extended time-tracking module's own shapes: the timer that is running
/// right now, and what the server says about an entry it has just saved.
///
/// The entry itself is [WorkItem] and stays there — the same document the issue
/// panel and the timesheet already read. A second model of the same rows would
/// be two parsers to keep in step for no gain.

/// How a timer counts. Only [stopwatch] is written before HIN-86; the other two
/// are stored by the server today so that the value never changes meaning.
enum TimerMode {
  stopwatch,
  countdown,
  pomodoro;

  static TimerMode parse(String? raw) => switch (raw) {
    'COUNTDOWN' => TimerMode.countdown,
    'POMODORO' => TimerMode.pomodoro,
    _ => TimerMode.stopwatch,
  };
}

/// The timer the server says is running for this account.
///
/// It carries no elapsed time on purpose: the number on screen is counted
/// locally from [startedAt], so it keeps moving between requests instead of
/// freezing until the next one. The server is still the truth about *whether*
/// one runs and what it is called — a timer started on a phone has to read the
/// same on a laptop.
class RunningTimer extends Equatable {
  const RunningTimer({
    required this.id,
    required this.startedAt,
    this.projectId,
    this.issueId,
    this.description,
    this.activityType,
    this.tags = const [],
    this.billable = false,
    this.mode = TimerMode.stopwatch,
    this.plannedMinutes,
  });

  final String id;
  final DateTime startedAt;
  final String? projectId;
  final String? issueId;
  final String? description;

  /// Null until somebody chooses one; the server applies the default when the
  /// entry is filed.
  final String? activityType;
  final List<String> tags;
  final bool billable;
  final TimerMode mode;
  final int? plannedMinutes;

  /// How long it has been running as of [now], never negative.
  ///
  /// A clock that is behind the server's would otherwise show a timer that has
  /// not started yet, counting backwards — which is what a device whose time is
  /// a few seconds off would do the moment a timer is started.
  Duration elapsed(DateTime now) {
    final elapsed = now.difference(startedAt);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  factory RunningTimer.fromJson(Map<String, dynamic> json) => RunningTimer(
    id: json['id'] as String,
    startedAt: parseInstant(json['startedAt']) ?? DateTime.now(),
    projectId: json['projectId'] as String?,
    issueId: json['issueId'] as String?,
    description: json['description'] as String?,
    activityType: json['activityType'] as String?,
    tags: ((json['tags'] as List<dynamic>?) ?? const [])
        .whereType<String>()
        .toList(),
    billable: json['billable'] as bool? ?? false,
    mode: TimerMode.parse(json['mode'] as String?),
    plannedMinutes: (json['plannedMinutes'] as num?)?.toInt(),
  );

  @override
  List<Object?> get props => [
    id,
    startedAt,
    projectId,
    issueId,
    description,
    activityType,
    tags,
    billable,
    mode,
    plannedMinutes,
  ];
}

/// A saved entry together with what the server noticed while saving it.
///
/// [overlaps] names the caller's other entries that share time with this one.
/// It is advice: two entries may legitimately overlap, so the server records
/// what it was told and reports what it saw, and the person decides. Empty
/// whenever the entry has no start and end to compare.
class SavedTimeEntry extends Equatable {
  const SavedTimeEntry({required this.entry, this.overlaps = const []});

  final WorkItem entry;
  final List<String> overlaps;

  bool get hasOverlaps => overlaps.isNotEmpty;

  factory SavedTimeEntry.fromJson(Map<String, dynamic> json) => SavedTimeEntry(
    entry: WorkItem.fromJson(json['entry'] as Map<String, dynamic>),
    overlaps: ((json['overlaps'] as List<dynamic>?) ?? const [])
        .whereType<String>()
        .toList(),
  );

  @override
  List<Object?> get props => [entry, overlaps];
}

/// What a new or edited entry says. Either [startedAt] + [endedAt] or
/// [durationMinutes] + [date] — the server settles which, and refuses a draft
/// that says neither.
class TimeEntryDraft extends Equatable {
  const TimeEntryDraft({
    this.projectId,
    this.issueId,
    this.durationMinutes,
    this.date,
    this.activityType,
    this.description,
    this.startedAt,
    this.endedAt,
    this.tags,
    this.billable,
  });

  final String? projectId;
  final String? issueId;
  final int? durationMinutes;
  final DateTime? date;
  final String? activityType;
  final String? description;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// Null means "leave them alone"; an empty list means "remove them all".
  final List<String>? tags;
  final bool? billable;

  /// The body a create sends: every field, so an absent one means "not given".
  Map<String, dynamic> toCreateJson() => {
    'projectId': ?projectId,
    'issueId': ?issueId,
    'durationMinutes': ?durationMinutes,
    if (date != null) 'date': formatDateOnly(date!),
    'activityType': ?activityType,
    'description': ?description,
    'startedAt': ?startedAt?.toUtc().toIso8601String(),
    'endedAt': ?endedAt?.toUtc().toIso8601String(),
    'tags': ?tags,
    'billable': ?billable,
  };

  /// The body a patch sends.
  ///
  /// The two instants are always present, explicitly null when they are being
  /// cleared: the server tells "absent" from "null" for exactly these two
  /// fields, because an instant has no empty value of its own and switching an
  /// entry from a start/end pair to a plain duration has to be sayable.
  ///
  /// Everything else is omitted when the draft does not carry it — the tags
  /// especially. The server reads a present tag list as an instruction and an
  /// empty one as "remove them all", so a form that does not edit tags must not
  /// mention them. Sending the default empty list stripped the tags off every
  /// entry that was edited, silently, for the one field the screen never shows
  /// you losing.
  Map<String, dynamic> toPatchJson() => {
    'durationMinutes': ?durationMinutes,
    if (date != null) 'date': formatDateOnly(date!),
    'activityType': ?activityType,
    'description': description ?? '',
    'startedAt': startedAt?.toUtc().toIso8601String(),
    'endedAt': endedAt?.toUtc().toIso8601String(),
    'tags': ?tags,
    'billable': ?billable,
  };

  @override
  List<Object?> get props => [
    projectId,
    issueId,
    durationMinutes,
    date,
    activityType,
    description,
    startedAt,
    endedAt,
    tags,
    billable,
  ];
}

/// What narrows the personal list. Every field optional; the owner never is —
/// the server answers with the caller's own entries and offers no way to ask
/// otherwise.
class TimeEntryFilter extends Equatable {
  const TimeEntryFilter({this.from, this.to, this.projectId, this.query});

  final DateTime? from;
  final DateTime? to;
  final String? projectId;
  final String? query;

  bool get isEmpty =>
      from == null &&
      to == null &&
      projectId == null &&
      (query == null || query!.trim().isEmpty);

  TimeEntryFilter copyWith({
    DateTime? from,
    DateTime? to,
    String? projectId,
    String? query,
    bool clearRange = false,
    bool clearProject = false,
    bool clearQuery = false,
  }) => TimeEntryFilter(
    from: clearRange ? null : (from ?? this.from),
    to: clearRange ? null : (to ?? this.to),
    projectId: clearProject ? null : (projectId ?? this.projectId),
    query: clearQuery ? null : (query ?? this.query),
  );

  Map<String, dynamic> toQuery() => {
    if (from != null) 'from': formatDateOnly(from!),
    if (to != null) 'to': formatDateOnly(to!),
    'projectId': ?projectId,
    if (query != null && query!.trim().isNotEmpty) 'q': query!.trim(),
  };

  @override
  List<Object?> get props => [from, to, projectId, query];
}
