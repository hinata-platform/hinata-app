import 'package:equatable/equatable.dart';

/// The report "absences and balances", the yearly run and the notices behind a
/// lapse (HIN-119). Days are thousandths of a working day, exactly as the server
/// sends them.

/// Rows per person for one type, or one row per type summed over the people.
enum AbsenceReportGroupBy {
  person('PERSON'),
  type('TYPE');

  const AbsenceReportGroupBy(this.wire);

  final String wire;

  static AbsenceReportGroupBy fromWire(String? value) =>
      value == 'TYPE' ? AbsenceReportGroupBy.type : AbsenceReportGroupBy.person;
}

/// What the report asks: a leave year, a type, a group, and how to group.
class AbsenceReportQuery extends Equatable {
  const AbsenceReportQuery({
    this.year,
    this.typeId,
    this.teamId,
    this.projectId,
    this.groupBy = AbsenceReportGroupBy.person,
  });

  /// The leave year; null lets the server pick the current one.
  final int? year;
  final String? typeId;
  final String? teamId;
  final String? projectId;
  final AbsenceReportGroupBy groupBy;

  AbsenceReportQuery copyWith({
    Object? year = _keep,
    Object? typeId = _keep,
    Object? teamId = _keep,
    Object? projectId = _keep,
    AbsenceReportGroupBy? groupBy,
  }) => AbsenceReportQuery(
    year: identical(year, _keep) ? this.year : year as int?,
    typeId: identical(typeId, _keep) ? this.typeId : typeId as String?,
    teamId: identical(teamId, _keep) ? this.teamId : teamId as String?,
    projectId: identical(projectId, _keep)
        ? this.projectId
        : projectId as String?,
    groupBy: groupBy ?? this.groupBy,
  );

  Map<String, Object> toQuery() => {
    'year': ?year,
    'typeId': ?typeId,
    'teamId': ?teamId,
    'projectId': ?projectId,
    'groupBy': groupBy.wire,
  };

  @override
  List<Object?> get props => [year, typeId, teamId, projectId, groupBy];
}

const Object _keep = Object();

/// One row's figures. [ratePermille] is present only for a keeper with the
/// absence rate switched on; the server leaves it out otherwise.
class AbsenceFigures extends Equatable {
  const AbsenceFigures({
    this.entitledMilliDays = 0,
    this.carriedInMilliDays = 0,
    this.takenMilliDays = 0,
    this.plannedMilliDays = 0,
    this.remainingMilliDays = 0,
    this.expiringMilliDays = 0,
    this.expiringOn,
    this.ratePermille,
  });

  final int entitledMilliDays;
  final int carriedInMilliDays;
  final int takenMilliDays;
  final int plannedMilliDays;
  final int remainingMilliDays;

  /// What lapses next, and on which day, if nothing is taken before then.
  final int expiringMilliDays;
  final DateTime? expiringOn;

  /// The share of planned working time away, in thousandths.
  final int? ratePermille;

  static AbsenceFigures fromJson(Map<String, dynamic>? json) {
    final data = json ?? const {};
    int read(String key) => (data[key] as num?)?.toInt() ?? 0;
    return AbsenceFigures(
      entitledMilliDays: read('entitledMilliDays'),
      carriedInMilliDays: read('carriedInMilliDays'),
      takenMilliDays: read('takenMilliDays'),
      plannedMilliDays: read('plannedMilliDays'),
      remainingMilliDays: read('remainingMilliDays'),
      expiringMilliDays: read('expiringMilliDays'),
      expiringOn: DateTime.tryParse(data['expiringOn'] as String? ?? ''),
      ratePermille: (data['ratePermille'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [
    entitledMilliDays,
    carriedInMilliDays,
    takenMilliDays,
    plannedMilliDays,
    remainingMilliDays,
    expiringMilliDays,
    expiringOn,
    ratePermille,
  ];
}

/// A person (with their name) or a type, and its figures.
class AbsenceReportRow extends Equatable {
  const AbsenceReportRow({
    this.userId,
    this.name,
    this.typeId,
    this.figures = const AbsenceFigures(),
  });

  final String? userId;
  final String? name;
  final String? typeId;
  final AbsenceFigures figures;

  /// The row's identity in a paged list.
  String get key => userId ?? typeId ?? '';

  static AbsenceReportRow fromJson(Map<String, dynamic> json) =>
      AbsenceReportRow(
        userId: json['userId'] as String?,
        name: json['name'] as String?,
        typeId: json['typeId'] as String?,
        figures: AbsenceFigures.fromJson(
          json['figures'] as Map<String, dynamic>?,
        ),
      );

  @override
  List<Object?> get props => [userId, typeId, figures];
}

/// The report's head: what it covers, and the figures over everybody in it.
class AbsenceReportHead extends Equatable {
  const AbsenceReportHead({
    required this.year,
    this.groupBy = AbsenceReportGroupBy.person,
    this.typeId,
    this.rateVisible = false,
    this.people = 0,
    this.totals = const AbsenceFigures(),
  });

  final int year;
  final AbsenceReportGroupBy groupBy;
  final String? typeId;
  final bool rateVisible;
  final int people;
  final AbsenceFigures totals;

  static AbsenceReportHead fromJson(Map<String, dynamic> json) =>
      AbsenceReportHead(
        year: (json['year'] as num?)?.toInt() ?? DateTime.now().year,
        groupBy: AbsenceReportGroupBy.fromWire(json['groupBy'] as String?),
        typeId: json['typeId'] as String?,
        rateVisible: json['rateVisible'] as bool? ?? false,
        people: (json['people'] as num?)?.toInt() ?? 0,
        totals: AbsenceFigures.fromJson(
          json['totals'] as Map<String, dynamic>?,
        ),
      );

  @override
  List<Object?> get props => [
    year,
    groupBy,
    typeId,
    rateVisible,
    people,
    totals,
  ];
}

/// A notice that leave is about to lapse — the record a lapse rests on.
class AbsenceNotice extends Equatable {
  const AbsenceNotice({
    required this.id,
    required this.typeId,
    required this.year,
    required this.kind,
    required this.remainingMilliDays,
    this.expiresOn,
    this.sentAt,
    this.manual = false,
  });

  final String id;
  final String typeId;
  final int year;

  /// `ANNUAL`, `BEFORE_YEAR_END`, `BEFORE_CARRYOVER_DEADLINE` or `MANUAL`.
  final String kind;
  final int remainingMilliDays;
  final DateTime? expiresOn;
  final DateTime? sentAt;
  final bool manual;

  static AbsenceNotice fromJson(Map<String, dynamic> json) => AbsenceNotice(
    id: json['id'] as String? ?? '',
    typeId: json['typeId'] as String? ?? '',
    year: (json['year'] as num?)?.toInt() ?? 0,
    kind: json['kind'] as String? ?? 'ANNUAL',
    remainingMilliDays: (json['remainingMilliDays'] as num?)?.toInt() ?? 0,
    expiresOn: DateTime.tryParse(json['expiresOn'] as String? ?? ''),
    sentAt: DateTime.tryParse(json['sentAt'] as String? ?? '')?.toLocal(),
    manual: json['manual'] as bool? ?? false,
  );

  @override
  List<Object?> get props => [id];
}

/// Somebody whose days would lapse on a deadline nobody told them about.
class AbsenceMissingNotice extends Equatable {
  const AbsenceMissingNotice({
    required this.userId,
    required this.typeId,
    required this.year,
    required this.milliDays,
    this.name,
    this.deadline,
    this.overdue = false,
  });

  final String userId;
  final String? name;
  final String typeId;
  final int year;
  final int milliDays;
  final DateTime? deadline;

  /// The deadline passed: the run held the days because nobody was told.
  final bool overdue;

  String get key => '$userId:$typeId:$year';

  static AbsenceMissingNotice fromJson(Map<String, dynamic> json) =>
      AbsenceMissingNotice(
        userId: json['userId'] as String? ?? '',
        name: json['name'] as String?,
        typeId: json['typeId'] as String? ?? '',
        year: (json['year'] as num?)?.toInt() ?? 0,
        milliDays: (json['milliDays'] as num?)?.toInt() ?? 0,
        deadline: DateTime.tryParse(json['deadline'] as String? ?? ''),
        overdue: json['overdue'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [key, milliDays, overdue];
}

/// A proposed lapse after a long illness, waiting for a keeper.
class AbsenceProposal extends Equatable {
  const AbsenceProposal({
    required this.id,
    required this.userId,
    required this.typeId,
    required this.year,
    required this.milliDays,
    this.name,
    this.sickDays,
    this.windowFrom,
    this.windowTo,
  });

  final String id;
  final String userId;
  final String? name;
  final String typeId;

  /// The leave year the days come from.
  final int year;
  final int milliDays;
  final int? sickDays;
  final DateTime? windowFrom;
  final DateTime? windowTo;

  static AbsenceProposal fromJson(Map<String, dynamic> json) => AbsenceProposal(
    id: json['id'] as String? ?? '',
    userId: json['userId'] as String? ?? '',
    name: json['name'] as String?,
    typeId: json['typeId'] as String? ?? '',
    year: (json['year'] as num?)?.toInt() ?? 0,
    milliDays: (json['milliDays'] as num?)?.toInt() ?? 0,
    sickDays: (json['sickDays'] as num?)?.toInt(),
    windowFrom: DateTime.tryParse(json['windowFrom'] as String? ?? ''),
    windowTo: DateTime.tryParse(json['windowTo'] as String? ?? ''),
  );

  @override
  List<Object?> get props => [id];
}

/// What the yearly run did on its last night.
class AbsenceYearRun extends Equatable {
  const AbsenceYearRun({
    this.day,
    this.finishedAt,
    this.accrued = 0,
    this.carried = 0,
    this.expired = 0,
    this.held = 0,
    this.proposals = 0,
    this.failed = false,
    this.openProposals = 0,
  });

  /// Null when the run never ran.
  final DateTime? day;
  final DateTime? finishedAt;
  final int accrued;
  final int carried;
  final int expired;
  final int held;
  final int proposals;
  final bool failed;

  /// Proposals still waiting, whatever night opened them.
  final int openProposals;

  static AbsenceYearRun fromJson(Map<String, dynamic> json) {
    final last = json['lastRun'] as Map<String, dynamic>?;
    int read(String key) => (last?[key] as num?)?.toInt() ?? 0;
    return AbsenceYearRun(
      day: DateTime.tryParse(last?['day'] as String? ?? ''),
      finishedAt: DateTime.tryParse(
        last?['finishedAt'] as String? ?? '',
      )?.toLocal(),
      accrued: read('accrued'),
      carried: read('carried'),
      expired: read('expired'),
      held: read('held'),
      proposals: read('proposals'),
      failed: last?['failed'] as bool? ?? false,
      openProposals: (json['openProposals'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [day, finishedAt, held, openProposals, failed];
}

/// What settling one type takes for somebody leaving (§§ 5, 7 Abs. 4 BUrlG).
class AbsenceSettlement extends Equatable {
  const AbsenceSettlement({
    required this.typeId,
    required this.year,
    this.reason,
    this.accruedMilliDays = 0,
    this.bookedMilliDays = 0,
    this.correctionMilliDays = 0,
    this.remainingMilliDays = 0,
    this.payoutMilliDays = 0,
  });

  final String typeId;
  final int year;
  final String? reason;

  /// What the year is worth with the leaving date.
  final int accruedMilliDays;
  final int bookedMilliDays;

  /// The correction to book first; negative for twelfths.
  final int correctionMilliDays;
  final int remainingMilliDays;

  /// What would be left after the correction, and so paid out.
  final int payoutMilliDays;

  static AbsenceSettlement fromJson(Map<String, dynamic> json) {
    int read(String key) => (json[key] as num?)?.toInt() ?? 0;
    return AbsenceSettlement(
      typeId: json['typeId'] as String? ?? '',
      year: read('year'),
      reason: json['reason'] as String?,
      accruedMilliDays: read('accruedMilliDays'),
      bookedMilliDays: read('bookedMilliDays'),
      correctionMilliDays: read('correctionMilliDays'),
      remainingMilliDays: read('remainingMilliDays'),
      payoutMilliDays: read('payoutMilliDays'),
    );
  }

  @override
  List<Object?> get props => [typeId, year, payoutMilliDays];
}
