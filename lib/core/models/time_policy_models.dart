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
  });

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
  /// an exception is for.
  ///
  /// This is only the *lock date*. A period somebody has handed in freezes its
  /// entries too, and that answer needs the approvals of the window on screen —
  /// see [lockFor].
  bool isLocked(DateTime? date) {
    final lock = lockBefore;
    if (lock == null || date == null) return false;
    final day = DateTime(date.year, date.month, date.day);
    if (!day.isBefore(DateTime(lock.year, lock.month, lock.day))) return false;
    return !lockExceptions.any((exception) => exception.covers(day));
  }

  /// Why [date] cannot be written, or null when it can.
  ///
  /// The lock date is asked first, because it is the more absolute answer: a day
  /// an administrator has archived stays archived whatever a submission says
  /// about it — and that is exactly how the server resolves it too.
  ///
  /// [frozenPeriods] are the submissions that cover the window on screen, for the
  /// reader's own time and the entry's project. The caller supplies them because
  /// only the caller knows which window it is drawing; passing none answers about
  /// the lock date alone, which is the honest answer for an entry with no project
  /// — those are never handed in.
  TimeLockInfo? lockFor(
    DateTime? date, {
    List<TimesheetApproval> frozenPeriods = const [],
    String? entryId,
  }) {
    if (date == null) return null;
    if (isLocked(date)) {
      return TimeLockInfo(
        reason: 'lockDate',
        lockDate: lockBefore,
        entryId: entryId,
      );
    }
    if (!approvalsEnabled) return null;
    final day = DateTime(date.year, date.month, date.day);
    for (final period in frozenPeriods) {
      if (!period.status.freezes) continue;
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

  factory TimePolicySnapshot.fromJson(Map<String, dynamic> json) {
    final required = json['requiredFields'] as Map<String, dynamic>?;
    final rounding = json['rounding'] as Map<String, dynamic>?;
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
  ];
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

  final int? budgetAlertPercent;
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
