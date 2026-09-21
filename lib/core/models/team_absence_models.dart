import 'package:equatable/equatable.dart';

import '../util/dates.dart';
import 'time_policy_models.dart';

/// The team absence calendar and its capacity band (HIN-118).
///
/// Everything here arrives coarsened. The server applies the calendar level
/// and each type's own visibility before it builds a row, so a type the reader
/// may not know is absent from the JSON, not hidden by the app — and sickness
/// never arrives as sickness. Nothing in this file decides what to show.

/// One absence or open request on a person's row. The type fields are all
/// null when the reader may only know that the person is away.
class TeamAbsenceEntry extends Equatable {
  const TeamAbsenceEntry({
    required this.from,
    required this.to,
    this.halfDay = false,
    this.requested = false,
    this.typeId,
    this.typeKey,
    this.typeSystemKey,
    this.typeName,
    this.icon,
    this.hue,
  });

  final DateTime from;
  final DateTime to;
  final bool halfDay;

  /// Asked for and not decided yet: drawn hatched, and it lowers no capacity.
  final bool requested;
  final String? typeId;
  final String? typeKey;
  final String? typeSystemKey;
  final String? typeName;
  final String? icon;
  final int? hue;

  /// Whether the reader sees the type or only that the person is away.
  bool get typed => typeId != null;

  bool covers(DateTime day) => !day.isBefore(from) && !day.isAfter(to);

  factory TeamAbsenceEntry.fromJson(Map<String, dynamic> json) =>
      TeamAbsenceEntry(
        from: parseDate(json['from'])!,
        to: parseDate(json['to'])!,
        halfDay: json['halfDay'] as bool? ?? false,
        requested: json['requested'] as bool? ?? false,
        typeId: json['typeId'] as String?,
        typeKey: json['typeKey'] as String?,
        typeSystemKey: json['typeSystemKey'] as String?,
        typeName: json['typeName'] as String?,
        icon: json['icon'] as String?,
        hue: (json['hue'] as num?)?.toInt(),
      );

  @override
  List<Object?> get props => [
    from,
    to,
    halfDay,
    requested,
    typeId,
    typeKey,
    typeSystemKey,
    typeName,
    icon,
    hue,
  ];
}

/// A holiday on one person's row, from the calendar they follow that day.
class TeamAbsenceHoliday extends Equatable {
  const TeamAbsenceHoliday({
    required this.date,
    required this.name,
    this.halfDay = false,
  });

  final DateTime date;
  final String name;
  final bool halfDay;

  factory TeamAbsenceHoliday.fromJson(Map<String, dynamic> json) =>
      TeamAbsenceHoliday(
        date: parseDate(json['date'])!,
        name: json['name'] as String? ?? '',
        halfDay: json['halfDay'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [date, name, halfDay];
}

class TeamAbsenceRow extends Equatable {
  const TeamAbsenceRow({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.holidays = const [],
    this.entries = const [],
  });

  final String userId;
  final String name;
  final String? avatarUrl;
  final List<TeamAbsenceHoliday> holidays;
  final List<TeamAbsenceEntry> entries;

  factory TeamAbsenceRow.fromJson(Map<String, dynamic> json) => TeamAbsenceRow(
    userId: json['userId'] as String,
    name: json['name'] as String? ?? '',
    avatarUrl: json['avatarUrl'] as String?,
    holidays: [
      for (final raw in (json['holidays'] as List<dynamic>?) ?? const [])
        TeamAbsenceHoliday.fromJson(raw as Map<String, dynamic>),
    ],
    entries: [
      for (final raw in (json['entries'] as List<dynamic>?) ?? const [])
        TeamAbsenceEntry.fromJson(raw as Map<String, dynamic>),
    ],
  );

  @override
  List<Object?> get props => [userId, name, avatarUrl, holidays, entries];
}

/// One page of rows and what the calendar needs once.
class TeamAbsencePage extends Equatable {
  const TeamAbsencePage({
    required this.rows,
    required this.total,
    required this.level,
    this.truncated = false,
  });

  final List<TeamAbsenceRow> rows;
  final int total;
  final AbsenceCalendarLevel level;

  /// The group had more people than one calendar reads; the first ones by id
  /// are shown.
  final bool truncated;

  factory TeamAbsencePage.fromJson(Map<String, dynamic> json) =>
      TeamAbsencePage(
        rows: [
          for (final raw in (json['content'] as List<dynamic>?) ?? const [])
            TeamAbsenceRow.fromJson(raw as Map<String, dynamic>),
        ],
        total: (json['totalElements'] as num?)?.toInt() ?? 0,
        level: AbsenceCalendarLevel.fromWire(json['visibility'] as String?),
        truncated: json['truncated'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [rows, total, level, truncated];
}

/// Which group a calendar reads: a team, a project, or the reader's own
/// projects when neither is named.
class TeamAbsenceScope extends Equatable {
  const TeamAbsenceScope({this.teamId, this.projectId, this.label});

  /// The people of the reader's own projects.
  static const mine = TeamAbsenceScope();

  final String? teamId;
  final String? projectId;

  /// What the picker shows; null for [mine].
  final String? label;

  Map<String, Object> get query => {'teamId': ?teamId, 'projectId': ?projectId};

  @override
  List<Object?> get props => [teamId, projectId];
}

/// How finely the band adds up.
enum CapacityResolution {
  day('DAY'),
  week('WEEK');

  const CapacityResolution(this.wire);

  final String wire;
}

/// One day or week of the band: sums, never a person. [away] and [requested]
/// are the most people away on any day of the bucket.
class CapacityBucket extends Equatable {
  const CapacityBucket({
    required this.from,
    required this.to,
    required this.scheduledMinutes,
    required this.capacityMinutes,
    this.away = 0,
    this.requested = 0,
  });

  final DateTime from;
  final DateTime to;
  final int scheduledMinutes;
  final int capacityMinutes;
  final int away;
  final int requested;

  /// What is left, from 0 to 1; 1 where nothing was planned.
  double get share =>
      scheduledMinutes <= 0 ? 1 : capacityMinutes / scheduledMinutes;

  factory CapacityBucket.fromJson(Map<String, dynamic> json) => CapacityBucket(
    from: parseDate(json['from'])!,
    to: parseDate(json['to'])!,
    scheduledMinutes: (json['scheduledMinutes'] as num?)?.toInt() ?? 0,
    capacityMinutes: (json['capacityMinutes'] as num?)?.toInt() ?? 0,
    away: (json['away'] as num?)?.toInt() ?? 0,
    requested: (json['requested'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [
    from,
    to,
    scheduledMinutes,
    capacityMinutes,
    away,
    requested,
  ];
}

class CapacityBand extends Equatable {
  const CapacityBand({
    required this.resolution,
    required this.people,
    required this.buckets,
    this.truncated = false,
  });

  final CapacityResolution resolution;
  final int people;
  final bool truncated;
  final List<CapacityBucket> buckets;

  factory CapacityBand.fromJson(Map<String, dynamic> json) => CapacityBand(
    resolution: json['resolution'] == 'WEEK'
        ? CapacityResolution.week
        : CapacityResolution.day,
    people: (json['people'] as num?)?.toInt() ?? 0,
    truncated: json['truncated'] as bool? ?? false,
    buckets: [
      for (final raw in (json['buckets'] as List<dynamic>?) ?? const [])
        CapacityBucket.fromJson(raw as Map<String, dynamic>),
    ],
  );

  @override
  List<Object?> get props => [resolution, people, truncated, buckets];
}
