/// Absence management 2.0 (HIN-116): the types an operator offers, what people
/// are entitled to, and the journal their balances are the sum of.
///
/// Behind the server's `absence_management` flag. With it off none of this is
/// reachable and absences stay what stage 10 made them: a span somebody enters
/// that shapes capacity.
///
/// Days travel as thousandths of a working day — 20 days is 20000, half a day
/// is 500. The server stores them that way so a balance cannot drift by a
/// rounding error, and the wire keeps the same integers so the app never has to
/// decide how to add up 8.33 (see [formatDays] for showing one).
library;

import 'package:equatable/equatable.dart';

/// A working day in thousandths, mirroring `TimeOffType.DAY` on the server.
const int kMilliDay = 1000;

/// What an absence *is*, as opposed to how it is administered.
///
/// The kind decides the two things an operator cannot configure: which stored
/// absence type it becomes, and whether approval may be required at all. A
/// [AbsenceKind.sick] type is never subject to approval — § 5 EFZG knows a
/// notification, not a permission.
enum AbsenceKind {
  vacation('VACATION'),
  sick('SICK'),
  special('SPECIAL'),
  unpaid('UNPAID'),
  parental('PARENTAL'),
  training('TRAINING'),
  compensatory('COMPENSATORY'),
  other('OTHER');

  const AbsenceKind(this.wire);

  final String wire;

  String get labelKey => 'absence.kind.$name';

  static AbsenceKind fromWire(Object? value) => values.firstWhere(
    (kind) => kind.wire == value,
    orElse: () => AbsenceKind.other,
  );
}

/// How a yearly allowance arrives.
enum AbsenceAccrual {
  none('NONE'),
  annual('ANNUAL'),
  monthly('MONTHLY');

  const AbsenceAccrual(this.wire);

  final String wire;

  String get labelKey => 'absence.accrual.$name';

  static AbsenceAccrual fromWire(Object? value) => values.firstWhere(
    (accrual) => accrual.wire == value,
    orElse: () => AbsenceAccrual.none,
  );
}

/// What happens to what is left when the leave year ends (§ 7 Abs. 3 BUrlG).
enum AbsenceCarryover {
  none('NONE'),
  unlimited('UNLIMITED'),
  capped('CAPPED');

  const AbsenceCarryover(this.wire);

  final String wire;

  String get labelKey => 'absence.carryover.$name';

  static AbsenceCarryover fromWire(Object? value) => values.firstWhere(
    (carryover) => carryover.wire == value,
    orElse: () => AbsenceCarryover.none,
  );
}

/// Who decides a request for a type. A2 routes it; A1 stores the choice.
enum AbsenceApproverRule {
  teamLead('TEAM_LEAD'),
  named('NAMED'),
  admin('ADMIN'),
  auto('AUTO');

  const AbsenceApproverRule(this.wire);

  final String wire;

  String get labelKey => 'absence.approver.$name';

  static AbsenceApproverRule fromWire(Object? value) => values.firstWhere(
    (rule) => rule.wire == value,
    orElse: () => AbsenceApproverRule.teamLead,
  );
}

/// How much of an absence of a type other people may see. A3 reads it.
enum AbsenceVisibility {
  selfOnly('SELF_ONLY'),
  busyOnly('BUSY_ONLY'),
  type('TYPE');

  const AbsenceVisibility(this.wire);

  final String wire;

  String get labelKey => 'absence.visibility.$name';

  static AbsenceVisibility fromWire(Object? value) => values.firstWhere(
    (visibility) => visibility.wire == value,
    orElse: () => AbsenceVisibility.selfOnly,
  );
}

/// Why a balance moved.
enum AbsenceLedgerKind {
  accrual('ACCRUAL'),
  carryoverIn('CARRYOVER_IN'),
  carryoverOut('CARRYOVER_OUT'),
  adjustment('ADJUSTMENT'),
  booked('BOOKED'),
  returned('RETURNED'),
  expired('EXPIRED'),
  payout('PAYOUT'),
  conversion('CONVERSION');

  const AbsenceLedgerKind(this.wire);

  final String wire;

  String get labelKey => 'absence.ledger.$name';

  static AbsenceLedgerKind fromWire(Object? value) => values.firstWhere(
    (kind) => kind.wire == value,
    orElse: () => AbsenceLedgerKind.adjustment,
  );
}

/// One kind of absence an operator offers, with the rules that belong to it.
class AbsenceType extends Equatable {
  const AbsenceType({
    required this.id,
    required this.key,
    required this.kind,
    this.name,
    this.systemKey,
    this.icon,
    this.hue,
    this.paid = false,
    this.countsAgainstBalance = false,
    this.unlimited = false,
    this.requiresApproval = false,
    this.approverRule = AbsenceApproverRule.teamLead,
    this.halfDaysAllowed = true,
    this.fractionAllowed = false,
    this.minNoticeDays,
    this.maxConsecutiveDays,
    this.negativeBalanceAllowed = false,
    this.negativeLimitMilliDays,
    this.visibility = AbsenceVisibility.selfOnly,
    this.accrual = AbsenceAccrual.none,
    this.allowanceMilliDays = 0,
    this.yearAnchorMonth = 1,
    this.yearAnchorDay = 1,
    this.waitingPeriodMonths = 0,
    this.prorateOnJoin = true,
    this.prorateOnLeave = true,
    this.carryover = AbsenceCarryover.none,
    this.carryoverCapMilliDays,
    this.carryoverExpiresMonth = 3,
    this.carryoverExpiresDay = 31,
    this.active = true,
  });

  final String id;
  final String key;
  final AbsenceKind kind;

  /// What an operator called it, or null for a built-in nobody renamed — then
  /// [systemKey] names the translated label. Null is an answer, not a gap: a
  /// name shipped as data would leave a German instance reading English.
  final String? name;

  /// `vacation`, `sick` or `other` for the three built-ins; null for the rest.
  final String? systemKey;

  final String? icon;
  final int? hue;
  final bool paid;
  final bool countsAgainstBalance;
  final bool unlimited;

  /// The *enforced* value, not the stored flag: a sick type reads false here
  /// however the document was written.
  final bool requiresApproval;

  final AbsenceApproverRule approverRule;
  final bool halfDaysAllowed;
  final bool fractionAllowed;
  final int? minNoticeDays;
  final int? maxConsecutiveDays;
  final bool negativeBalanceAllowed;
  final int? negativeLimitMilliDays;
  final AbsenceVisibility visibility;
  final AbsenceAccrual accrual;
  final int allowanceMilliDays;
  final int yearAnchorMonth;
  final int yearAnchorDay;
  final int waitingPeriodMonths;
  final bool prorateOnJoin;
  final bool prorateOnLeave;
  final AbsenceCarryover carryover;
  final int? carryoverCapMilliDays;
  final int carryoverExpiresMonth;
  final int carryoverExpiresDay;
  final bool active;

  /// Whether this is one of the three an instance cannot delete.
  bool get isSystem => systemKey != null && systemKey!.isNotEmpty;

  /// The i18n key for a built-in's label, or null when the name is the answer.
  String? get systemLabelKey => isSystem ? 'absence.type.$systemKey' : null;

  static AbsenceType fromJson(Map<String, dynamic> json) => AbsenceType(
    id: json['id'] as String? ?? '',
    key: json['key'] as String? ?? '',
    kind: AbsenceKind.fromWire(json['kind']),
    name: (json['name'] as String?)?.trim().isEmpty ?? true
        ? null
        : json['name'] as String?,
    systemKey: json['systemKey'] as String?,
    icon: json['icon'] as String?,
    hue: (json['hue'] as num?)?.toInt(),
    paid: json['paid'] as bool? ?? false,
    countsAgainstBalance: json['countsAgainstBalance'] as bool? ?? false,
    unlimited: json['unlimited'] as bool? ?? false,
    requiresApproval: json['requiresApproval'] as bool? ?? false,
    approverRule: AbsenceApproverRule.fromWire(json['approverRule']),
    halfDaysAllowed: json['halfDaysAllowed'] as bool? ?? true,
    fractionAllowed: json['fractionAllowed'] as bool? ?? false,
    minNoticeDays: (json['minNoticeDays'] as num?)?.toInt(),
    maxConsecutiveDays: (json['maxConsecutiveDays'] as num?)?.toInt(),
    negativeBalanceAllowed: json['negativeBalanceAllowed'] as bool? ?? false,
    negativeLimitMilliDays: (json['negativeLimitMilliDays'] as num?)?.toInt(),
    visibility: AbsenceVisibility.fromWire(json['visibility']),
    accrual: AbsenceAccrual.fromWire(json['accrual']),
    allowanceMilliDays: (json['allowanceMilliDays'] as num?)?.toInt() ?? 0,
    yearAnchorMonth: (json['yearAnchorMonth'] as num?)?.toInt() ?? 1,
    yearAnchorDay: (json['yearAnchorDay'] as num?)?.toInt() ?? 1,
    waitingPeriodMonths: (json['waitingPeriodMonths'] as num?)?.toInt() ?? 0,
    prorateOnJoin: json['prorateOnJoin'] as bool? ?? true,
    prorateOnLeave: json['prorateOnLeave'] as bool? ?? true,
    carryover: AbsenceCarryover.fromWire(json['carryover']),
    carryoverCapMilliDays: (json['carryoverCapMilliDays'] as num?)?.toInt(),
    carryoverExpiresMonth: (json['carryoverExpiresMonth'] as num?)?.toInt() ?? 3,
    carryoverExpiresDay: (json['carryoverExpiresDay'] as num?)?.toInt() ?? 31,
    active: json['active'] as bool? ?? true,
  );

  @override
  List<Object?> get props => [id, key, name, kind, allowanceMilliDays, active];
}

/// One type's standing for one person and leave year.
class AbsenceBalance extends Equatable {
  const AbsenceBalance({
    required this.typeId,
    required this.year,
    this.entitledMilliDays = 0,
    this.accruedMilliDays = 0,
    this.carriedInMilliDays = 0,
    this.adjustedMilliDays = 0,
    this.takenMilliDays = 0,
    this.plannedMilliDays = 0,
    this.expiredMilliDays = 0,
    this.paidOutMilliDays = 0,
    this.remainingMilliDays = 0,
    this.expiresOn,
    this.granted = false,
    this.unlimited = false,
    this.reason,
    this.belowLegalMinimum = false,
    this.legalMinimumMilliDays = 0,
  });

  final String typeId;
  final int year;
  final int entitledMilliDays;
  final int accruedMilliDays;
  final int carriedInMilliDays;
  final int adjustedMilliDays;

  /// Days already behind the person.
  final int takenMilliDays;

  /// Days booked and still ahead of them.
  final int plannedMilliDays;

  final int expiredMilliDays;
  final int paidOutMilliDays;
  final int remainingMilliDays;

  /// When what was carried into this year runs out, for a type that carries.
  final DateTime? expiresOn;

  /// Whether the year was granted at all. A missing grant and a zero balance
  /// are different states and the screen says which.
  final bool granted;

  final bool unlimited;

  /// Why the year worked out as it did: `FULL`, `WAITING_PERIOD`, and so on.
  final String? reason;

  /// Whether the allowance is under the statutory minimum for this person's
  /// working week (§ 3 Abs. 1 BUrlG). A warning, never a refusal.
  final bool belowLegalMinimum;

  final int legalMinimumMilliDays;

  static AbsenceBalance fromJson(Map<String, dynamic> json) => AbsenceBalance(
    typeId: json['typeId'] as String? ?? '',
    year: (json['year'] as num?)?.toInt() ?? 0,
    entitledMilliDays: (json['entitledMilliDays'] as num?)?.toInt() ?? 0,
    accruedMilliDays: (json['accruedMilliDays'] as num?)?.toInt() ?? 0,
    carriedInMilliDays: (json['carriedInMilliDays'] as num?)?.toInt() ?? 0,
    adjustedMilliDays: (json['adjustedMilliDays'] as num?)?.toInt() ?? 0,
    takenMilliDays: (json['takenMilliDays'] as num?)?.toInt() ?? 0,
    plannedMilliDays: (json['plannedMilliDays'] as num?)?.toInt() ?? 0,
    expiredMilliDays: (json['expiredMilliDays'] as num?)?.toInt() ?? 0,
    paidOutMilliDays: (json['paidOutMilliDays'] as num?)?.toInt() ?? 0,
    remainingMilliDays: (json['remainingMilliDays'] as num?)?.toInt() ?? 0,
    expiresOn: DateTime.tryParse(json['expiresOn'] as String? ?? ''),
    granted: json['granted'] as bool? ?? false,
    unlimited: json['unlimited'] as bool? ?? false,
    reason: json['reason'] as String?,
    belowLegalMinimum: json['belowLegalMinimum'] as bool? ?? false,
    legalMinimumMilliDays:
        (json['legalMinimumMilliDays'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [typeId, year, remainingMilliDays, granted];
}

/// Everything a balance screen needs in one answer.
class AbsenceBalances extends Equatable {
  const AbsenceBalances({
    required this.userId,
    required this.year,
    required this.workingDaysPerWeek,
    required this.balances,
  });

  final String userId;
  final int year;
  final int workingDaysPerWeek;
  final List<AbsenceBalance> balances;

  static AbsenceBalances fromJson(Map<String, dynamic> json) => AbsenceBalances(
    userId: json['userId'] as String? ?? '',
    year: (json['year'] as num?)?.toInt() ?? 0,
    workingDaysPerWeek: (json['workingDaysPerWeek'] as num?)?.toInt() ?? 5,
    balances: ((json['balances'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AbsenceBalance.fromJson)
        .toList(growable: false),
  );

  @override
  List<Object?> get props => [userId, year, workingDaysPerWeek, balances];
}

/// One movement of a balance. Nothing edits one; a correction is its opposite.
class AbsenceLedgerEntry extends Equatable {
  const AbsenceLedgerEntry({
    required this.id,
    required this.typeId,
    required this.year,
    required this.kind,
    required this.milliDays,
    this.effectiveOn,
    this.reason,
    this.actorId,
    this.refId,
  });

  final String id;
  final String typeId;
  final int year;
  final AbsenceLedgerKind kind;

  /// Signed: positive grants days, negative takes them.
  final int milliDays;

  final DateTime? effectiveOn;
  final String? reason;
  final String? actorId;
  final String? refId;

  static AbsenceLedgerEntry fromJson(Map<String, dynamic> json) =>
      AbsenceLedgerEntry(
        id: json['id'] as String? ?? '',
        typeId: json['typeId'] as String? ?? '',
        year: (json['year'] as num?)?.toInt() ?? 0,
        kind: AbsenceLedgerKind.fromWire(json['kind']),
        milliDays: (json['milliDays'] as num?)?.toInt() ?? 0,
        effectiveOn: DateTime.tryParse(json['effectiveOn'] as String? ?? ''),
        reason: json['reason'] as String?,
        actorId: json['actorId'] as String?,
        refId: json['refId'] as String?,
      );

  @override
  List<Object?> get props => [id, typeId, year, kind, milliDays, effectiveOn];
}

/// That somebody was granted a type for a year, and how much.
class AbsenceEntitlement extends Equatable {
  const AbsenceEntitlement({
    required this.id,
    required this.userId,
    required this.typeId,
    required this.year,
    required this.allowanceMilliDays,
    required this.accruedMilliDays,
    this.source,
    this.note,
  });

  final String id;
  final String userId;
  final String typeId;
  final int year;
  final int allowanceMilliDays;
  final int accruedMilliDays;
  final String? source;
  final String? note;

  static AbsenceEntitlement fromJson(Map<String, dynamic> json) =>
      AbsenceEntitlement(
        id: json['id'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        typeId: json['typeId'] as String? ?? '',
        year: (json['year'] as num?)?.toInt() ?? 0,
        allowanceMilliDays: (json['allowanceMilliDays'] as num?)?.toInt() ?? 0,
        accruedMilliDays: (json['accruedMilliDays'] as num?)?.toInt() ?? 0,
        source: json['source'] as String?,
        note: json['note'] as String?,
      );

  @override
  List<Object?> get props => [id, userId, typeId, year, accruedMilliDays];
}

/// What a bulk grant would do for one person, before it does it.
class AbsenceGrantPreview extends Equatable {
  const AbsenceGrantPreview({
    required this.userId,
    required this.accruedMilliDays,
    required this.alreadyGranted,
    this.reason,
  });

  final String userId;
  final int accruedMilliDays;
  final bool alreadyGranted;
  final String? reason;

  static AbsenceGrantPreview fromJson(Map<String, dynamic> json) =>
      AbsenceGrantPreview(
        userId: json['userId'] as String? ?? '',
        accruedMilliDays: (json['accruedMilliDays'] as num?)?.toInt() ?? 0,
        alreadyGranted: json['alreadyGranted'] as bool? ?? false,
        reason: json['reason'] as String?,
      );

  @override
  List<Object?> get props => [userId, accruedMilliDays, alreadyGranted];
}

/// When somebody joined and left. The only personal facts the module keeps.
class EmploymentDates extends Equatable {
  const EmploymentDates({
    required this.userId,
    this.hiredOn,
    this.leftOn,
    this.note,
  });

  final String userId;
  final DateTime? hiredOn;
  final DateTime? leftOn;
  final String? note;

  bool get isEmpty => hiredOn == null && leftOn == null;

  static EmploymentDates fromJson(Map<String, dynamic> json) => EmploymentDates(
    userId: json['userId'] as String? ?? '',
    hiredOn: DateTime.tryParse(json['hiredOn'] as String? ?? ''),
    leftOn: DateTime.tryParse(json['leftOn'] as String? ?? ''),
    note: json['note'] as String?,
  );

  @override
  List<Object?> get props => [userId, hiredOn, leftOn, note];
}

/// Thousandths of a working day as a number of days, trimmed of trailing zeros.
///
/// Rendered rather than rounded: five twelfths of twenty days is 8.333 and the
/// screen says 8.33, because rounding it to 8 on the way in would be telling
/// somebody they have less leave than the law gave them (§ 5 Abs. 2 BUrlG).
String formatDays(int milliDays, {String decimalSeparator = '.'}) {
  final negative = milliDays < 0;
  final value = milliDays.abs();
  final whole = value ~/ kMilliDay;
  final rest = value % kMilliDay;
  final sign = negative ? '-' : '';
  if (rest == 0) return '$sign$whole';
  // Two places is enough for half days, quarter days and toggl's 0.375; a third
  // place would be a precision the arithmetic does not claim.
  final hundredths = (rest / 10).round().toString().padLeft(2, '0');
  final trimmed = hundredths.endsWith('0')
      ? hundredths.substring(0, 1)
      : hundredths;
  return '$sign$whole$decimalSeparator$trimmed';
}
