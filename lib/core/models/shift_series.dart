/// Recurring events of the shift planning module (HIN-161).
///
/// A series is a rule plus what every occurrence looks like; the server turns
/// it into ordinary events ahead of time. The app builds the rule
/// ([SeriesRule]) and sends wall clocks; what the rule reads like in words
/// ([ShiftSeries.recurrenceLabel], [SeriesPreview.recurrenceLabel]) always
/// comes from the server.
library;

import 'package:equatable/equatable.dart';

import '../util/dates.dart';
import 'shift_models.dart' show parseLocalWallClock;

String _two(int v) => v.toString().padLeft(2, '0');

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// A wall clock without zone or seconds, the way a draft sends it.
String seriesWallClock(DateTime t) =>
    '${_date(t)}T${_two(t.hour)}:${_two(t.minute)}';

/// Minutes after midnight from `18:00` or `18:00:00`; null for anything else.
int? parseSeriesTime(Object? value) {
  if (value is! String) return null;
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return null;
  }
  return h * 60 + m;
}

String _time(int minutes) => '${_two(minutes ~/ 60)}:${_two(minutes % 60)}';

DateTime? _day(Object? value) {
  if (value is! String || value.length < 10) return null;
  final parsed = DateTime.tryParse(value.substring(0, 10));
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}

/// How often a series repeats.
enum SeriesFrequency {
  daily('DAILY'),
  weekly('WEEKLY'),
  monthly('MONTHLY');

  const SeriesFrequency(this.wire);

  final String wire;

  static SeriesFrequency? parse(String? value) {
    for (final f in values) {
      if (f.wire == value) return f;
    }
    return null;
  }
}

/// The RFC 5545 rule of a series, in the subset the server takes:
/// `FREQ=DAILY|WEEKLY|MONTHLY`, `INTERVAL` 1 to 100, `BYDAY` only for a
/// weekly rule and only plain weekdays, exactly one `BYMONTHDAY` for a
/// monthly one, and an end either as `COUNT` (1 to 5000) or as `UNTIL` (a
/// date), never both.
class SeriesRule extends Equatable {
  const SeriesRule({
    required this.frequency,
    this.interval = 1,
    this.weekdays = const {},
    this.monthDay,
    this.count,
    this.until,
  });

  /// Every day.
  const SeriesRule.daily() : this(frequency: SeriesFrequency.daily);

  /// Every week on [start]'s weekday.
  SeriesRule.weekly(DateTime start)
    : this(frequency: SeriesFrequency.weekly, weekdays: {start.weekday});

  /// Every month on [start]'s day of the month.
  SeriesRule.monthly(DateTime start)
    : this(frequency: SeriesFrequency.monthly, monthDay: start.day);

  static const int maxInterval = 100;
  static const int maxCount = 5000;

  final SeriesFrequency frequency;

  /// Every how many days, weeks or months.
  final int interval;

  /// [DateTime.monday] to [DateTime.sunday]; a weekly rule only. Empty means
  /// the weekday of the first occurrence.
  final Set<int> weekdays;

  /// The day of the month; a monthly rule only.
  final int? monthDay;

  /// How many occurrences in all, or null.
  final int? count;

  /// The last day an occurrence may fall on, or null.
  final DateTime? until;

  static const List<String> _days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

  /// The rule as the server takes it, without the `RRULE:` prefix.
  String toRrule() {
    final parts = <String>['FREQ=${frequency.wire}'];
    final step = interval.clamp(1, maxInterval);
    if (step > 1) parts.add('INTERVAL=$step');
    if (frequency == SeriesFrequency.weekly && weekdays.isNotEmpty) {
      final sorted = weekdays.where((d) => d >= 1 && d <= 7).toList()..sort();
      parts.add('BYDAY=${sorted.map((d) => _days[d - 1]).join(',')}');
    }
    if (frequency == SeriesFrequency.monthly && monthDay != null) {
      parts.add('BYMONTHDAY=${monthDay!.clamp(1, 31)}');
    }
    if (count != null) {
      parts.add('COUNT=${count!.clamp(1, maxCount)}');
    } else if (until != null) {
      final u = until!;
      parts.add(
        'UNTIL=${u.year.toString().padLeft(4, '0')}${_two(u.month)}${_two(u.day)}',
      );
    }
    return parts.join(';');
  }

  /// Reads a rule the server holds; null for one outside the subset.
  static SeriesRule? parse(String? rrule) {
    if (rrule == null || rrule.trim().isEmpty) return null;
    final body = rrule.trim().replaceFirst(RegExp('^RRULE:'), '');
    final fields = <String, String>{};
    for (final part in body.split(';')) {
      final i = part.indexOf('=');
      if (i > 0) {
        fields[part.substring(0, i).toUpperCase()] = part.substring(i + 1);
      }
    }
    final frequency = SeriesFrequency.parse(fields['FREQ']);
    if (frequency == null) return null;
    final weekdays = <int>{};
    for (final d in (fields['BYDAY'] ?? '').split(',')) {
      final i = _days.indexOf(d.trim().toUpperCase());
      if (i >= 0) weekdays.add(i + 1);
    }
    DateTime? until;
    final u = fields['UNTIL'];
    if (u != null && u.length >= 8) {
      final y = int.tryParse(u.substring(0, 4));
      final m = int.tryParse(u.substring(4, 6));
      final d = int.tryParse(u.substring(6, 8));
      if (y != null && m != null && d != null) until = DateTime(y, m, d);
    }
    final count = int.tryParse(fields['COUNT'] ?? '');
    return SeriesRule(
      frequency: frequency,
      interval: int.tryParse(fields['INTERVAL'] ?? '') ?? 1,
      weekdays: frequency == SeriesFrequency.weekly ? weekdays : const {},
      monthDay: frequency == SeriesFrequency.monthly
          ? int.tryParse(fields['BYMONTHDAY'] ?? '')
          : null,
      count: count,
      until: count == null ? until : null,
    );
  }

  SeriesRule copyWith({
    SeriesFrequency? frequency,
    int? interval,
    Set<int>? weekdays,
    int? monthDay,
  }) => SeriesRule(
    frequency: frequency ?? this.frequency,
    interval: interval ?? this.interval,
    weekdays: weekdays ?? this.weekdays,
    monthDay: monthDay ?? this.monthDay,
    count: count,
    until: until,
  );

  /// The same rule with another end: after [count] occurrences, on [until],
  /// or (both null) none.
  SeriesRule withEnd({int? count, DateTime? until}) => SeriesRule(
    frequency: frequency,
    interval: interval,
    weekdays: weekdays,
    monthDay: monthDay,
    count: count,
    until: count == null ? until : null,
  );

  @override
  List<Object?> get props => [
    frequency,
    interval,
    weekdays,
    monthDay,
    count,
    until,
  ];
}

/// One shift of every occurrence (`TemplateDraft`, `TemplateResponse`), in
/// wall clocks of the series' zone. An end at or before the start is on the
/// next day.
class SeriesTemplate extends Equatable {
  const SeriesTemplate({
    this.key,
    required this.title,
    this.dayOffset = 0,
    required this.startMinutes,
    required this.endMinutes,
    this.requiredHelpers = 1,
    this.maxHelpers,
  });

  /// Stable per template; null lets the server give one.
  final String? key;
  final String title;

  /// The day within the occurrence, 0 for its first.
  final int dayOffset;
  final int startMinutes;
  final int endMinutes;
  final int requiredHelpers;
  final int? maxHelpers;

  factory SeriesTemplate.fromJson(Map<String, dynamic> json) => SeriesTemplate(
    key: json['key'] as String?,
    title: json['title'] as String? ?? '',
    dayOffset: (json['dayOffset'] as num?)?.toInt() ?? 0,
    startMinutes: parseSeriesTime(json['start']) ?? 0,
    endMinutes: parseSeriesTime(json['end']) ?? 0,
    requiredHelpers: (json['requiredHelpers'] as num?)?.toInt() ?? 1,
    maxHelpers: (json['maxHelpers'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'title': title.trim(),
    'dayOffset': dayOffset,
    'start': _time(startMinutes),
    'end': _time(endMinutes),
    'requiredHelpers': requiredHelpers,
    'maxHelpers': maxHelpers,
  };

  @override
  List<Object?> get props => [
    key,
    title,
    dayOffset,
    startMinutes,
    endMinutes,
    requiredHelpers,
    maxHelpers,
  ];
}

/// A new series, or a draft to preview (`SeriesDraft`).
class SeriesDraft extends Equatable {
  const SeriesDraft({
    required this.title,
    required this.firstStart,
    required this.durationMinutes,
    required this.rule,
    this.description,
    this.location,
    this.timezone,
    this.selfAssignable = true,
    this.shifts = const [],
  });

  final String title;

  /// The wall clock of the first occurrence in [timezone].
  final DateTime firstStart;
  final int durationMinutes;
  final SeriesRule rule;
  final String? description;
  final String? location;

  /// Null lets the server take the creator's zone.
  final String? timezone;
  final bool selfAssignable;
  final List<SeriesTemplate> shifts;

  Map<String, dynamic> toJson() {
    String? text(String? v) {
      final t = v?.trim();
      return t == null || t.isEmpty ? null : t;
    }

    return {
      'title': title.trim(),
      'description': text(description),
      'location': text(location),
      'timezone': ?timezone,
      'firstStart': seriesWallClock(firstStart),
      'durationMinutes': durationMinutes,
      'rrule': rule.toRrule(),
      'selfAssignable': selfAssignable,
      'shifts': [for (final s in shifts) s.toJson()],
    };
  }

  @override
  List<Object?> get props => [
    title,
    firstStart,
    durationMinutes,
    rule,
    description,
    location,
    timezone,
    selfAssignable,
    shifts,
  ];
}

/// One upcoming occurrence (`OccurrenceResponse`).
class SeriesOccurrence extends Equatable {
  const SeriesOccurrence({
    required this.date,
    required this.startsAt,
    required this.endsAt,
    required this.startsLocal,
    required this.endsLocal,
  });

  /// Its day in the series' zone.
  final DateTime date;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime startsLocal;
  final DateTime endsLocal;

  factory SeriesOccurrence.fromJson(Map<String, dynamic> json) {
    final startsAt = parseInstant(json['startsAt']) ?? DateTime(1970);
    final endsAt = parseInstant(json['endsAt']) ?? startsAt;
    final startsLocal = parseLocalWallClock(json['startsLocal']) ?? startsAt;
    return SeriesOccurrence(
      date:
          _day(json['date']) ??
          DateTime(startsLocal.year, startsLocal.month, startsLocal.day),
      startsAt: startsAt,
      endsAt: endsAt,
      startsLocal: startsLocal,
      endsLocal: parseLocalWallClock(json['endsLocal']) ?? endsAt,
    );
  }

  static List<SeriesOccurrence> listFromJson(Object? value) => [
    if (value is List)
      for (final item in value)
        if (item is Map<String, dynamic>) SeriesOccurrence.fromJson(item),
  ];

  @override
  List<Object?> get props => [date, startsAt, endsAt, startsLocal, endsLocal];
}

/// What a draft would make, saved nowhere (`PreviewResponse`).
class SeriesPreview extends Equatable {
  const SeriesPreview({required this.recurrenceLabel, this.next = const []});

  final String recurrenceLabel;
  final List<SeriesOccurrence> next;

  factory SeriesPreview.fromJson(Map<String, dynamic> json) => SeriesPreview(
    recurrenceLabel: json['recurrenceLabel'] as String? ?? '',
    next: SeriesOccurrence.listFromJson(json['next']),
  );

  @override
  List<Object?> get props => [recurrenceLabel, next];
}

/// A series (`SeriesResponse`).
class ShiftSeries extends Equatable {
  const ShiftSeries({
    required this.id,
    required this.projectId,
    required this.title,
    required this.firstStart,
    required this.durationMinutes,
    required this.rrule,
    required this.recurrenceLabel,
    this.timezone,
    this.exdates = const [],
    this.shifts = const [],
    this.selfAssignable = true,
    this.finished = false,
    this.canPlan = false,
    this.next = const [],
    this.occurrencesCreated,
  });

  final String id;
  final String projectId;
  final String title;
  final DateTime firstStart;
  final int durationMinutes;
  final String rrule;
  final String recurrenceLabel;
  final String? timezone;
  final List<DateTime> exdates;
  final List<SeriesTemplate> shifts;
  final bool selfAssignable;
  final bool finished;
  final bool canPlan;

  /// The next five occurrences from today on.
  final List<SeriesOccurrence> next;

  /// How many occurrences creating it brought; only in the answer to that.
  final int? occurrencesCreated;

  /// [rrule] read back, or null when it is outside the app's subset.
  SeriesRule? get rule => SeriesRule.parse(rrule);

  factory ShiftSeries.fromJson(Map<String, dynamic> json) => ShiftSeries(
    id: json['id'] as String? ?? '',
    projectId: json['projectId'] as String? ?? '',
    title: json['title'] as String? ?? '',
    firstStart: parseLocalWallClock(json['firstStart']) ?? DateTime(1970),
    durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
    rrule: json['rrule'] as String? ?? '',
    recurrenceLabel: json['recurrenceLabel'] as String? ?? '',
    timezone: json['timezone'] as String?,
    exdates: [for (final d in (json['exdates'] as List?) ?? const []) ?_day(d)],
    shifts: [
      for (final s in (json['shifts'] as List?) ?? const [])
        if (s is Map<String, dynamic>) SeriesTemplate.fromJson(s),
    ],
    selfAssignable: json['selfAssignable'] as bool? ?? true,
    finished: json['finished'] as bool? ?? false,
    canPlan: json['canPlan'] as bool? ?? false,
    next: SeriesOccurrence.listFromJson(json['next']),
    occurrencesCreated: (json['occurrencesCreated'] as num?)?.toInt(),
  );

  @override
  List<Object?> get props => [
    id,
    projectId,
    title,
    firstStart,
    durationMinutes,
    rrule,
    recurrenceLabel,
    timezone,
    exdates,
    shifts,
    selfAssignable,
    finished,
    canPlan,
    next,
    occurrencesCreated,
  ];
}
