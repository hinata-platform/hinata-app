import 'package:equatable/equatable.dart';

import '../util/dates.dart';
import 'time_approval_models.dart';

/// What the operator's time-tracking policies currently demand, as the people
/// they apply to are told them.
///
/// The admin settings are admin-only, and every rule in here is one an ordinary
/// member runs into: a field they must fill in, a day they can no longer edit,
/// a tag they may not coin. Without this the editor could only discover each
/// rule by being refused — a poor editor, and the opposite of the transparency
/// the epic asks for.
///
/// Read from `GET /api/v1/time/policy`, which resolves the same values the
/// server's write gate enforces. Nothing here is a secret and nothing here is
/// personal.
class TimePolicySnapshot extends Equatable {
  const TimePolicySnapshot({
    this.requiredProject = false,
    this.requiredIssue = false,
    this.requiredDescription = false,
    this.requiredTag = false,
    this.lockBefore,
    this.lockExceptions = const [],
    this.roundingMode = 'NONE',
    this.roundingIncrement = 15,
    this.limitTagAccess = false,
    this.defaultBillable = false,
    this.approvalsEnabled = false,
    this.approvalRhythm = const ApprovalRhythm(),
    this.myFrozenPeriods = const [],
    this.leadsSeeMemberEntries = false,
    this.maxDaysBack = defaultMaxDaysBack,
    this.arbzgHintsEnabled = false,
    this.lateEntryHintDays,
    this.myBackfillGrants = const [],
    this.targetRemindersEnabled = false,
    this.suggestedDailyTargetMinutes,
    this.suggestedWeeklyTargetMinutes,
    this.alertsEnabled = false,
    this.absenceCalendar = AbsenceCalendarLevel.off,
    this.workloadReportsEnabled = false,
    this.absenceReportsEnabled = false,
  });

  /// What the server enforces when it says nothing: a year, as the 1.x routes
  /// always have.
  static const defaultMaxDaysBack = 365;

  /// What a fresh instance demands: nothing. Also what the app assumes while the
  /// policy is still loading, or when the server is too old to publish it — the
  /// server refuses what it must, and marking a field required that is not would
  /// block a save the server would have accepted.
  static const none = TimePolicySnapshot();

  final bool requiredProject;
  final bool requiredIssue;
  final bool requiredDescription;
  final bool requiredTag;

  /// Entries dated before this day cannot be created, changed or deleted.
  /// Null when nothing is frozen.
  ///
  /// Never in the future — the server refuses a later date and clamps one that
  /// arrives from a deployment variable. A freeze that reached into the present
  /// would block the recording of working time that is happening right now, which
  /// is the one thing the law requires the system to be able to do.
  final DateTime? lockBefore;

  /// Spans an administrator has reopened inside the freeze, each with a reason.
  ///
  /// Published to everyone, note and all, and that is the point: a day that is
  /// open again inside a closed month is a rule people run into, and an exception
  /// nobody could see would be indistinguishable from a bug.
  final List<TimeLockException> lockExceptions;

  /// `NONE`, `UP`, `DOWN` or `NEAREST` — how reports fold durations. Never
  /// applied to a stored entry.
  final String roundingMode;
  final int roundingIncrement;

  /// Whether only administrators may add words to the tag catalogue.
  final bool limitTagAccess;
  final bool defaultBillable;

  /// Whether periods are handed in and signed off on this instance at all.
  ///
  /// Read from the policy rather than discovered by calling the approvals route
  /// and getting a 404: a screen that offered an action which does not exist is
  /// the opposite of what publishing the rules is for.
  final bool approvalsEnabled;

  /// How often they are handed in. The app never turns this into dates — that is
  /// `GET /time/approvals/periods`.
  final ApprovalRhythm approvalRhythm;

  /// The reader's own submissions that freeze something, newest first.
  ///
  /// Carried with the rules rather than fetched per screen, because "is this day
  /// of mine frozen" is asked by four of them and a copy each would be four
  /// requests and four ways to be stale. Bounded by the page the cubit reads: a
  /// hundred submissions is years of them, and a period older than that is behind
  /// the lock date anyway.
  final List<TimesheetApproval> myFrozenPeriods;

  /// Whether a lead sees the entries of the members of projects they lead —
  /// including their rows in the timesheet. Off means leads see project totals,
  /// never who booked what.
  final bool leadsSeeMemberEntries;

  /// How many days back a day can be recorded without an administrator opening
  /// it first. A typo guard, never a deadline.
  final int maxDaysBack;

  /// Whether the Working Hours Act hints exist for the reader's own entries.
  final bool arbzgHintsEnabled;

  /// After how many days an entry is marked as recorded late, or null for no
  /// such hint.
  final int? lateEntryHintDays;

  /// Days an administrator opened for the reader, beyond the limit or before the
  /// lock date, each until it runs out. Only the reader's own: nobody else's
  /// would change what this reader may record, and the server sends none.
  final List<TimeOpenedDays> myBackfillGrants;

  /// Whether a person can set targets of their own and be reminded of them
  /// (HIN-92). The reminders panel is shown only while this is on.
  final bool targetRemindersEnabled;

  /// Targets the operator suggests. Offered to take over, never applied.
  final int? suggestedDailyTargetMinutes;
  final int? suggestedWeeklyTargetMinutes;

  /// Whether leads and assignees hear about budgets and estimates; the project
  /// thresholds mean something only while this is on.
  final bool alertsEnabled;

  /// How much of other people's absences the team calendar shows (HIN-118).
  /// [AbsenceCalendarLevel.off] whenever absence management is off, so the
  /// calendar and the "away today" card are asked for only where they exist.
  final AbsenceCalendarLevel absenceCalendar;

  /// Whether the workload report exists on this instance (HIN-93). Who may
  /// read it the server decides; the tab is offered only where it could answer.
  final bool workloadReportsEnabled;

  /// Whether the report "absences and balances" exists (HIN-119): only while
  /// absence management does, and only with its own policy on.
  final bool absenceReportsEnabled;

  /// Whether `GET /time/hints` answers at all. Asked before calling it, so a
  /// screen never pays for a 404.
  bool get hintsEnabled => arbzgHintsEnabled || lateEntryHintDays != null;

  /// The first day the date pickers offer.
  ///
  /// The oldest day the limit allows, or the start of an older span an
  /// administrator has opened, for everyone or for the reader — a picker that
  /// stopped at the limit would hide exactly the days an opening exists for.
  /// Which of the days in between can be picked is [withinReach].
  DateTime firstRecordableDay(DateTime today) {
    var first = DateTime(today.year, today.month, today.day - maxDaysBack);
    for (final exception in lockExceptions) {
      if (exception.from.isBefore(first)) first = exception.from;
    }
    for (final grant in myBackfillGrants) {
      if (grant.from.isBefore(first)) first = grant.from;
    }
    return first;
  }

  /// Whether [day] can be recorded as far as the limit goes: inside
  /// [maxDaysBack] of [today], or opened by an exception or for the reader.
  ///
  /// The lock date is not asked here. A locked day can still be picked, and the
  /// editor then says why it cannot be saved and how to ask for it; a day beyond
  /// the limit that nothing opened is greyed out in the picker, whose footer
  /// offers asking for it instead.
  bool withinReach(DateTime day, DateTime today) {
    final date = DateTime(day.year, day.month, day.day);
    final oldest = DateTime(today.year, today.month, today.day - maxDaysBack);
    if (!date.isBefore(oldest)) return true;
    return lockExceptions.any((exception) => exception.covers(date)) ||
        myBackfillGrants.any((grant) => grant.covers(date));
  }

  /// An issue always brings its project, so requiring one requires the other.
  bool get requiresPlacement => requiredProject || requiredIssue;

  /// The i18n key of the first field rule an entry with these values does not
  /// satisfy, or null when it satisfies them all.
  ///
  /// Here rather than written out at each caller, because it is asked in three
  /// places that must agree: the composer greys out its save button with it, the
  /// stop decides with it whether the composer has to open at all, and the
  /// server enforces the same four rules on the write. Two of those live on
  /// screens the third never sees.
  ///
  /// The lock is *not* part of it. A frozen day is a rule about when, judged
  /// against a date the caller has and this does not, and it cannot be fixed by
  /// typing — which is exactly what separates it from these four.
  String? unmetBy({
    String? projectId,
    String? issueId,
    String? description,
    List<String> tags = const [],
    bool placement = true,
  }) {
    // [placement] is false where the caller is not settling where the entry
    // sits: `PATCH /time/entries/{id}` carries neither field, so an edit cannot
    // violate these two — and an entry filed before the rule existed would
    // otherwise be read-only to the owner trying to bring it into compliance.
    if (placement) {
      if (requiredIssue && issueId == null) return 'time.policy.needIssue';
      if (requiresPlacement && projectId == null) {
        return 'time.policy.needProject';
      }
    }
    if (requiredDescription && (description?.trim().isEmpty ?? true)) {
      return 'time.policy.needDescription';
    }
    if (requiredTag && tags.isEmpty) return 'time.policy.needTag';
    return null;
  }

  /// Whether the day of [date] is frozen by the lock date.
  ///
  /// A date-only comparison: the lock is a calendar day on both sides, and an
  /// instant would make it depend on the hour somebody happened to open the
  /// editor. An exception that reopens the day makes this false, which is what
  /// an exception is for, and so do days an administrator opened for the reader.
  ///
  /// This is only the *lock date*. A period somebody has handed in freezes its
  /// entries too, and that answer needs the approvals of the window on screen —
  /// see [lockFor].
  bool isLocked(DateTime? date) {
    final lock = lockBefore;
    if (lock == null || date == null) return false;
    final day = DateTime(date.year, date.month, date.day);
    if (!day.isBefore(DateTime(lock.year, lock.month, lock.day))) return false;
    return !lockExceptions.any((exception) => exception.covers(day)) &&
        !myBackfillGrants.any((grant) => grant.covers(day));
  }

  /// Why [date] of [projectId] cannot be written, or null when it can.
  ///
  /// The one resolver, so every screen draws the same lock for the same day: the
  /// list, the entry sheet, the timesheet cell and the calendar all ask this. The
  /// lock date is asked first, because it is the more absolute answer — a day an
  /// administrator has archived stays archived whatever a submission says about
  /// it — and that is exactly the order the server resolves them in.
  ///
  /// The freezing submissions come from [myFrozenPeriods], which the cubit loads
  /// with the rules. Both halves of the tuple have to match: a period is somebody's
  /// hours *for one project*, so a submission of project B freezes nothing in
  /// project A. An entry with no project is never frozen by an approval at all —
  /// those are private and are never handed in — and falls under the lock date like
  /// everything else.
  TimeLockInfo? lockFor(DateTime? date, {String? projectId, String? entryId}) {
    if (date == null) return null;
    if (isLocked(date)) {
      return TimeLockInfo(
        reason: 'lockDate',
        lockDate: lockBefore,
        entryId: entryId,
      );
    }
    if (!approvalsEnabled || projectId == null) return null;
    final day = DateTime(date.year, date.month, date.day);
    for (final period in myFrozenPeriods) {
      if (period.projectId != projectId || !period.status.freezes) continue;
      final start = DateTime(
        period.periodStart.year,
        period.periodStart.month,
        period.periodStart.day,
      );
      final end = DateTime(
        period.periodEnd.year,
        period.periodEnd.month,
        period.periodEnd.day,
      );
      if (!day.isBefore(start) && !day.isAfter(end)) {
        return TimeLockInfo(
          reason: 'approval',
          approvalId: period.id,
          periodStart: period.periodStart,
          periodEnd: period.periodEnd,
          entryId: entryId,
        );
      }
    }
    return null;
  }

  /// The same rules with the reader's freezing submissions attached.
  TimePolicySnapshot withFrozenPeriods(List<TimesheetApproval> periods) =>
      TimePolicySnapshot(
        requiredProject: requiredProject,
        requiredIssue: requiredIssue,
        requiredDescription: requiredDescription,
        requiredTag: requiredTag,
        lockBefore: lockBefore,
        lockExceptions: lockExceptions,
        roundingMode: roundingMode,
        roundingIncrement: roundingIncrement,
        limitTagAccess: limitTagAccess,
        defaultBillable: defaultBillable,
        approvalsEnabled: approvalsEnabled,
        approvalRhythm: approvalRhythm,
        myFrozenPeriods: periods,
        leadsSeeMemberEntries: leadsSeeMemberEntries,
        maxDaysBack: maxDaysBack,
        arbzgHintsEnabled: arbzgHintsEnabled,
        lateEntryHintDays: lateEntryHintDays,
        myBackfillGrants: myBackfillGrants,
        targetRemindersEnabled: targetRemindersEnabled,
        suggestedDailyTargetMinutes: suggestedDailyTargetMinutes,
        suggestedWeeklyTargetMinutes: suggestedWeeklyTargetMinutes,
        alertsEnabled: alertsEnabled,
        absenceCalendar: absenceCalendar,
        workloadReportsEnabled: workloadReportsEnabled,
        absenceReportsEnabled: absenceReportsEnabled,
      );

  factory TimePolicySnapshot.fromJson(Map<String, dynamic> json) {
    final required = json['requiredFields'] as Map<String, dynamic>?;
    final rounding = json['rounding'] as Map<String, dynamic>?;
    final reminders = json['targetReminders'] as Map<String, dynamic>?;
    return TimePolicySnapshot(
      requiredProject: required?['project'] as bool? ?? false,
      requiredIssue: required?['issue'] as bool? ?? false,
      requiredDescription: required?['description'] as bool? ?? false,
      requiredTag: required?['tag'] as bool? ?? false,
      lockBefore: parseDate(json['lockBefore']),
      lockExceptions: ((json['lockExceptions'] as List<dynamic>?) ?? const [])
          .map((e) => TimeLockException.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      roundingMode: rounding?['mode'] as String? ?? 'NONE',
      roundingIncrement: (rounding?['increment'] as num?)?.toInt() ?? 15,
      limitTagAccess: json['limitTagAccess'] as bool? ?? false,
      defaultBillable: json['defaultBillable'] as bool? ?? false,
      approvalsEnabled: json['approvalsEnabled'] as bool? ?? false,
      approvalRhythm: ApprovalRhythm.fromJson(
        (json['approvalPeriod'] as Map<String, dynamic>?) ?? const {},
      ),
      leadsSeeMemberEntries: json['leadsSeeMemberEntries'] as bool? ?? false,
      maxDaysBack: (json['maxDaysBack'] as num?)?.toInt() ?? defaultMaxDaysBack,
      arbzgHintsEnabled: json['arbzgHintsEnabled'] as bool? ?? false,
      lateEntryHintDays: (json['lateEntryHintDays'] as num?)?.toInt(),
      myBackfillGrants: [
        for (final raw in (json['myBackfillGrants'] as List<dynamic>?) ?? [])
          ?TimeOpenedDays.fromJson(raw as Map<String, dynamic>),
      ],
      targetRemindersEnabled: reminders?['enabled'] as bool? ?? false,
      suggestedDailyTargetMinutes:
          (reminders?['suggestedDailyTargetMinutes'] as num?)?.toInt(),
      suggestedWeeklyTargetMinutes:
          (reminders?['suggestedWeeklyTargetMinutes'] as num?)?.toInt(),
      alertsEnabled: json['alertsEnabled'] as bool? ?? false,
      absenceCalendar: AbsenceCalendarLevel.fromWire(
        json['absenceCalendarVisibility'] as String?,
      ),
      workloadReportsEnabled: json['workloadReportsEnabled'] as bool? ?? false,
      absenceReportsEnabled: json['absenceReportsEnabled'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
    requiredProject,
    requiredIssue,
    requiredDescription,
    requiredTag,
    lockBefore,
    lockExceptions,
    roundingMode,
    roundingIncrement,
    limitTagAccess,
    defaultBillable,
    approvalsEnabled,
    approvalRhythm,
    myFrozenPeriods,
    leadsSeeMemberEntries,
    maxDaysBack,
    arbzgHintsEnabled,
    lateEntryHintDays,
    myBackfillGrants,
    targetRemindersEnabled,
    suggestedDailyTargetMinutes,
    suggestedWeeklyTargetMinutes,
    alertsEnabled,
    absenceCalendar,
    workloadReportsEnabled,
    absenceReportsEnabled,
  ];
}

/// The levels of the team absence calendar, as the server names them.
///
/// The level is a ceiling: every absence type has its own visibility, and the
/// server sends the narrower of the two. Sickness is "away" on every level.
enum AbsenceCalendarLevel {
  off('OFF'),
  busyOnly('BUSY_ONLY'),
  type('TYPE');

  const AbsenceCalendarLevel(this.wire);

  final String wire;

  bool get isOn => this != off;

  String get labelKey => 'absence.calendar.level.$name';

  static AbsenceCalendarLevel fromWire(String? wire) =>
      values.firstWhere((level) => level.wire == wire, orElse: () => off);
}

/// Days an administrator opened for the reader, until [expiresAt].
///
/// Not a lock exception: an exception opens days for everyone and publishes its
/// reason, and these are opened for one person, whose reason stays between them
/// and the administrators.
class TimeOpenedDays extends Equatable {
  const TimeOpenedDays({required this.from, required this.to, this.expiresAt});

  final DateTime from;
  final DateTime to;

  /// When the days close again.
  final DateTime? expiresAt;

  /// Whether [date] falls inside, both bounds included.
  bool covers(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(DateTime(from.year, from.month, from.day)) &&
        !day.isAfter(DateTime(to.year, to.month, to.day));
  }

  static TimeOpenedDays? fromJson(Map<String, dynamic> json) {
    final from = parseDate(json['from']);
    final to = parseDate(json['to']);
    if (from == null || to == null) return null;
    return TimeOpenedDays(
      from: from,
      to: to,
      expiresAt: parseInstant(json['expiresAt']),
    );
  }

  @override
  List<Object?> get props => [from, to, expiresAt];
}

/// One word from the tag catalogue.
///
/// Entries carry tags as plain strings; this is the row behind the word — what
/// the picker lists, what a rename hangs off, and the colour it is drawn in.
class TimeTag extends Equatable {
  const TimeTag({
    required this.id,
    required this.name,
    this.hue = 250,
    this.entries,
  });

  final String id;
  final String name;
  final int hue;

  /// How many entries carry it. Only the admin list and the answer to a rename
  /// or a delete count it — the picker has no use for the number and must not
  /// pay for it on every keystroke.
  final int? entries;

  factory TimeTag.fromJson(Map<String, dynamic> json) => TimeTag(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    hue: (json['hue'] as num?)?.toInt() ?? 250,
    entries: (json['entries'] as num?)?.toInt(),
  );

  @override
  List<Object?> get props => [id, name, hue, entries];
}

/// What one project decides for itself about time.
///
/// Every field may be null, and null is an answer: "whatever the instance
/// policy says". That is why the form sends the whole block back — an override
/// has to be removable, and a patch could not say so.
class ProjectTimeSettings extends Equatable {
  const ProjectTimeSettings({
    this.budgetMinutes,
    this.defaultBillable,
    this.approvalRequired,
    this.approvalPeriod,
    this.lockBefore,
    this.budgetAlertPercent,
    this.estimateAlertPercent,
    this.updatedAt,
    this.updatedBy,
  });

  /// What the server applies while [budgetAlertPercent] is null. Mirrors
  /// `TimeAlerts.DEFAULT_BUDGET_PERCENT`.
  static const defaultBudgetAlertPercent = 80;

  /// What the server applies while [estimateAlertPercent] is null. Mirrors
  /// `TimeAlerts.DEFAULT_ESTIMATE_PERCENT`.
  static const defaultEstimateAlertPercent = 100;

  final int? budgetMinutes;
  final bool? defaultBillable;
  final bool? approvalRequired;

  /// `WEEKLY`, `BIWEEKLY`, `SEMI_MONTHLY`, `MONTHLY`, `QUARTERLY`,
  /// `CUSTOM_DAYS` or `FREE`; null leaves the instance rhythm in force. What a
  /// period covers is the server's arithmetic (HIN-88), never the app's.
  final String? approvalPeriod;

  /// A freeze for this project alone; null leaves the instance lock date in
  /// force. Only ever closes *more* than the instance — the server takes the
  /// later of the two, so a lead cannot reopen the month an administrator
  /// archived.
  final DateTime? lockBefore;

  /// The share of the budget, and of the sum of the estimates, at which the
  /// leads hear about it besides 100 %; null means [defaultBudgetAlertPercent].
  final int? budgetAlertPercent;

  /// The share of an issue's estimate at which its assignees hear about it;
  /// null means [defaultEstimateAlertPercent].
  final int? estimateAlertPercent;
  final DateTime? updatedAt;
  final String? updatedBy;

  bool get isEmpty =>
      budgetMinutes == null &&
      defaultBillable == null &&
      approvalRequired == null &&
      approvalPeriod == null &&
      lockBefore == null &&
      budgetAlertPercent == null &&
      estimateAlertPercent == null;

  ProjectTimeSettings copyWith({
    int? budgetMinutes,
    bool? defaultBillable,
    bool? approvalRequired,
    String? approvalPeriod,
    DateTime? lockBefore,
    int? budgetAlertPercent,
    int? estimateAlertPercent,
    bool clearBudget = false,
    bool clearDefaultBillable = false,
    bool clearApprovalRequired = false,
    bool clearApprovalPeriod = false,
    bool clearLockBefore = false,
    bool clearBudgetAlert = false,
    bool clearEstimateAlert = false,
  }) => ProjectTimeSettings(
    budgetMinutes: clearBudget ? null : (budgetMinutes ?? this.budgetMinutes),
    defaultBillable: clearDefaultBillable
        ? null
        : (defaultBillable ?? this.defaultBillable),
    approvalRequired: clearApprovalRequired
        ? null
        : (approvalRequired ?? this.approvalRequired),
    approvalPeriod: clearApprovalPeriod
        ? null
        : (approvalPeriod ?? this.approvalPeriod),
    lockBefore: clearLockBefore ? null : (lockBefore ?? this.lockBefore),
    budgetAlertPercent: clearBudgetAlert
        ? null
        : (budgetAlertPercent ?? this.budgetAlertPercent),
    estimateAlertPercent: clearEstimateAlert
        ? null
        : (estimateAlertPercent ?? this.estimateAlertPercent),
    updatedAt: updatedAt,
    updatedBy: updatedBy,
  );

  factory ProjectTimeSettings.fromJson(Map<String, dynamic> json) {
    final period = json['approvalPeriod'] as Map<String, dynamic>?;
    final alerts = json['alertThresholds'] as Map<String, dynamic>?;
    return ProjectTimeSettings(
      budgetMinutes: (json['budgetMinutes'] as num?)?.toInt(),
      defaultBillable: json['defaultBillable'] as bool?,
      approvalRequired: json['approvalRequired'] as bool?,
      approvalPeriod: period?['type'] as String?,
      lockBefore: parseDate(json['lockBefore']),
      budgetAlertPercent: (alerts?['budgetPercent'] as num?)?.toInt(),
      estimateAlertPercent: (alerts?['estimatePercent'] as num?)?.toInt(),
      updatedAt: parseInstant(json['updatedAt']),
      updatedBy: json['updatedBy'] as String?,
    );
  }

  /// The whole block, as a PUT sends it. An omitted key is "no override", which
  /// is exactly what a null field means here.
  Map<String, dynamic> toJson() => {
    'budgetMinutes': ?budgetMinutes,
    'defaultBillable': ?defaultBillable,
    'approvalRequired': ?approvalRequired,
    if (approvalPeriod != null) 'approvalPeriod': {'type': approvalPeriod},
    if (lockBefore != null) 'lockBefore': formatDateOnly(lockBefore!),
    if (budgetAlertPercent != null || estimateAlertPercent != null)
      'alertThresholds': {
        'budgetPercent': ?budgetAlertPercent,
        'estimatePercent': ?estimateAlertPercent,
      },
  };

  @override
  List<Object?> get props => [
    budgetMinutes,
    defaultBillable,
    approvalRequired,
    approvalPeriod,
    lockBefore,
    budgetAlertPercent,
    estimateAlertPercent,
    updatedAt,
    updatedBy,
  ];
}

/// One recorded change to a time entry, as its owner reads it.
///
/// Narrower than the admin audit feed it comes from: no client address and no
/// user-agent. Those are in the record for an investigation an administrator
/// runs; on a screen every colleague can open they would turn a transparency
/// feature into a way of finding out where somebody works from.
class TimeEntryHistoryEntry extends Equatable {
  const TimeEntryHistoryEntry({
    required this.id,
    required this.action,
    this.timestamp,
    this.actorId,
    this.actorLabel,
    this.metadata = const {},
  });

  final String id;

  /// The server's `AuditAction` name, e.g. `TIME_ENTRY_UPDATED`. Rendered
  /// through `audit.action.<name>` — the same keys the audit screen uses.
  final String action;
  final DateTime? timestamp;
  final String? actorId;

  /// The name as it was when the change happened, so the record keeps saying
  /// who acted after that account is renamed or deleted.
  final String? actorLabel;
  final Map<String, String> metadata;

  factory TimeEntryHistoryEntry.fromJson(Map<String, dynamic> json) =>
      TimeEntryHistoryEntry(
        id: json['id'] as String,
        action: json['action'] as String? ?? 'UNKNOWN',
        timestamp: parseInstant(json['timestamp']),
        actorId: json['actorId'] as String?,
        actorLabel: json['actorLabel'] as String?,
        metadata: ((json['metadata'] as Map<dynamic, dynamic>?) ?? const {})
            .map((key, value) => MapEntry('$key', '$value')),
      );

  @override
  List<Object?> get props => [id, action, timestamp, actorId, actorLabel];
}
