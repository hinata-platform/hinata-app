import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart' show IconData;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../util/dates.dart';
import 'work_models.dart';

/// The extended time-tracking module's own shapes: the timer that is running
/// right now, and what the server says about an entry it has just saved.
///
/// The entry itself is [WorkItem] and stays there — the same document the issue
/// panel and the timesheet already read. A second model of the same rows would
/// be two parsers to keep in step for no gain.

/// How a timer counts.
///
/// The server owns this, as it owns whether a timer runs at all: a pomodoro
/// begun on a phone has to be the same pomodoro on a laptop, half-way through
/// the same interval. Only [stopwatch] was ever written before HIN-86, so a
/// stored value never changes meaning.
enum TimerMode {
  stopwatch,
  countdown,
  pomodoro;

  static TimerMode parse(String? raw) => switch (raw) {
    'COUNTDOWN' => TimerMode.countdown,
    'POMODORO' => TimerMode.pomodoro,
    _ => TimerMode.stopwatch,
  };

  String get wire => switch (this) {
    TimerMode.stopwatch => 'STOPWATCH',
    TimerMode.countdown => 'COUNTDOWN',
    TimerMode.pomodoro => 'POMODORO',
  };

  /// The i18n key for this mode's name.
  String get labelKey => 'time.mode.$name';

  /// The glyph every surface draws for it. Here rather than in a `switch` at
  /// each call site: a fourth mode should be one edit, not three.
  IconData get icon => switch (this) {
    TimerMode.stopwatch => LucideIcons.timer,
    TimerMode.countdown => LucideIcons.hourglass,
    TimerMode.pomodoro => LucideIcons.circleDot,
  };
}

/// Which half of a pomodoro cycle is running. Null outside [TimerMode.pomodoro].
enum TimerPhase {
  work,
  shortBreak,
  longBreak;

  static TimerPhase? parse(String? raw) => switch (raw) {
    'WORK' => TimerPhase.work,
    'BREAK' => TimerPhase.shortBreak,
    'LONG_BREAK' => TimerPhase.longBreak,
    _ => null,
  };

  /// How the server spells it. Beside [parse], because the pairing is the whole
  /// point: `shortBreak` is `BREAK` on the wire, and a spelling written out at
  /// a call site somewhere else is one that can be renamed without this one
  /// noticing — after which a restored pomodoro reads back with no phase.
  String get wire => switch (this) {
    TimerPhase.work => 'WORK',
    TimerPhase.shortBreak => 'BREAK',
    TimerPhase.longBreak => 'LONG_BREAK',
  };

  /// Whether this half records nothing. The distinction the whole module turns
  /// on: booked time is worked time, so a break never becomes an entry.
  bool get isBreak => this != TimerPhase.work;

  String get labelKey => 'time.phase.$name';
}

/// The lengths one pomodoro run counts by, in minutes.
///
/// A copy of the person's preferences taken when the run started, not a live
/// reference to them: changing your preferred break length must not rewrite the
/// run you are in the middle of.
class PomodoroConfig extends Equatable {
  const PomodoroConfig({
    this.work = 25,
    this.shortBreak = 5,
    this.longBreak = 15,
    this.cycles = 4,
  });

  final int work;
  final int shortBreak;
  final int longBreak;

  /// Work intervals per set — after that many, the break is the long one.
  final int cycles;

  /// Whether work interval number [done] completes a set.
  ///
  /// [done] must be positive as well as divide evenly: zero divides by
  /// everything, so without it a run whose first interval recorded nothing
  /// would open with the long break — the reward for a set nobody has worked.
  bool _completesASet(int done) => cycles > 0 && done > 0 && done % cycles == 0;

  /// Minutes of the break that follows work interval number [done].
  int breakAfter(int done) => _completesASet(done) ? longBreak : shortBreak;

  /// Which break follows work interval number [done].
  TimerPhase phaseAfter(int done) =>
      _completesASet(done) ? TimerPhase.longBreak : TimerPhase.shortBreak;

  /// How long [phase] runs, given the intervals already done.
  int minutesOf(TimerPhase phase, int done) =>
      phase == TimerPhase.work ? work : breakAfter(done);

  PomodoroConfig copyWith({
    int? work,
    int? shortBreak,
    int? longBreak,
    int? cycles,
  }) => PomodoroConfig(
    work: work ?? this.work,
    shortBreak: shortBreak ?? this.shortBreak,
    longBreak: longBreak ?? this.longBreak,
    cycles: cycles ?? this.cycles,
  );

  factory PomodoroConfig.fromJson(Map<String, dynamic> json) => PomodoroConfig(
    work: (json['work'] as num?)?.toInt() ?? 25,
    shortBreak: (json['shortBreak'] as num?)?.toInt() ?? 5,
    longBreak: (json['longBreak'] as num?)?.toInt() ?? 15,
    cycles: (json['cycles'] as num?)?.toInt() ?? 4,
  );

  Map<String, dynamic> toJson() => {
    'work': work,
    'shortBreak': shortBreak,
    'longBreak': longBreak,
    'cycles': cycles,
  };

  @override
  List<Object?> get props => [work, shortBreak, longBreak, cycles];
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
    this.pomodoro,
    this.phase,
    this.phaseStartedAt,
    this.cyclesDone = 0,
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

  /// A countdown's target, in minutes; null for the other two modes.
  final int? plannedMinutes;

  /// The lengths a pomodoro run counts by; null for the other two modes.
  final PomodoroConfig? pomodoro;

  /// Which half of a pomodoro is running; null for the other two modes.
  final TimerPhase? phase;

  /// When the current [phase] began. Equal to [startedAt] today, because every
  /// phase change writes a new timer, but they are not the same fact.
  final DateTime? phaseStartedAt;

  /// Work intervals completed in this run — what decides when the long break
  /// falls, and what the focus screen counts out.
  final int cyclesDone;

  bool get isBreak => phase?.isBreak ?? false;

  /// How long it has been running as of [now], never negative.
  ///
  /// A clock that is behind the server's would otherwise show a timer that has
  /// not started yet, counting backwards — which is what a device whose time is
  /// a few seconds off would do the moment a timer is started.
  Duration elapsed(DateTime now) {
    final elapsed = now.difference(startedAt);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  /// How long this timer is counting *towards*, or null when it counts towards
  /// nothing — which is what a stopwatch is.
  Duration? get target => switch (mode) {
    TimerMode.stopwatch => null,
    TimerMode.countdown =>
      plannedMinutes == null ? null : Duration(minutes: plannedMinutes!),
    TimerMode.pomodoro =>
      (pomodoro == null || phase == null)
          ? null
          : Duration(minutes: pomodoro!.minutesOf(phase!, cyclesDone)),
  };

  /// Whether the current interval has reached its target. Always false for a
  /// stopwatch, which has none.
  bool hasReachedTarget(DateTime now) {
    final target = this.target;
    return target != null && elapsed(now) >= target;
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
    pomodoro: json['pomodoro'] is Map<String, dynamic>
        ? PomodoroConfig.fromJson(json['pomodoro'] as Map<String, dynamic>)
        : null,
    phase: TimerPhase.parse(json['phase'] as String?),
    phaseStartedAt: parseInstant(json['phaseStartedAt']),
    cyclesDone: (json['cyclesDone'] as num?)?.toInt() ?? 0,
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
    pomodoro,
    phase,
    phaseStartedAt,
    cyclesDone,
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

/// One window of the personal calendar: what was asked for, what came back, and
/// whether the server had more than it hands out.
///
/// The window is echoed so a client can tell this answer apart from the one it
/// asked for two navigations ago — a slow week that resolves after the reader
/// has paged on must not be drawn over the week now on screen.
///
/// Only entries for now. The later layers this view grows — absences and
/// holidays, then subscribed calendar events — arrive as their own fields when
/// the stages that produce them land; a missing layer reads as an empty one, so
/// nothing here has to move for them.
class CalendarWindow extends Equatable {
  const CalendarWindow({
    required this.from,
    required this.to,
    this.entries = const [],
    this.truncated = false,
  });

  final DateTime from;
  final DateTime to;
  final List<WorkItem> entries;

  /// The window held more than the server returns. The grid says so rather than
  /// quietly drawing a partial week.
  final bool truncated;

  factory CalendarWindow.fromJson(Map<String, dynamic> json) => CalendarWindow(
    from: parseDate(json['from'] as String?) ?? DateTime.now(),
    to: parseDate(json['to'] as String?) ?? DateTime.now(),
    entries: ((json['entries'] as List<dynamic>?) ?? const [])
        .map((e) => WorkItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    truncated: json['truncated'] as bool? ?? false,
  );

  @override
  List<Object?> get props => [from, to, entries, truncated];
}
