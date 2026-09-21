import 'package:equatable/equatable.dart';

import '../util/dates.dart';

/// Time reports (HIN-93): what a report asks, what it answers, and the saved,
/// shared and scheduled forms of the question.
///
/// Every number here was computed by the server in the reader's own scope. A
/// group the reader may not see as a person never arrives as one; nothing in
/// this file decides what somebody may see.

/// What a summary is grouped by. [readsPeople] groups by person and are
/// offered only when the server says the reader may see somebody else's rows.
enum ReportGroupBy {
  project('PROJECT', 'time.reports.group.project'),
  user('USER', 'time.reports.group.user', readsPeople: true),
  team('TEAM', 'time.reports.group.team', readsPeople: true),
  activity('ACTIVITY', 'time.reports.group.activity'),
  tag('TAG', 'time.reports.group.tag'),
  issue('ISSUE', 'time.reports.group.issue'),
  day('DAY', 'time.reports.group.day', time: true),
  week('WEEK', 'time.reports.group.week', time: true),
  month('MONTH', 'time.reports.group.month', time: true);

  const ReportGroupBy(
    this.wire,
    this.labelKey, {
    this.readsPeople = false,
    this.time = false,
  });

  final String wire;
  final String labelKey;
  final bool readsPeople;

  /// Buckets of days, drawn as a line rather than as slices.
  final bool time;

  static ReportGroupBy parse(Object? value) => values.firstWhere(
    (group) => group.wire == value,
    orElse: () => ReportGroupBy.project,
  );
}

/// The window a report covers. Relative ones move with the day they are
/// opened; [custom] keeps its two days.
enum ReportRange {
  thisWeek('THIS_WEEK', 'time.reports.range.thisWeek'),
  lastWeek('LAST_WEEK', 'time.reports.range.lastWeek'),
  thisMonth('THIS_MONTH', 'time.reports.range.thisMonth'),
  lastMonth('LAST_MONTH', 'time.reports.range.lastMonth'),
  last30Days('LAST_30_DAYS', 'time.reports.range.last30Days'),
  thisYear('THIS_YEAR', 'time.reports.range.thisYear'),
  custom('CUSTOM', 'time.reports.range.custom');

  const ReportRange(this.wire, this.labelKey);

  final String wire;
  final String labelKey;

  static ReportRange parse(Object? value) => values.firstWhere(
    (range) => range.wire == value,
    orElse: () => ReportRange.thisMonth,
  );

  /// The two days this range covers around [today], weeks starting on
  /// [weekStart] (1 = Monday). The same arithmetic the server does for a
  /// saved report, so the screen and the mail agree on "last week".
  (DateTime, DateTime) window(DateTime today, {int weekStart = 1}) {
    final day = dateOnly(today);
    final offset = (day.weekday - weekStart) % 7;
    final monday = day.subtract(Duration(days: offset));
    return switch (this) {
      thisWeek => (monday, monday.add(const Duration(days: 6))),
      lastWeek => (
        monday.subtract(const Duration(days: 7)),
        monday.subtract(const Duration(days: 1)),
      ),
      thisMonth => (
        DateTime(day.year, day.month),
        DateTime(day.year, day.month + 1, 0),
      ),
      lastMonth => (
        DateTime(day.year, day.month - 1),
        DateTime(day.year, day.month, 0),
      ),
      last30Days => (day.subtract(const Duration(days: 29)), day),
      thisYear => (DateTime(day.year), DateTime(day.year, 12, 31)),
      custom => (day, day),
    };
  }
}

enum ReportChart {
  bar('BAR', 'time.reports.chart.bar'),
  pie('PIE', 'time.reports.chart.pie'),
  line('LINE', 'time.reports.chart.line');

  const ReportChart(this.wire, this.labelKey);

  final String wire;
  final String labelKey;

  static ReportChart parse(Object? value) => values.firstWhere(
    (chart) => chart.wire == value,
    orElse: () => ReportChart.bar,
  );
}

/// The state of the period an entry sits in for its person and project.
enum ReportApproval {
  open('OPEN', 'time.reports.approval.open'),
  submitted('SUBMITTED', 'time.reports.approval.submitted'),
  approved('APPROVED', 'time.reports.approval.approved'),
  rejected('REJECTED', 'time.reports.approval.rejected');

  const ReportApproval(this.wire, this.labelKey);

  final String wire;
  final String labelKey;

  static ReportApproval? parse(Object? value) {
    for (final state in values) {
      if (state.wire == value) return state;
    }
    return null;
  }
}

/// How each entry is folded before it is added up. [policy] sends nothing and
/// takes the operator's default.
enum ReportRounding {
  policy(null, 'time.reports.rounding.policy'),
  none('NONE', 'time.reports.rounding.none'),
  up('UP', 'time.reports.rounding.up'),
  down('DOWN', 'time.reports.rounding.down'),
  nearest('NEAREST', 'time.reports.rounding.nearest');

  const ReportRounding(this.wire, this.labelKey);

  final String? wire;
  final String labelKey;

  static ReportRounding parse(Object? value) => values.firstWhere(
    (mode) => mode.wire == value,
    orElse: () => ReportRounding.policy,
  );
}

/// A report's question: its window, its filters, how it is grouped and drawn.
class ReportQuery extends Equatable {
  const ReportQuery({
    this.range = ReportRange.thisMonth,
    this.from,
    this.to,
    this.projectIds = const [],
    this.userIds = const [],
    this.teamIds = const [],
    this.tags = const [],
    this.billable,
    this.activities = const [],
    this.text,
    this.approval = const {},
    this.rounding = ReportRounding.policy,
    this.roundingIncrement = 15,
    this.groupBy = ReportGroupBy.project,
    this.chart = ReportChart.bar,
  });

  final ReportRange range;

  /// The days of a [ReportRange.custom] range; ignored otherwise.
  final DateTime? from;
  final DateTime? to;
  final List<String> projectIds;
  final List<String> userIds;
  final List<String> teamIds;
  final List<String> tags;
  final bool? billable;
  final List<String> activities;

  /// A word the description must contain.
  final String? text;
  final Set<ReportApproval> approval;
  final ReportRounding rounding;
  final int roundingIncrement;
  final ReportGroupBy groupBy;
  final ReportChart chart;

  /// How many filters narrow the report beyond its window.
  int get filterCount =>
      (projectIds.isEmpty ? 0 : 1) +
      (userIds.isEmpty ? 0 : 1) +
      (teamIds.isEmpty ? 0 : 1) +
      (tags.isEmpty ? 0 : 1) +
      (billable == null ? 0 : 1) +
      (activities.isEmpty ? 0 : 1) +
      ((text ?? '').isEmpty ? 0 : 1) +
      (approval.isEmpty ? 0 : 1);

  /// The two days covered on [today].
  (DateTime, DateTime) window(DateTime today, {int weekStart = 1}) =>
      range == ReportRange.custom && from != null && to != null
      ? (dateOnly(from!), dateOnly(to!))
      : range.window(today, weekStart: weekStart);

  /// The query parameters of every report route, with the window of [today].
  Map<String, dynamic> toQuery(DateTime today, {int weekStart = 1}) {
    final (start, end) = window(today, weekStart: weekStart);
    return {
      'from': formatDateOnly(start),
      'to': formatDateOnly(end),
      if (projectIds.isNotEmpty) 'projectIds': projectIds,
      if (userIds.isNotEmpty) 'userIds': userIds,
      if (teamIds.isNotEmpty) 'teamIds': teamIds,
      if (tags.isNotEmpty) 'tags': tags,
      if (billable != null) 'billable': billable,
      if (activities.isNotEmpty) 'activities': activities,
      if ((text ?? '').trim().isNotEmpty) 'q': text!.trim(),
      if (approval.isNotEmpty)
        'approval': [for (final state in approval) state.wire],
      if (rounding.wire != null) 'rounding': rounding.wire,
      if (rounding.wire != null) 'roundingIncrement': roundingIncrement,
    };
  }

  /// The config a saved report stores.
  Map<String, dynamic> toConfig() => {
    'range': range.wire,
    if (range == ReportRange.custom && from != null)
      'from': formatDateOnly(from!),
    if (range == ReportRange.custom && to != null) 'to': formatDateOnly(to!),
    'projectIds': projectIds,
    'userIds': userIds,
    'teamIds': teamIds,
    'tags': tags,
    'billable': ?billable,
    'activities': activities,
    if ((text ?? '').trim().isNotEmpty) 'q': text!.trim(),
    if (approval.isNotEmpty)
      'approval': [for (final state in approval) state.wire],
    'rounding': ?rounding.wire,
    if (rounding.wire != null) 'roundingIncrement': roundingIncrement,
    'groupBy': groupBy.wire,
    'chart': chart.wire,
  };

  factory ReportQuery.fromConfig(Map<String, dynamic> json) => ReportQuery(
    range: ReportRange.parse(json['range']),
    from: parseDate(json['from']),
    to: parseDate(json['to']),
    projectIds: _strings(json['projectIds']),
    userIds: _strings(json['userIds']),
    teamIds: _strings(json['teamIds']),
    tags: _strings(json['tags']),
    billable: json['billable'] as bool?,
    activities: _strings(json['activities']),
    text: json['q'] as String?,
    approval: {
      for (final raw in (json['approval'] as List<dynamic>?) ?? const [])
        ?ReportApproval.parse(raw),
    },
    rounding: ReportRounding.parse(json['rounding']),
    roundingIncrement: (json['roundingIncrement'] as num?)?.toInt() ?? 15,
    groupBy: ReportGroupBy.parse(json['groupBy']),
    chart: ReportChart.parse(json['chart']),
  );

  static const _unset = Object();

  ReportQuery copyWith({
    ReportRange? range,
    Object? from = _unset,
    Object? to = _unset,
    List<String>? projectIds,
    List<String>? userIds,
    List<String>? teamIds,
    List<String>? tags,
    Object? billable = _unset,
    List<String>? activities,
    Object? text = _unset,
    Set<ReportApproval>? approval,
    ReportRounding? rounding,
    int? roundingIncrement,
    ReportGroupBy? groupBy,
    ReportChart? chart,
  }) => ReportQuery(
    range: range ?? this.range,
    from: identical(from, _unset) ? this.from : from as DateTime?,
    to: identical(to, _unset) ? this.to : to as DateTime?,
    projectIds: projectIds ?? this.projectIds,
    userIds: userIds ?? this.userIds,
    teamIds: teamIds ?? this.teamIds,
    tags: tags ?? this.tags,
    billable: identical(billable, _unset) ? this.billable : billable as bool?,
    activities: activities ?? this.activities,
    text: identical(text, _unset) ? this.text : text as String?,
    approval: approval ?? this.approval,
    rounding: rounding ?? this.rounding,
    roundingIncrement: roundingIncrement ?? this.roundingIncrement,
    groupBy: groupBy ?? this.groupBy,
    chart: chart ?? this.chart,
  );

  /// The same question without any filter: window, grouping and chart kept.
  ReportQuery cleared() => ReportQuery(
    range: range,
    from: from,
    to: to,
    rounding: rounding,
    roundingIncrement: roundingIncrement,
    groupBy: groupBy,
    chart: chart,
  );

  @override
  List<Object?> get props => [
    range,
    from,
    to,
    projectIds,
    userIds,
    teamIds,
    tags,
    billable,
    activities,
    text,
    approval,
    rounding,
    roundingIncrement,
    groupBy,
    chart,
  ];
}

class ReportTotals extends Equatable {
  const ReportTotals({
    this.minutes = 0,
    this.filedMinutes = 0,
    this.billableMinutes = 0,
    this.entries = 0,
  });

  /// Rounded per entry, then added up.
  final int minutes;

  /// As recorded.
  final int filedMinutes;
  final int billableMinutes;
  final int entries;

  bool get rounded => minutes != filedMinutes;

  factory ReportTotals.fromJson(Map<String, dynamic> json) => ReportTotals(
    minutes: (json['minutes'] as num?)?.toInt() ?? 0,
    filedMinutes: (json['filedMinutes'] as num?)?.toInt() ?? 0,
    billableMinutes: (json['billableMinutes'] as num?)?.toInt() ?? 0,
    entries: (json['entries'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [minutes, filedMinutes, billableMinutes, entries];
}

/// One group of a summary.
class ReportGroup extends Equatable {
  const ReportGroup({
    this.key,
    this.label,
    this.detail,
    this.minutes = 0,
    this.billableMinutes = 0,
    this.entries = 0,
  });

  /// The id, the name, or the first day of a bucket; null for "none".
  final String? key;

  /// What the key reads as; null where the key is its own label.
  final String? label;

  /// A second line: a project key, an issue's readable id, a username.
  final String? detail;
  final int minutes;
  final int billableMinutes;
  final int entries;

  /// The first day of a time bucket.
  DateTime? get day => parseDate(key);

  factory ReportGroup.fromJson(Map<String, dynamic> json) => ReportGroup(
    key: json['key'] as String?,
    label: json['label'] as String?,
    detail: json['detail'] as String?,
    minutes: (json['minutes'] as num?)?.toInt() ?? 0,
    billableMinutes: (json['billableMinutes'] as num?)?.toInt() ?? 0,
    entries: (json['entries'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [
    key,
    label,
    detail,
    minutes,
    billableMinutes,
    entries,
  ];
}

/// Totals and one page of groups.
class ReportSummary extends Equatable {
  const ReportSummary({
    this.totals = const ReportTotals(),
    this.groupBy = ReportGroupBy.project,
    this.groups = const [],
    this.groupCount = 0,
    this.people = false,
  });

  final ReportTotals totals;
  final ReportGroupBy groupBy;
  final List<ReportGroup> groups;
  final int groupCount;

  /// Whether the reader may see anybody's entries but their own.
  final bool people;

  factory ReportSummary.fromJson(Map<String, dynamic> json) {
    final page = json['groups'] as Map<String, dynamic>? ?? const {};
    return ReportSummary(
      totals: ReportTotals.fromJson(
        json['totals'] as Map<String, dynamic>? ?? const {},
      ),
      groupBy: ReportGroupBy.parse(json['groupBy']),
      groups: [
        for (final raw in (page['content'] as List<dynamic>?) ?? const [])
          ReportGroup.fromJson(raw as Map<String, dynamic>),
      ],
      groupCount: (page['totalElements'] as num?)?.toInt() ?? 0,
      people: json['people'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [totals, groupBy, groups, groupCount, people];
}

/// One entry of a detailed report, names already resolved.
class ReportEntry extends Equatable {
  const ReportEntry({
    required this.id,
    required this.date,
    this.startedAt,
    this.endedAt,
    this.minutes = 0,
    this.roundedMinutes = 0,
    this.userId,
    this.userName,
    this.projectId,
    this.projectKey,
    this.projectName,
    this.issueId,
    this.issueKey,
    this.issueTitle,
    this.activity,
    this.description,
    this.tags = const [],
    this.billable = false,
  });

  final String id;
  final DateTime date;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int minutes;
  final int roundedMinutes;
  final String? userId;
  final String? userName;
  final String? projectId;
  final String? projectKey;
  final String? projectName;
  final String? issueId;
  final String? issueKey;
  final String? issueTitle;
  final String? activity;
  final String? description;
  final List<String> tags;
  final bool billable;

  factory ReportEntry.fromJson(Map<String, dynamic> json) => ReportEntry(
    id: json['id'] as String? ?? '',
    date: parseDate(json['date']) ?? DateTime(1970),
    startedAt: parseInstant(json['startedAt']),
    endedAt: parseInstant(json['endedAt']),
    minutes: (json['minutes'] as num?)?.toInt() ?? 0,
    roundedMinutes: (json['roundedMinutes'] as num?)?.toInt() ?? 0,
    userId: json['userId'] as String?,
    userName: json['userName'] as String?,
    projectId: json['projectId'] as String?,
    projectKey: json['projectKey'] as String?,
    projectName: json['projectName'] as String?,
    issueId: json['issueId'] as String?,
    issueKey: json['issueKey'] as String?,
    issueTitle: json['issueTitle'] as String?,
    activity: json['activity'] as String?,
    description: json['description'] as String?,
    tags: _strings(json['tags']),
    billable: json['billable'] as bool? ?? false,
  );

  @override
  List<Object?> get props => [id, date, minutes, roundedMinutes, description];
}

/// Booked time against capacity for one person.
class WorkloadRow extends Equatable {
  const WorkloadRow({
    required this.userId,
    required this.name,
    this.username,
    this.scheduledMinutes = 0,
    this.holidayMinutes = 0,
    this.absenceMinutes = 0,
    this.capacityMinutes = 0,
    this.bookedMinutes = 0,
    this.differenceMinutes = 0,
  });

  final String userId;
  final String name;
  final String? username;
  final int scheduledMinutes;
  final int holidayMinutes;
  final int absenceMinutes;
  final int capacityMinutes;
  final int bookedMinutes;

  /// Booked minus capacity, signed; the screen makes nothing more of it.
  final int differenceMinutes;

  factory WorkloadRow.fromJson(Map<String, dynamic> json) => WorkloadRow(
    userId: json['userId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    username: json['username'] as String?,
    scheduledMinutes: (json['scheduledMinutes'] as num?)?.toInt() ?? 0,
    holidayMinutes: (json['holidayMinutes'] as num?)?.toInt() ?? 0,
    absenceMinutes: (json['absenceMinutes'] as num?)?.toInt() ?? 0,
    capacityMinutes: (json['capacityMinutes'] as num?)?.toInt() ?? 0,
    bookedMinutes: (json['bookedMinutes'] as num?)?.toInt() ?? 0,
    differenceMinutes: (json['differenceMinutes'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [userId, capacityMinutes, bookedMinutes];
}

class WorkloadPage {
  const WorkloadPage({
    this.rows = const [],
    this.total = 0,
    this.truncated = false,
    this.bookedInLedProjects = false,
  });

  final List<WorkloadRow> rows;
  final int total;
  final bool truncated;

  /// Booked time counts only the reader's own projects (a lead).
  final bool bookedInLedProjects;

  factory WorkloadPage.fromJson(Map<String, dynamic> json) {
    final page = json['people'] as Map<String, dynamic>? ?? const {};
    return WorkloadPage(
      rows: [
        for (final raw in (page['content'] as List<dynamic>?) ?? const [])
          WorkloadRow.fromJson(raw as Map<String, dynamic>),
      ],
      total: (page['totalElements'] as num?)?.toInt() ?? 0,
      truncated: json['truncated'] as bool? ?? false,
      bookedInLedProjects: json['bookedInLedProjects'] as bool? ?? false,
    );
  }
}

enum ReportCadence {
  weekly('WEEKLY', 'time.reports.saved.weekly'),
  monthly('MONTHLY', 'time.reports.saved.monthly');

  const ReportCadence(this.wire, this.labelKey);

  final String wire;
  final String labelKey;

  static ReportCadence parse(Object? value) =>
      value == 'MONTHLY' ? ReportCadence.monthly : ReportCadence.weekly;
}

/// When a saved report is mailed, and to whom.
class ReportSchedule extends Equatable {
  const ReportSchedule({
    required this.cadence,
    this.weekday = DateTime.monday,
    this.hour = 7,
    this.recipients = const [],
  });

  final ReportCadence cadence;

  /// 1 = Monday, as [DateTime.weekday]; only for a weekly schedule.
  final int weekday;
  final int hour;
  final List<String> recipients;

  static const _days = [
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
    'SUNDAY',
  ];

  factory ReportSchedule.fromJson(Map<String, dynamic> json) => ReportSchedule(
    cadence: ReportCadence.parse(json['cadence']),
    weekday: _days.indexOf(json['dayOfWeek'] as String? ?? 'MONDAY') + 1,
    hour: (json['hour'] as num?)?.toInt() ?? 7,
    recipients: _strings(json['recipients']),
  );

  Map<String, dynamic> toJson() => {
    'cadence': cadence.wire,
    if (cadence == ReportCadence.weekly) 'dayOfWeek': _days[weekday - 1],
    'hour': hour,
    'recipients': recipients,
  };

  @override
  List<Object?> get props => [cadence, weekday, hour, recipients];
}

/// A saved report as its reader sees it.
class SavedReport extends Equatable {
  const SavedReport({
    required this.id,
    required this.name,
    required this.query,
    this.from,
    this.to,
    this.owned = true,
    this.shared = false,
    this.schedule,
    this.updatedAt,
  });

  final String id;
  final String name;
  final ReportQuery query;

  /// The window resolved by the server for today on the reader's clock.
  final DateTime? from;
  final DateTime? to;
  final bool owned;
  final bool shared;
  final ReportSchedule? schedule;
  final DateTime? updatedAt;

  factory SavedReport.fromJson(Map<String, dynamic> json) => SavedReport(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    query: ReportQuery.fromConfig(
      json['config'] as Map<String, dynamic>? ?? const {},
    ),
    from: parseDate(json['from']),
    to: parseDate(json['to']),
    owned: json['owned'] as bool? ?? true,
    shared: json['shared'] as bool? ?? false,
    schedule: json['schedule'] is Map<String, dynamic>
        ? ReportSchedule.fromJson(json['schedule'] as Map<String, dynamic>)
        : null,
    updatedAt: parseInstant(json['updatedAt']),
  );

  @override
  List<Object?> get props => [id, name, query, shared, schedule, updatedAt];
}

/// What a column of an imported file holds.
enum ImportColumn {
  date('DATE', 'time.import.column.date'),
  start('START', 'time.import.column.start'),
  end('END', 'time.import.column.end'),
  minutes('MINUTES', 'time.import.column.minutes'),
  hours('HOURS', 'time.import.column.hours'),
  duration('DURATION', 'time.import.column.duration'),
  project('PROJECT', 'time.import.column.project'),
  issue('ISSUE', 'time.import.column.issue'),
  activity('ACTIVITY', 'time.import.column.activity'),
  description('DESCRIPTION', 'time.import.column.description'),
  tags('TAGS', 'time.import.column.tags'),
  billable('BILLABLE', 'time.import.column.billable'),
  user('USER', 'time.import.column.user');

  const ImportColumn(this.wire, this.labelKey);

  final String wire;
  final String labelKey;

  static ImportColumn? parse(Object? value) {
    for (final column in values) {
      if (column.wire == value) return column;
    }
    return null;
  }
}

class ImportRowError extends Equatable {
  const ImportRowError({required this.line, required this.message});

  final int line;

  /// Already in the reader's language.
  final String message;

  factory ImportRowError.fromJson(Map<String, dynamic> json) => ImportRowError(
    line: (json['line'] as num?)?.toInt() ?? 0,
    message: json['message'] as String? ?? '',
  );

  @override
  List<Object?> get props => [line, message];
}

class ImportPreviewRow extends Equatable {
  const ImportPreviewRow({
    required this.line,
    this.date,
    this.minutes,
    this.project,
    this.issue,
    this.description,
    this.tags = const [],
    this.error,
  });

  final int line;
  final DateTime? date;
  final int? minutes;
  final String? project;
  final String? issue;
  final String? description;
  final List<String> tags;
  final String? error;

  factory ImportPreviewRow.fromJson(Map<String, dynamic> json) =>
      ImportPreviewRow(
        line: (json['line'] as num?)?.toInt() ?? 0,
        date: parseDate(json['date']),
        minutes: (json['minutes'] as num?)?.toInt(),
        project: json['project'] as String?,
        issue: json['issue'] as String?,
        description: json['description'] as String?,
        tags: _strings(json['tags']),
        error: json['error'] as String?,
      );

  @override
  List<Object?> get props => [line, date, minutes, error];
}

/// A checked file, before anything is written.
class ImportPreview extends Equatable {
  const ImportPreview({
    required this.importId,
    this.headers = const [],
    this.mapping = const {},
    this.totalRows = 0,
    this.validRows = 0,
    this.errorCount = 0,
    this.rows = const [],
    this.errors = const [],
  });

  final String importId;
  final List<String> headers;
  final Map<ImportColumn, int> mapping;
  final int totalRows;
  final int validRows;
  final int errorCount;
  final List<ImportPreviewRow> rows;
  final List<ImportRowError> errors;

  factory ImportPreview.fromJson(Map<String, dynamic> json) {
    final errors = json['errors'] as Map<String, dynamic>? ?? const {};
    return ImportPreview(
      importId: json['importId'] as String? ?? '',
      headers: _strings(json['headers']),
      mapping: {
        for (final entry
            in ((json['mapping'] as Map<String, dynamic>?) ?? const {}).entries)
          ?ImportColumn.parse(entry.key): (entry.value as num).toInt(),
      },
      totalRows: (json['totalRows'] as num?)?.toInt() ?? 0,
      validRows: (json['validRows'] as num?)?.toInt() ?? 0,
      errorCount: (json['errorCount'] as num?)?.toInt() ?? 0,
      rows: [
        for (final raw in (json['rows'] as List<dynamic>?) ?? const [])
          ImportPreviewRow.fromJson(raw as Map<String, dynamic>),
      ],
      errors: [
        for (final raw in (errors['content'] as List<dynamic>?) ?? const [])
          ImportRowError.fromJson(raw as Map<String, dynamic>),
      ],
    );
  }

  @override
  List<Object?> get props => [importId, mapping, totalRows, validRows, rows];
}

List<String> _strings(Object? raw) => [
  for (final value in (raw as List<dynamic>?) ?? const [])
    if (value is String) value,
];
