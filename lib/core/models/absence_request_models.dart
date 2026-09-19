/// Absence management 2.0 (HIN-117): asking for time off, what became of the
/// asking, and reporting sickness — which is none of that.
///
/// **The request is the document and the absence is its result.** Approving one
/// writes exactly one absence and exactly one movement of a balance, and the
/// request keeps both ids so cancelling can undo precisely those. Nothing here
/// computes a balance: every figure on every screen is a sum the server made.
///
/// Days travel as thousandths of a working day, as everywhere else in this
/// module ([kMilliDay]).
library;

import 'package:equatable/equatable.dart';

import '../util/dates.dart';
import 'absence_models.dart';

/// Where a request stands.
///
/// The three ends differ in who ended it — the person ([withdrawn]), whoever
/// decided it ([rejected]), or either of them afterwards ([cancelled]) — and a
/// screen that collapsed them into one would lose the only question anybody
/// asks about an old request.
enum AbsenceRequestStatus {
  submitted('SUBMITTED'),
  approved('APPROVED'),
  rejected('REJECTED'),
  withdrawn('WITHDRAWN'),
  cancelled('CANCELLED');

  const AbsenceRequestStatus(this.wire);

  final String wire;

  String get labelKey => 'absence.request.status.$name';

  /// Whether a decision can still be made, which is also whether the person can
  /// still take it back.
  bool get open => this == AbsenceRequestStatus.submitted;

  static AbsenceRequestStatus fromWire(Object? value) => values.firstWhere(
    (status) => status.wire == value,
    orElse: () => AbsenceRequestStatus.submitted,
  );
}

/// One step of a request's story, in the order it happened.
class AbsenceRequestEvent extends Equatable {
  const AbsenceRequestEvent({this.at, this.by, this.from, this.to, this.note});

  final DateTime? at;

  /// Who acted, or null for something the server did on its own — § 9 BUrlG
  /// shortening leave is the one that happens today.
  final String? by;

  /// Null on the first step: a request comes from nowhere.
  final AbsenceRequestStatus? from;
  final AbsenceRequestStatus? to;
  final String? note;

  static AbsenceRequestEvent fromJson(Map<String, dynamic> json) =>
      AbsenceRequestEvent(
        at: parseInstant(json['at']),
        by: json['by'] as String?,
        from: json['from'] == null
            ? null
            : AbsenceRequestStatus.fromWire(json['from']),
        to: json['to'] == null
            ? null
            : AbsenceRequestStatus.fromWire(json['to']),
        note: json['note'] as String?,
      );

  @override
  List<Object?> get props => [at, by, from, to, note];
}

/// A request, with the few things a screen needs beside it.
class AbsenceRequest extends Equatable {
  const AbsenceRequest({
    required this.id,
    required this.userId,
    required this.typeId,
    required this.from,
    required this.to,
    required this.status,
    this.personName,
    this.typeKey,
    this.typeSystemKey,
    this.firstDayMilliDays,
    this.lastDayMilliDays,
    this.milliDays = 0,
    this.workingDays,
    this.holidays,
    this.note,
    this.approverIds = const [],
    this.decidedBy,
    this.decidedAt,
    this.decisionNote,
    this.substituteId,
    this.timeOffId,
    this.balanceShort = false,
    this.shortNotice = false,
    this.clashes = 0,
    this.history = const [],
    this.createdAt,
  });

  final String id;
  final String userId;
  final String typeId;
  final DateTime from;
  final DateTime to;
  final AbsenceRequestStatus status;

  /// Whose request it is, resolved by the server so a list of twenty-five rows
  /// is not twenty-five lookups.
  final String? personName;

  /// The type's key and, for a built-in nobody renamed, its system key. Enough
  /// to name it without the catalogue, and the catalogue fills in icon and hue.
  final String? typeKey;
  final String? typeSystemKey;

  /// Thousandths the edge days count for; null means a whole day.
  final int? firstDayMilliDays;
  final int? lastDayMilliDays;

  /// What the span cost when it was filed, frozen. A pattern that changes
  /// afterwards does not reinterpret a decision already made.
  final int milliDays;

  final int? workingDays;

  /// Public holidays the span swallowed, which is why it may cost less than it
  /// spans.
  final int? holidays;

  final String? note;
  final List<String> approverIds;
  final String? decidedBy;
  final DateTime? decidedAt;

  /// Why it was decided that way. Required on a rejection (§ 7 Abs. 1 BUrlG).
  final String? decisionNote;

  final String? substituteId;

  /// The absence an approval created, or null while there is none.
  final String? timeOffId;

  /// Whether what is left will not cover it. A yes or a no and never a figure:
  /// a lead deciding leave learns whether the days are there, not how many the
  /// person has (R2, R10).
  final bool balanceShort;

  /// Whether it arrives inside the notice period the type asks for. A warning
  /// to whoever decides, never a refusal.
  final bool shortNotice;

  /// How many other people the reader may know about are away across the same
  /// span. Zero on one's own list, where the question is nobody's business.
  final int clashes;

  final List<AbsenceRequestEvent> history;
  final DateTime? createdAt;

  /// Whether the span is a single half day, which is how the old calendar
  /// already understood one.
  bool get isHalfDay => from == to && firstDayMilliDays == kMilliDay ~/ 2;

  static AbsenceRequest fromJson(Map<String, dynamic> json) => AbsenceRequest(
    id: json['id'] as String? ?? '',
    userId: json['userId'] as String? ?? '',
    typeId: json['typeId'] as String? ?? '',
    from: parseDate(json['from']) ?? DateTime.now(),
    to: parseDate(json['to']) ?? parseDate(json['from']) ?? DateTime.now(),
    status: AbsenceRequestStatus.fromWire(json['status']),
    personName: json['personName'] as String?,
    typeKey: json['typeKey'] as String?,
    typeSystemKey: json['typeSystemKey'] as String?,
    firstDayMilliDays: (json['firstDayMilliDays'] as num?)?.toInt(),
    lastDayMilliDays: (json['lastDayMilliDays'] as num?)?.toInt(),
    milliDays: (json['milliDays'] as num?)?.toInt() ?? 0,
    workingDays: (json['workingDays'] as num?)?.toInt(),
    holidays: (json['holidays'] as num?)?.toInt(),
    note: json['note'] as String?,
    approverIds: [
      for (final id in (json['approverIds'] as List<dynamic>?) ?? const [])
        if (id is String) id,
    ],
    decidedBy: json['decidedBy'] as String?,
    decidedAt: parseInstant(json['decidedAt']),
    decisionNote: json['decisionNote'] as String?,
    substituteId: json['substituteId'] as String?,
    timeOffId: json['timeOffId'] as String?,
    balanceShort: json['balanceShort'] as bool? ?? false,
    shortNotice: json['shortNotice'] as bool? ?? false,
    clashes: (json['clashes'] as num?)?.toInt() ?? 0,
    history: [
      for (final step in (json['history'] as List<dynamic>?) ?? const [])
        if (step is Map<String, dynamic>) AbsenceRequestEvent.fromJson(step),
    ],
    createdAt: parseInstant(json['createdAt']),
  );

  @override
  List<Object?> get props => [id, status, from, to, milliDays, decidedAt];
}

/// What a span would cost, while somebody is still picking the dates.
class AbsencePreview extends Equatable {
  const AbsencePreview({
    this.milliDays = 0,
    this.workingDays = 0,
    this.holidays = 0,
    this.daysOff = 0,
    this.balanceShort = false,
    this.shortNotice = false,
  });

  final int milliDays;
  final int workingDays;

  /// Public holidays inside the span. Named on the form so the figure carries
  /// its reason: a number on its own invites the suspicion that something was
  /// miscounted, the same number beside its reason does not.
  final int holidays;

  /// Days nobody works: weekends and the days a part-time pattern leaves empty.
  final int daysOff;

  final bool balanceShort;
  final bool shortNotice;

  static AbsencePreview fromJson(Map<String, dynamic> json) => AbsencePreview(
    milliDays: (json['milliDays'] as num?)?.toInt() ?? 0,
    workingDays: (json['workingDays'] as num?)?.toInt() ?? 0,
    holidays: (json['holidays'] as num?)?.toInt() ?? 0,
    daysOff: (json['daysOff'] as num?)?.toInt() ?? 0,
    balanceShort: json['balanceShort'] as bool? ?? false,
    shortNotice: json['shortNotice'] as bool? ?? false,
  );

  @override
  List<Object?> get props => [milliDays, workingDays, holidays, daysOff];
}

/// Somebody else away across the same span: who, when, and whether it is
/// already settled.
///
/// Never what kind of absence. Whether a colleague is on holiday or ill is not
/// part of this decision, and a clash line that said so would be a way for
/// anybody who ever decides a request to learn it (R10, R11).
class AbsenceClash extends Equatable {
  const AbsenceClash({
    required this.userId,
    required this.from,
    required this.to,
    this.name,
    this.approved = false,
  });

  final String userId;
  final String? name;
  final DateTime from;
  final DateTime to;
  final bool approved;

  static AbsenceClash fromJson(Map<String, dynamic> json) => AbsenceClash(
    userId: json['userId'] as String? ?? '',
    name: json['name'] as String?,
    from: parseDate(json['from']) ?? DateTime.now(),
    to: parseDate(json['to']) ?? DateTime.now(),
    approved: json['approved'] as bool? ?? false,
  );

  @override
  List<Object?> get props => [userId, from, to, approved];
}

/// What somebody asks for, typed rather than a map in a widget.
class AbsenceRequestDraft {
  const AbsenceRequestDraft({
    required this.typeId,
    required this.from,
    this.to,
    this.firstDayMilliDays,
    this.lastDayMilliDays,
    this.note,
    this.substituteId,
  });

  final String typeId;
  final DateTime from;
  final DateTime? to;

  /// Thousandths the first and last day count for; left out they are whole
  /// days. Only the edges, because only the edges can be partial.
  final int? firstDayMilliDays;
  final int? lastDayMilliDays;

  final String? note;
  final String? substituteId;

  Map<String, dynamic> toJson() => {
    'typeId': typeId,
    'from': formatDateOnly(from),
    if (to != null) 'to': formatDateOnly(to!),
    'firstDayMilliDays': ?firstDayMilliDays,
    'lastDayMilliDays': ?lastDayMilliDays,
    if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
    if (substituteId != null && substituteId!.isNotEmpty)
      'substituteId': substituteId,
  };
}

/// Every calendar day [requests] cover, at local midnight.
///
/// Both screens that hatch a requested day build this, and a second
/// implementation of "which days does a span touch" is a second answer waiting
/// to be off by one at the end of a month.
Set<DateTime> daysCovered(Iterable<AbsenceRequest> requests) {
  final days = <DateTime>{};
  for (final request in requests) {
    var day = DateTime(request.from.year, request.from.month, request.from.day);
    final last = DateTime(request.to.year, request.to.month, request.to.day);
    while (!day.isAfter(last)) {
      days.add(day);
      day = DateTime(day.year, day.month, day.day + 1);
    }
  }
  return days;
}

/// What reporting sickness produced, including any leave § 9 BUrlG gave back.
class SickReport extends Equatable {
  const SickReport({
    this.absenceId,
    this.milliDays = 0,
    this.returnedMilliDays = 0,
  });

  final String? absenceId;
  final int milliDays;

  /// Days of approved leave the sickness fell on, handed back to the balance.
  /// Zero unless it overlapped something (§ 9 BUrlG).
  final int returnedMilliDays;

  static SickReport fromJson(Map<String, dynamic> json) => SickReport(
    absenceId: json['absenceId'] as String?,
    milliDays: (json['milliDays'] as num?)?.toInt() ?? 0,
    returnedMilliDays: (json['returnedMilliDays'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [absenceId, milliDays, returnedMilliDays];
}

/// The rules a screen asks about a request, in one place because three asked
/// them in three shapes and had already drifted: the card offered a keeper no
/// cancel on a leave that had begun while the sheet did.
extension AbsenceRequestRules on AbsenceRequest {
  /// Whether [today] — or now — is past the first day of it.
  bool hasStarted([DateTime? today]) => !from.isAfter(
    DateTime(
      (today ?? DateTime.now()).year,
      (today ?? DateTime.now()).month,
      (today ?? DateTime.now()).day,
    ),
  );

  /// Whether this can still be taken back before anybody decided it.
  bool withdrawableBy({required bool mine}) => mine && status.open;

  /// Whether the approved leave can still be called off.
  ///
  /// One's own while all of it is still ahead: once a day of it is behind the
  /// person it is a record of what happened, and only whoever keeps absences
  /// changes a record. The server decides the same way; the button is hidden
  /// rather than offered and refused.
  bool cancellableBy({required bool mine, required bool keeper}) =>
      status == AbsenceRequestStatus.approved &&
      (keeper || (mine && !hasStarted()));
}
