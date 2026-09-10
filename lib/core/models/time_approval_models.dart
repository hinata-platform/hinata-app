import 'package:equatable/equatable.dart';

import '../util/dates.dart';

/// Where a submitted period stands.
enum ApprovalStatus {
  /// Handed in and waiting. Freezes the period.
  submitted,

  /// Signed off. Freezes the period; only a reopen takes it back.
  approved,

  /// Sent back with a reason. Does *not* freeze — the point is to fix it.
  rejected,

  /// Taken back by the submitter before anyone decided. Does not freeze.
  withdrawn;

  static ApprovalStatus? parse(String? wire) => switch (wire) {
    'SUBMITTED' => ApprovalStatus.submitted,
    'APPROVED' => ApprovalStatus.approved,
    'REJECTED' => ApprovalStatus.rejected,
    'WITHDRAWN' => ApprovalStatus.withdrawn,
    _ => null,
  };

  /// Whether this state makes the period's entries immutable.
  bool get freezes =>
      this == ApprovalStatus.submitted || this == ApprovalStatus.approved;

  /// `time.approval.status.<name>` — the chip's label.
  String get labelKey => 'time.approval.status.$name';
}

/// Why an entry cannot be written, who can lift it, and what the way back is.
///
/// One shape for every reason, because there are two after HIN-88 and a third
/// (an issued invoice) in HIN-96. Three mechanisms each with their own sentence
/// would give somebody three ways of being told "no" and three places to look
/// for the way out; this is the one the server speaks and the one component
/// `LockNotice` renders.
///
/// Built either from the `details` of a 403 — the authoritative answer, since
/// the server is what refused — or locally from the policy, so a screen can draw
/// a lock *before* anybody tries to write.
class TimeLockInfo extends Equatable {
  /// Longest reason the server accepts on a decision, a reopen, a lock exception
  /// or a correction request. Stated here because four dialogs cap the same
  /// field, and four copies of a number is how one of them drifts.
  static const noteMaxLength = 1000;

  const TimeLockInfo({
    required this.reason,
    this.lockDate,
    this.approvalId,
    this.periodStart,
    this.periodEnd,
    this.entryId,
  });

  /// `lockDate`, `approval` or `invoice` — the server's vocabulary, verbatim.
  ///
  /// An unknown value is kept rather than mapped to an enum: a server newer than
  /// this build may name a fourth reason, and "frozen, for a reason this app
  /// cannot name" is a better answer than pretending nothing is wrong.
  final String reason;

  /// The freeze boundary, when the reason is the lock date. Days *before* it are
  /// shut; the day itself is open.
  final DateTime? lockDate;

  /// The submission that freezes it, when the reason is an approval.
  final String? approvalId;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  /// The entry this is about, when it is about one. Carried so the notice can
  /// offer the correction request without the caller re-plumbing it.
  final String? entryId;

  bool get isLockDate => reason == 'lockDate';
  bool get isApproval => reason == 'approval';

  /// `time.lock.reason.<reason>` — one sentence per reason.
  String get reasonKey => 'time.lock.reason.$reason';

  /// `time.lock.holder.<reason>` — who can lift this one.
  String get holderKey => 'time.lock.holder.$reason';

  /// `time.lock.remedy.<reason>` — what to do about it.
  String get remedyKey => 'time.lock.remedy.$reason';

  /// A refusal that names a freeze, or null for any other failure.
  static TimeLockInfo? fromDetails(
    Map<String, String> details, {
    String? entryId,
  }) {
    final reason = details['reason'];
    if (reason == null || reason.isEmpty) return null;
    return TimeLockInfo(
      reason: reason,
      lockDate: parseDate(details['lockDate']),
      approvalId: details['approvalId'],
      periodStart: parseDate(details['periodStart']),
      periodEnd: parseDate(details['periodEnd']),
      entryId: entryId,
    );
  }

  TimeLockInfo withEntry(String? id) => TimeLockInfo(
    reason: reason,
    lockDate: lockDate,
    approvalId: approvalId,
    periodStart: periodStart,
    periodEnd: periodEnd,
    entryId: id ?? entryId,
  );

  @override
  List<Object?> get props => [
    reason,
    lockDate,
    approvalId,
    periodStart,
    periodEnd,
    entryId,
  ];
}

/// One span an administrator has reopened inside the freeze.
class TimeLockException extends Equatable {
  const TimeLockException({
    required this.id,
    required this.from,
    required this.to,
    this.note,
    this.by,
    this.at,
  });

  final String id;
  final DateTime from;
  final DateTime to;

  /// Why it was opened. Always present on a new one — the server refuses a blank
  /// reason — and the whole of what makes the feature accountable.
  final String? note;
  final String? by;
  final DateTime? at;

  /// Whether [date] falls inside, both bounds included.
  bool covers(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(DateTime(from.year, from.month, from.day)) &&
        !day.isAfter(DateTime(to.year, to.month, to.day));
  }

  factory TimeLockException.fromJson(Map<String, dynamic> json) =>
      TimeLockException(
        id: json['id'] as String? ?? '',
        from: parseDate(json['from']) ?? DateTime(1970),
        to: parseDate(json['to']) ?? DateTime(1970),
        note: json['note'] as String?,
        by: json['by'] as String?,
        at: parseInstant(json['at']),
      );

  @override
  List<Object?> get props => [id, from, to, note, by, at];
}

/// How often timesheets are handed in, as the people who hand them in are told.
///
/// Just the parameters. Turning them into dates is the server's arithmetic and
/// arrives through `GET /time/approvals/periods` — there is deliberately no
/// second implementation of it in the app, because two would disagree on exactly
/// one day a year and nobody would notice until a payroll period was short.
class ApprovalRhythm extends Equatable {
  const ApprovalRhythm({this.type = 'MONTHLY', this.weekStartsOn, this.days});

  /// `WEEKLY`, `BIWEEKLY`, `SEMI_MONTHLY`, `MONTHLY`, `QUARTERLY`,
  /// `CUSTOM_DAYS` or `FREE`.
  final String type;
  final String? weekStartsOn;
  final int? days;

  /// Whether the calendar is cut into periods at all. False only for `FREE`,
  /// where the person picks a span instead of stepping through a grid.
  bool get hasGrid => type != 'FREE';

  factory ApprovalRhythm.fromJson(Map<String, dynamic> json) => ApprovalRhythm(
    type: json['type'] as String? ?? 'MONTHLY',
    weekStartsOn: json['weekStartsOn'] as String?,
    days: (json['days'] as num?)?.toInt(),
  );

  @override
  List<Object?> get props => [type, weekStartsOn, days];
}

/// One project's standing inside one period.
class ApprovalProjectStatus extends Equatable {
  const ApprovalProjectStatus({
    required this.projectId,
    this.projectKey,
    this.projectName,
    this.status,
    this.approvalId,
    this.minutes = 0,
    this.required = true,
    this.note,
  });

  final String projectId;
  final String? projectKey;
  final String? projectName;

  /// Null when nothing has been handed in for this project and period yet.
  final ApprovalStatus? status;
  final String? approvalId;
  final int minutes;

  /// Whether this project's periods are meant to be handed in at all.
  final bool required;

  /// The reason given with the last decision — a rejection's, above all.
  final String? note;

  bool get isOpen => status == null || !status!.freezes;

  factory ApprovalProjectStatus.fromJson(Map<String, dynamic> json) =>
      ApprovalProjectStatus(
        projectId: json['projectId'] as String? ?? '',
        projectKey: json['projectKey'] as String?,
        projectName: json['projectName'] as String?,
        status: ApprovalStatus.parse(json['status'] as String?),
        approvalId: json['approvalId'] as String?,
        minutes: (json['minutes'] as num?)?.toInt() ?? 0,
        required: json['required'] as bool? ?? true,
        note: json['note'] as String?,
      );

  @override
  List<Object?> get props => [
    projectId,
    projectKey,
    projectName,
    status,
    approvalId,
    minutes,
    required,
    note,
  ];
}

/// One period, and where each of the reader's projects stands in it.
class ApprovalPeriod extends Equatable {
  const ApprovalPeriod({
    required this.start,
    required this.end,
    required this.type,
    this.projects = const [],
  });

  final DateTime start;
  final DateTime end;

  /// The rhythm these dates were cut from — a snapshot on a stored submission,
  /// so a later policy change never reinterprets what is already handed in.
  final String type;
  final List<ApprovalProjectStatus> projects;

  bool contains(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(DateTime(start.year, start.month, start.day)) &&
        !day.isAfter(DateTime(end.year, end.month, end.day));
  }

  /// Projects that could still be handed in: they have hours, they are asked
  /// for, and they are not already submitted or signed off.
  List<ApprovalProjectStatus> get submittable => projects
      .where((p) => p.required && p.isOpen && p.minutes > 0)
      .toList(growable: false);

  /// Submissions of this period that can be taken back — pending ones only.
  List<ApprovalProjectStatus> get withdrawable => projects
      .where((p) => p.status == ApprovalStatus.submitted)
      .toList(growable: false);

  int get minutes => projects.fold(0, (sum, p) => sum + p.minutes);

  factory ApprovalPeriod.fromJson(Map<String, dynamic> json) => ApprovalPeriod(
    start: parseDate(json['start']) ?? DateTime(1970),
    end: parseDate(json['end']) ?? DateTime(1970),
    type: json['type'] as String? ?? 'MONTHLY',
    projects: ((json['projects'] as List<dynamic>?) ?? const [])
        .map((p) => ApprovalProjectStatus.fromJson(p as Map<String, dynamic>))
        .toList(growable: false),
  );

  @override
  List<Object?> get props => [start, end, type, projects];
}

/// One transition of a submission: who moved it where, and why.
class ApprovalEvent extends Equatable {
  const ApprovalEvent({this.at, this.by, this.from, this.to, this.note});

  final DateTime? at;
  final String? by;
  final ApprovalStatus? from;
  final ApprovalStatus? to;
  final String? note;

  factory ApprovalEvent.fromJson(Map<String, dynamic> json) => ApprovalEvent(
    at: parseInstant(json['at']),
    by: json['by'] as String?,
    from: ApprovalStatus.parse(json['from'] as String?),
    to: ApprovalStatus.parse(json['to'] as String?),
    note: json['note'] as String?,
  );

  @override
  List<Object?> get props => [at, by, from, to, note];
}

/// One person's time for one project over one span, handed in.
class TimesheetApproval extends Equatable {
  const TimesheetApproval({
    required this.id,
    required this.userId,
    required this.projectId,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
    this.periodType = 'MONTHLY',
    this.totalMinutes = 0,
    this.submittedAt,
    this.decidedBy,
    this.decidedAt,
    this.note,
    this.history = const [],
  });

  final String id;
  final String userId;
  final String projectId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final ApprovalStatus status;
  final String periodType;

  /// What the period held when it was handed in — a snapshot, useful precisely
  /// because it can go out of date: an approver who sees it differ from what the
  /// period holds now knows something moved after submission.
  final int totalMinutes;
  final DateTime? submittedAt;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String? note;
  final List<ApprovalEvent> history;

  factory TimesheetApproval.fromJson(Map<String, dynamic> json) =>
      TimesheetApproval(
        id: json['id'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        projectId: json['projectId'] as String? ?? '',
        periodStart: parseDate(json['periodStart']) ?? DateTime(1970),
        periodEnd: parseDate(json['periodEnd']) ?? DateTime(1970),
        status:
            ApprovalStatus.parse(json['status'] as String?) ??
            ApprovalStatus.submitted,
        periodType: json['periodType'] as String? ?? 'MONTHLY',
        totalMinutes: (json['totalMinutes'] as num?)?.toInt() ?? 0,
        submittedAt: parseInstant(json['submittedAt']),
        decidedBy: json['decidedBy'] as String?,
        decidedAt: parseInstant(json['decidedAt']),
        note: json['note'] as String?,
        history: ((json['history'] as List<dynamic>?) ?? const [])
            .map((e) => ApprovalEvent.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );

  @override
  List<Object?> get props => [
    id,
    userId,
    projectId,
    periodStart,
    periodEnd,
    status,
    periodType,
    totalMinutes,
    submittedAt,
    decidedBy,
    decidedAt,
    note,
    history,
  ];
}
