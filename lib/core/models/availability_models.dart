import 'package:equatable/equatable.dart';

import '../util/dates.dart';

/// Capacity planning (HIN-91): working-time patterns, absences, holidays and the
/// capacity that follows from them.
///
/// Planning information, never a rule about the entries. A day these models
/// mark is a day like any other for recording time (R9); the app shows the
/// marking and nothing else changes.

/// Why somebody is away. Nothing more is asked: a reason for a sick day would
/// be health data.
enum TimeOffType {
  vacation('VACATION'),
  sick('SICK'),
  other('OTHER');

  const TimeOffType(this.wire);

  final String wire;

  String get labelKey => 'availability.type.$name';

  static TimeOffType? fromWire(Object? value) {
    for (final type in values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

/// Planned minutes per weekday from a day on.
class WorkingPattern extends Equatable {
  const WorkingPattern({
    required this.id,
    required this.validFrom,
    required this.minutesPerWeekday,
    this.holidayCalendarId,
  });

  final String id;
  final DateTime validFrom;

  /// Seven entries, Monday first.
  final List<int> minutesPerWeekday;
  final String? holidayCalendarId;

  static WorkingPattern? fromJson(Map<String, dynamic> json) {
    final validFrom = parseDate(json['validFrom']);
    if (validFrom == null) return null;
    return WorkingPattern(
      id: json['id'] as String? ?? '',
      validFrom: validFrom,
      minutesPerWeekday: minutesOf(json['minutesPerWeekday']),
      holidayCalendarId: json['holidayCalendarId'] as String?,
    );
  }

  /// Seven minutes, Monday first, whatever arrived: a short list is filled
  /// with zeros, so a weekday is never out of range.
  static List<int> minutesOf(Object? value) {
    final list = value is List ? value : const [];
    return [
      for (var day = 0; day < 7; day++)
        day < list.length ? (list[day] as num?)?.toInt() ?? 0 : 0,
    ];
  }

  @override
  List<Object?> get props => [
    id,
    validFrom,
    minutesPerWeekday,
    holidayCalendarId,
  ];
}

/// A person's patterns and what applies while they have none.
class WorkingSchedule extends Equatable {
  const WorkingSchedule({
    required this.userId,
    required this.defaultMinutesPerWeekday,
    this.defaultHolidayCalendarId,
    this.current,
    this.history = const [],
  });

  final String userId;
  final List<int> defaultMinutesPerWeekday;
  final String? defaultHolidayCalendarId;

  /// The pattern that applies today, or null while the default does.
  final WorkingPattern? current;

  /// Every pattern, newest first.
  final List<WorkingPattern> history;

  List<int> get effectiveMinutes =>
      current?.minutesPerWeekday ?? defaultMinutesPerWeekday;

  factory WorkingSchedule.fromJson(Map<String, dynamic> json) =>
      WorkingSchedule(
        userId: json['userId'] as String? ?? '',
        defaultMinutesPerWeekday: WorkingPattern.minutesOf(
          json['defaultMinutesPerWeekday'],
        ),
        defaultHolidayCalendarId: json['defaultHolidayCalendarId'] as String?,
        current: json['current'] is Map<String, dynamic>
            ? WorkingPattern.fromJson(json['current'] as Map<String, dynamic>)
            : null,
        history: [
          for (final item in (json['history'] as List<dynamic>?) ?? const [])
            ?WorkingPattern.fromJson(item as Map<String, dynamic>),
        ],
      );

  @override
  List<Object?> get props => [
    userId,
    defaultMinutesPerWeekday,
    defaultHolidayCalendarId,
    current,
    history,
  ];
}

/// An absence. [id] and [note] are null in a lead's view of somebody else's.
class TimeOff extends Equatable {
  const TimeOff({
    this.id,
    required this.userId,
    required this.type,
    required this.from,
    required this.to,
    this.typeId,
    this.halfDay = false,
    this.note,
  });

  /// Longest note the server keeps (`TimeOff.NOTE_MAX`).
  static const int noteMax = 200;

  final String? id;
  final String userId;
  final TimeOffType type;

  /// The operator-defined type this was entered under, when the instance offers
  /// any (HIN-116). Null before absence management, while it is off, and for
  /// anybody who is not shown the full picture — a lead who may only see that
  /// somebody is away is not told which type it was.
  final String? typeId;

  final DateTime from;
  final DateTime to;
  final bool halfDay;
  final String? note;

  static TimeOff? fromJson(Map<String, dynamic> json) {
    final type = TimeOffType.fromWire(json['type']);
    final from = parseDate(json['from']);
    final to = parseDate(json['to']);
    if (type == null || from == null || to == null) return null;
    return TimeOff(
      id: json['id'] as String?,
      userId: json['userId'] as String? ?? '',
      type: type,
      typeId: json['typeId'] as String?,
      from: from,
      to: to,
      halfDay: json['halfDay'] as bool? ?? false,
      note: json['note'] as String?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    type,
    typeId,
    from,
    to,
    halfDay,
    note,
  ];
}

/// What somebody types for a new absence or an edit.
class TimeOffDraft {
  const TimeOffDraft({
    required this.type,
    required this.from,
    required this.to,
    this.typeId,
    this.halfDay = false,
    this.note,
  });

  final TimeOffType type;

  /// The operator's own type, when one was picked. The server derives [type]
  /// from it; sending both keeps a server without the module reading this
  /// exactly as it always did.
  final String? typeId;

  final DateTime from;
  final DateTime to;
  final bool halfDay;
  final String? note;

  /// A blank note is sent as an empty string, which the server reads as
  /// "clear it" on an edit.
  Map<String, dynamic> toJson() => {
    'type': type.wire,
    'typeId': ?typeId,
    'from': formatDateOnly(from),
    'to': formatDateOnly(to),
    'halfDay': halfDay && DateUtilsLite.sameDay(from, to),
    'note': note?.trim() ?? '',
  };
}

/// A holiday on a day, as the calendar a person follows names it.
class HolidayMark extends Equatable {
  const HolidayMark({
    required this.date,
    required this.name,
    this.halfDay = false,
  });

  final DateTime date;
  final String name;
  final bool halfDay;

  static HolidayMark? fromJson(Map<String, dynamic> json) {
    final date = parseDate(json['date']);
    if (date == null) return null;
    return HolidayMark(
      date: date,
      name: json['name'] as String? ?? '',
      halfDay: json['halfDay'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [date, name, halfDay];
}

/// One day of a capacity window.
class DayCapacity extends Equatable {
  const DayCapacity({
    required this.date,
    required this.scheduledMinutes,
    required this.holidayMinutes,
    required this.absenceMinutes,
    required this.capacityMinutes,
  });

  final DateTime date;
  final int scheduledMinutes;
  final int holidayMinutes;
  final int absenceMinutes;
  final int capacityMinutes;

  static DayCapacity? fromJson(Map<String, dynamic> json) {
    final date = parseDate(json['date']);
    if (date == null) return null;
    int minutes(String key) => (json[key] as num?)?.toInt() ?? 0;
    return DayCapacity(
      date: date,
      scheduledMinutes: minutes('scheduledMinutes'),
      holidayMinutes: minutes('holidayMinutes'),
      absenceMinutes: minutes('absenceMinutes'),
      capacityMinutes: minutes('capacityMinutes'),
    );
  }

  @override
  List<Object?> get props => [
    date,
    scheduledMinutes,
    holidayMinutes,
    absenceMinutes,
    capacityMinutes,
  ];
}

/// Capacity over a window: planned minutes less holidays and absences.
class Capacity extends Equatable {
  const Capacity({
    required this.from,
    required this.to,
    this.scheduledMinutes = 0,
    this.holidayMinutes = 0,
    this.absenceMinutes = 0,
    this.capacityMinutes = 0,
    this.days = const [],
    this.holidays = const [],
    this.absences = const [],
  });

  final DateTime from;
  final DateTime to;
  final int scheduledMinutes;
  final int holidayMinutes;
  final int absenceMinutes;
  final int capacityMinutes;
  final List<DayCapacity> days;
  final List<HolidayMark> holidays;
  final List<TimeOff> absences;

  /// The markings of the window's days.
  DayMarks get marks => DayMarks(
    holidays: holidays,
    absences: absences,
    scheduledMinutes: {for (final day in days) day.date: day.scheduledMinutes},
  );

  factory Capacity.fromJson(Map<String, dynamic> json) {
    int minutes(String key) => (json[key] as num?)?.toInt() ?? 0;
    return Capacity(
      from: parseDate(json['from']) ?? DateTime.now(),
      to: parseDate(json['to']) ?? DateTime.now(),
      scheduledMinutes: minutes('scheduledMinutes'),
      holidayMinutes: minutes('holidayMinutes'),
      absenceMinutes: minutes('absenceMinutes'),
      capacityMinutes: minutes('capacityMinutes'),
      days: [
        for (final item in (json['days'] as List<dynamic>?) ?? const [])
          ?DayCapacity.fromJson(item as Map<String, dynamic>),
      ],
      holidays: [
        for (final item in (json['holidays'] as List<dynamic>?) ?? const [])
          ?HolidayMark.fromJson(item as Map<String, dynamic>),
      ],
      absences: [
        for (final item in (json['absences'] as List<dynamic>?) ?? const [])
          ?TimeOff.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  @override
  List<Object?> get props => [
    from,
    to,
    scheduledMinutes,
    holidayMinutes,
    absenceMinutes,
    capacityMinutes,
    days,
    holidays,
    absences,
  ];
}

/// What a marked day is. One of three, in that order when a day is several.
enum DayMarkKind { holiday, absence, nonRegular }

/// The marking of one day: a holiday, an absence, or a day without planned
/// hours. A tone and a sentence, never a refusal.
class DayMark extends Equatable {
  const DayMark.holiday(this.name, {this.halfDay = false})
    : kind = DayMarkKind.holiday,
      absenceType = null;

  const DayMark.absence(this.absenceType, {this.halfDay = false})
    : kind = DayMarkKind.absence,
      name = null;

  const DayMark.nonRegular()
    : kind = DayMarkKind.nonRegular,
      name = null,
      absenceType = null,
      halfDay = false;

  final DayMarkKind kind;
  final String? name;
  final TimeOffType? absenceType;
  final bool halfDay;

  @override
  List<Object?> get props => [kind, name, absenceType, halfDay];
}

/// The markings of a window of days, asked for one day at a time.
///
/// One answer for every surface that marks days (the calendar, its week strip
/// and the list), so a day cannot be a holiday in one of them and an ordinary
/// day in another.
///
/// Every answer is a lookup, never a search: the list and the calendar ask once
/// for every day they draw, so each holiday, each day of each absence and each
/// day's planned minutes are filed under their day when the set is made.
class DayMarks {
  DayMarks({
    List<HolidayMark> holidays = const [],
    List<TimeOff> absences = const [],
    Map<DateTime, int> scheduledMinutes = const {},
  }) : this._(
         {for (final mark in holidays) _key(mark.date): mark},
         _absencesByDay(absences),
         {
           for (final entry in scheduledMinutes.entries)
             _key(entry.key): entry.value,
         },
       );

  DayMarks._(this._holidays, this._absences, this._scheduled);

  static final DayMarks none = DayMarks();

  /// Most days one absence is filed under: a year, the widest window the
  /// server answers, so a span that arrived wrong cannot grow the set without
  /// end.
  static const int _absenceDaysMax = 366;

  final Map<int, HolidayMark> _holidays;
  final Map<int, TimeOff> _absences;
  final Map<int, int> _scheduled;

  /// The marking of [day], or null for an ordinary working day or a day this
  /// window says nothing about.
  DayMark? on(DateTime day) {
    final key = _key(day);
    final holiday = _holidays[key];
    if (holiday != null) {
      return DayMark.holiday(holiday.name, halfDay: holiday.halfDay);
    }
    final absence = _absences[key];
    if (absence != null) {
      return DayMark.absence(absence.type, halfDay: absence.halfDay);
    }
    if (_scheduled[key] == 0) return const DayMark.nonRegular();
    return null;
  }

  /// One set of both windows' days, for windows loaded one at a time. A day
  /// both of them know is answered by [other], the window read later.
  DayMarks merge(DayMarks other) => DayMarks._(
    {..._holidays, ...other._holidays},
    {..._absences, ...other._absences},
    {..._scheduled, ...other._scheduled},
  );

  /// Every absence under each of its days. Where two overlap, the one listed
  /// first keeps the day.
  static Map<int, TimeOff> _absencesByDay(List<TimeOff> absences) {
    final byDay = <int, TimeOff>{};
    for (final absence in absences) {
      var day = DateTime(
        absence.from.year,
        absence.from.month,
        absence.from.day,
      );
      for (
        var filed = 0;
        filed < _absenceDaysMax && !day.isAfter(absence.to);
        filed++
      ) {
        byDay.putIfAbsent(_key(day), () => absence);
        day = DateTime(day.year, day.month, day.day + 1);
      }
    }
    return byDay;
  }

  static int _key(DateTime day) => day.year * 10000 + day.month * 100 + day.day;
}

/// A holiday calendar. The feed and import fields are null for anybody but an
/// administrator.
class HolidayCalendar extends Equatable {
  const HolidayCalendar({
    required this.id,
    required this.name,
    this.region,
    this.defaultCalendar = false,
    this.hasFeed,
    this.feedHost,
    this.importState,
    this.lastImportedAt,
    this.lastImportError,
    this.lastImport,
  });

  /// Longest name and region the server keeps (`HolidayCalendar.NAME_MAX`,
  /// `REGION_MAX`).
  static const int nameMax = 80;
  static const int regionMax = 80;

  final String id;
  final String name;
  final String? region;
  final bool defaultCalendar;
  final bool? hasFeed;
  final String? feedHost;

  /// `RUNNING`, `DONE` or `FAILED`, or null before the first import.
  final String? importState;
  final DateTime? lastImportedAt;

  /// The sentence of the last failed import, in the reader's language.
  final String? lastImportError;
  final HolidayImportSummary? lastImport;

  bool get importing => importState == 'RUNNING';
  bool get importFailed => importState == 'FAILED';

  factory HolidayCalendar.fromJson(Map<String, dynamic> json) =>
      HolidayCalendar(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        region: json['region'] as String?,
        defaultCalendar: json['defaultCalendar'] as bool? ?? false,
        hasFeed: json['hasFeed'] as bool?,
        feedHost: json['feedHost'] as String?,
        importState: json['importState'] as String?,
        lastImportedAt: parseInstant(json['lastImportedAt']),
        lastImportError: json['lastImportError'] as String?,
        lastImport: json['lastImport'] is Map<String, dynamic>
            ? HolidayImportSummary.fromJson(
                json['lastImport'] as Map<String, dynamic>,
              )
            : null,
      );

  @override
  List<Object?> get props => [
    id,
    name,
    region,
    defaultCalendar,
    hasFeed,
    feedHost,
    importState,
    lastImportedAt,
    lastImportError,
    lastImport,
  ];
}

/// What one import did for one year.
class HolidayImportSummary extends Equatable {
  const HolidayImportSummary({
    required this.year,
    this.added = 0,
    this.updated = 0,
    this.unchanged = 0,
    this.capped = 0,
    this.truncated = false,
  });

  final int year;
  final int added;
  final int updated;
  final int unchanged;
  final int capped;
  final bool truncated;

  factory HolidayImportSummary.fromJson(Map<String, dynamic> json) {
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    return HolidayImportSummary(
      year: count('year'),
      added: count('added'),
      updated: count('updated'),
      unchanged: count('unchanged'),
      capped: count('capped'),
      truncated: json['truncated'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
    year,
    added,
    updated,
    unchanged,
    capped,
    truncated,
  ];
}

/// One holiday of a calendar.
class Holiday extends Equatable {
  const Holiday({
    required this.id,
    required this.calendarId,
    required this.date,
    required this.name,
    this.halfDay = false,
    this.imported = false,
  });

  /// Longest name the server keeps (`Holiday.NAME_MAX`).
  static const int nameMax = 120;

  /// Most holidays one calendar holds in a year (`Holiday.PER_YEAR_MAX`).
  static const int perYearMax = 100;

  final String id;
  final String calendarId;
  final DateTime date;
  final String name;
  final bool halfDay;

  /// Came from the feed rather than by hand.
  final bool imported;

  static Holiday? fromJson(Map<String, dynamic> json) {
    final date = parseDate(json['date']);
    if (date == null) return null;
    return Holiday(
      id: json['id'] as String? ?? '',
      calendarId: json['calendarId'] as String? ?? '',
      date: date,
      name: json['name'] as String? ?? '',
      halfDay: json['halfDay'] as bool? ?? false,
      imported: json['source'] == 'IMPORT',
    );
  }

  @override
  List<Object?> get props => [id, calendarId, date, name, halfDay, imported];
}

/// The one date comparison this file needs, without pulling in Flutter.
abstract final class DateUtilsLite {
  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
