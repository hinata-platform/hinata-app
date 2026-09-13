import 'package:equatable/equatable.dart';

import '../util/dates.dart';

/// What a person is told about the processing of their working time, from
/// `GET /api/v1/time/privacy`.
///
/// The notice is prose, the operator's or the built-in template in the reader's
/// language. The visibility is computed by the server from the policies in force
/// on every read, which is why nothing here is cached beyond one screen.
class TimePrivacy extends Equatable {
  const TimePrivacy({
    required this.notice,
    this.customNotice = false,
    this.acknowledgedAt,
    this.visibility = const TimeVisibility(),
  });

  /// Markdown.
  final String notice;

  /// Whether the operator wrote the notice rather than the built-in one showing.
  final bool customNotice;

  /// When the reader first confirmed the notice, or null when they never have —
  /// which is what makes the module show it on first use.
  final DateTime? acknowledgedAt;

  final TimeVisibility visibility;

  bool get acknowledged => acknowledgedAt != null;

  factory TimePrivacy.fromJson(Map<String, dynamic> json) => TimePrivacy(
    notice: json['notice'] as String? ?? '',
    customNotice: json['customNotice'] as bool? ?? false,
    acknowledgedAt: parseInstant(json['acknowledgedAt']),
    visibility: TimeVisibility.fromJson(
      (json['visibility'] as Map<String, dynamic>?) ?? const {},
    ),
  );

  @override
  List<Object?> get props => [notice, customNotice, acknowledgedAt, visibility];
}

/// Who can see what of the reader's time, as the rules stand right now.
///
/// Only the answers that depend on a policy. That the reader sees their own
/// entries and that administrators see every entry is true everywhere, so the
/// panel states those two without asking.
class TimeVisibility extends Equatable {
  const TimeVisibility({
    this.leadsSeeEntries = false,
    this.approvalsEnabled = false,
    this.workloadReports = false,
    this.alerts = false,
    this.targetReminders = false,
    this.arbzgHints = false,
    this.lateEntryHintDays,
    this.maxDaysBack = 365,
    this.entryRetentionMonths = 0,
    this.descriptionRetentionMonths = 0,
    this.foreignChangesRecorded = true,
    this.entryCreationRecorded = false,
    this.timerEventsRecorded = false,
  });

  final bool leadsSeeEntries;
  final bool approvalsEnabled;
  final bool workloadReports;
  final bool alerts;
  final bool targetReminders;
  final bool arbzgHints;
  final int? lateEntryHintDays;
  final int maxDaysBack;

  /// Entries are deleted after this many months; 0 never.
  final int entryRetentionMonths;

  /// Descriptions of deleted accounts are emptied after this many months; 0 never.
  final int descriptionRetentionMonths;

  /// Somebody else changing the reader's entries is recorded.
  final bool foreignChangesRecorded;

  /// Filing an entry is recorded in the audit log.
  final bool entryCreationRecorded;

  /// Starting and stopping a timer is recorded in the audit log.
  final bool timerEventsRecorded;

  factory TimeVisibility.fromJson(Map<String, dynamic> json) => TimeVisibility(
    leadsSeeEntries: json['leadsSeeEntries'] as bool? ?? false,
    approvalsEnabled: json['approvalsEnabled'] as bool? ?? false,
    workloadReports: json['workloadReports'] as bool? ?? false,
    alerts: json['alerts'] as bool? ?? false,
    targetReminders: json['targetReminders'] as bool? ?? false,
    arbzgHints: json['arbzgHints'] as bool? ?? false,
    lateEntryHintDays: (json['lateEntryHintDays'] as num?)?.toInt(),
    maxDaysBack: (json['maxDaysBack'] as num?)?.toInt() ?? 365,
    entryRetentionMonths: (json['entryRetentionMonths'] as num?)?.toInt() ?? 0,
    descriptionRetentionMonths:
        (json['descriptionRetentionMonths'] as num?)?.toInt() ?? 0,
    foreignChangesRecorded: json['foreignChangesRecorded'] as bool? ?? true,
    entryCreationRecorded: json['entryCreationRecorded'] as bool? ?? false,
    timerEventsRecorded: json['timerEventsRecorded'] as bool? ?? false,
  );

  @override
  List<Object?> get props => [
    leadsSeeEntries,
    approvalsEnabled,
    workloadReports,
    alerts,
    targetReminders,
    arbzgHints,
    lateEntryHintDays,
    maxDaysBack,
    entryRetentionMonths,
    descriptionRetentionMonths,
    foreignChangesRecorded,
    entryCreationRecorded,
    timerEventsRecorded,
  ];
}

/// One self-hint about the reader's own entries, from `GET /api/v1/time/hints`.
///
/// Shown to the reader and nobody else, never stored and never counted.
class TimeHint extends Equatable {
  const TimeHint({
    required this.kind,
    required this.date,
    this.entryId,
    this.minutes,
    this.restMinutes,
    this.daysLate,
  });

  /// `DAILY_MAXIMUM`, `SHORT_REST`, `SUNDAY_WORK` or `LATE_ENTRY`. A kind this
  /// build does not know is dropped by [fromJson]'s caller rather than shown as
  /// a raw key.
  final String kind;
  final DateTime date;
  final String? entryId;
  final int? minutes;
  final int? restMinutes;
  final int? daysLate;

  static const knownKinds = {
    'DAILY_MAXIMUM',
    'SHORT_REST',
    'SUNDAY_WORK',
    'LATE_ENTRY',
  };

  bool get isKnown => knownKinds.contains(kind);
  bool get isLateEntry => kind == 'LATE_ENTRY';

  static TimeHint? fromJson(Map<String, dynamic> json) {
    final date = parseDate(json['date']);
    if (date == null) return null;
    return TimeHint(
      kind: json['kind'] as String? ?? '',
      date: date,
      entryId: json['entryId'] as String?,
      minutes: (json['minutes'] as num?)?.toInt(),
      restMinutes: (json['restMinutes'] as num?)?.toInt(),
      daysLate: (json['daysLate'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [kind, date, entryId, minutes, restMinutes, daysLate];
}

/// A request somebody made about their own time, as the people who can answer
/// it read it: a frozen entry to be corrected, or days to be opened.
class TimeCorrectionRequest extends Equatable {
  const TimeCorrectionRequest({
    required this.id,
    this.kind = kindEntry,
    this.entryId,
    this.date,
    this.from,
    this.to,
    this.projectId,
    this.reason,
    this.note,
    this.requesterId,
    this.requesterLabel,
    this.at,
    this.answer,
    this.grantable = false,
  });

  /// About one frozen entry.
  static const kindEntry = 'ENTRY';

  /// About days that cannot be recorded yet, named by [from] and [to].
  static const kindSpan = 'SPAN';

  final String id;
  final String kind;
  final String? entryId;

  /// The day of the entry, for [kindEntry].
  final DateTime? date;

  /// The days asked for, for [kindSpan].
  final DateTime? from;
  final DateTime? to;
  final String? projectId;

  /// `LOCK_DATE`, `APPROVAL` or `MAX_DAYS_BACK`: what stands in the way.
  final String? reason;
  final String? note;
  final String? requesterId;
  final String? requesterLabel;
  final DateTime? at;
  final TimeCorrectionAnswer? answer;

  /// Whether this reader can answer by opening the days for the person. Decided
  /// by the server: administrators only, and never for a submitted period.
  final bool grantable;

  bool get answered => answer != null;
  bool get isSpan => kind == kindSpan;

  factory TimeCorrectionRequest.fromJson(Map<String, dynamic> json) {
    final answer = json['answer'] as Map<String, dynamic>?;
    return TimeCorrectionRequest(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? kindEntry,
      entryId: json['entryId'] as String?,
      date: parseDate(json['date']),
      from: parseDate(json['from']),
      to: parseDate(json['to']),
      projectId: json['projectId'] as String?,
      reason: json['reason'] as String?,
      note: json['note'] as String?,
      requesterId: json['requesterId'] as String?,
      requesterLabel: json['requesterLabel'] as String?,
      at: parseInstant(json['at']),
      answer: answer == null ? null : TimeCorrectionAnswer.fromJson(answer),
      grantable: json['grantable'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
    id,
    kind,
    entryId,
    date,
    from,
    to,
    projectId,
    reason,
    note,
    requesterId,
    requesterLabel,
    at,
    answer,
    grantable,
  ];
}

/// The reply to a correction request.
class TimeCorrectionAnswer extends Equatable {
  const TimeCorrectionAnswer({
    this.note,
    this.byLabel,
    this.at,
    this.granted = false,
  });

  final String? note;
  final String? byLabel;
  final DateTime? at;

  /// Whether the answer opened the days for the person who asked.
  final bool granted;

  factory TimeCorrectionAnswer.fromJson(Map<String, dynamic> json) =>
      TimeCorrectionAnswer(
        note: json['note'] as String?,
        byLabel: json['byLabel'] as String?,
        at: parseInstant(json['at']),
        granted: json['granted'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [note, byLabel, at, granted];
}

/// Days an administrator opened for one person, as the administrators list them.
class TimeBackfillGrant extends Equatable {
  const TimeBackfillGrant({
    required this.id,
    required this.from,
    required this.to,
    this.userId,
    this.userLabel,
    this.note,
    this.grantedByLabel,
    this.grantedAt,
    this.expiresAt,
  });

  final String id;
  final DateTime from;
  final DateTime to;
  final String? userId;

  /// Null once the account is gone.
  final String? userLabel;

  /// The reason the administrator gave. The person reads it as the answer.
  final String? note;
  final String? grantedByLabel;
  final DateTime? grantedAt;

  /// When the days close again by themselves.
  final DateTime? expiresAt;

  static TimeBackfillGrant? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final from = parseDate(json['from']);
    final to = parseDate(json['to']);
    if (id == null || from == null || to == null) return null;
    return TimeBackfillGrant(
      id: id,
      from: from,
      to: to,
      userId: json['userId'] as String?,
      userLabel: json['userLabel'] as String?,
      note: json['note'] as String?,
      grantedByLabel: json['grantedByLabel'] as String?,
      grantedAt: parseInstant(json['grantedAt']),
      expiresAt: parseInstant(json['expiresAt']),
    );
  }

  @override
  List<Object?> get props => [
    id,
    from,
    to,
    userId,
    userLabel,
    note,
    grantedByLabel,
    grantedAt,
    expiresAt,
  ];
}
