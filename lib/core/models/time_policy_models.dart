import 'package:equatable/equatable.dart';

import '../util/dates.dart';

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
    this.roundingMode = 'NONE',
    this.roundingIncrement = 15,
    this.limitTagAccess = false,
    this.defaultBillable = false,
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
  final DateTime? lockBefore;

  /// `NONE`, `UP`, `DOWN` or `NEAREST` — how reports fold durations. Never
  /// applied to a stored entry.
  final String roundingMode;
  final int roundingIncrement;

  /// Whether only administrators may add words to the tag catalogue.
  final bool limitTagAccess;
  final bool defaultBillable;

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

  /// Whether the day of [date] is frozen. A date-only comparison: the lock is a
  /// calendar day on both sides, and an instant would make it depend on the hour
  /// somebody happened to open the editor.
  bool isLocked(DateTime? date) {
    final lock = lockBefore;
    if (lock == null || date == null) return false;
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).isBefore(DateTime(lock.year, lock.month, lock.day));
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
      roundingMode: rounding?['mode'] as String? ?? 'NONE',
      roundingIncrement: (rounding?['increment'] as num?)?.toInt() ?? 15,
      limitTagAccess: json['limitTagAccess'] as bool? ?? false,
      defaultBillable: json['defaultBillable'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
    requiredProject,
    requiredIssue,
    requiredDescription,
    requiredTag,
    lockBefore,
    roundingMode,
    roundingIncrement,
    limitTagAccess,
    defaultBillable,
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

  final int? budgetAlertPercent;
  final int? estimateAlertPercent;
  final DateTime? updatedAt;
  final String? updatedBy;

  bool get isEmpty =>
      budgetMinutes == null &&
      defaultBillable == null &&
      approvalRequired == null &&
      approvalPeriod == null &&
      budgetAlertPercent == null &&
      estimateAlertPercent == null;

  ProjectTimeSettings copyWith({
    int? budgetMinutes,
    bool? defaultBillable,
    bool? approvalRequired,
    String? approvalPeriod,
    int? budgetAlertPercent,
    int? estimateAlertPercent,
    bool clearBudget = false,
    bool clearDefaultBillable = false,
    bool clearApprovalRequired = false,
    bool clearApprovalPeriod = false,
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
