import 'package:equatable/equatable.dart';

import '../util/dates.dart';

/// Billing (HIN-96): hourly rates, the money reports and invoices.
///
/// Behind the server's `billing` flag, which is only on while the extended
/// time module is on too. Every amount travels in cents with the instance's
/// one currency; nothing here computes money — the server values every entry
/// on its own day and rounds once.

/// What the reader may do with billing (`GET /billing/access`).
class BillingAccess extends Equatable {
  const BillingAccess({
    required this.currency,
    this.admin = false,
    this.costs = false,
    this.invoices = false,
    this.reports = false,
    this.ledProjects = const [],
  });

  /// Nobody: a member who leads nothing, or billing that could not be read.
  static const none = BillingAccess(currency: 'EUR');

  final String currency;
  final bool admin;

  /// Cost rates, costs and margins — organisation admins only.
  final bool costs;
  final bool invoices;
  final bool reports;

  /// The projects whose revenue the reader prices; empty for an admin, who
  /// reaches all of them.
  final List<String> ledProjects;

  /// Whether the reader prices [projectId].
  bool leads(String? projectId) =>
      admin || (projectId != null && ledProjects.contains(projectId));

  factory BillingAccess.fromJson(Map<String, dynamic> json) => BillingAccess(
    currency: json['currency'] as String? ?? 'EUR',
    admin: json['admin'] as bool? ?? false,
    costs: json['costs'] as bool? ?? false,
    invoices: json['invoices'] as bool? ?? false,
    reports: json['reports'] as bool? ?? false,
    ledProjects: [
      for (final id in json['ledProjects'] as List? ?? const []) '$id',
    ],
  );

  @override
  List<Object?> get props => [
    currency,
    admin,
    costs,
    invoices,
    reports,
    ledProjects,
  ];
}

/// Whether a rate prices work for the client or says what it cost.
enum RateKind {
  billable('BILLABLE'),
  cost('COST');

  const RateKind(this.wire);

  final String wire;

  static RateKind parse(String? raw) =>
      raw == 'COST' ? RateKind.cost : RateKind.billable;
}

/// What a rate is set for, most specific first.
enum RateScope {
  issue('ISSUE'),
  projectMember('PROJECT_MEMBER'),
  user('USER'),
  project('PROJECT'),
  team('TEAM'),
  instanceDefault('DEFAULT');

  const RateScope(this.wire);

  final String wire;

  static RateScope parse(String? raw) => RateScope.values.firstWhere(
    (scope) => scope.wire == raw,
    orElse: () => RateScope.instanceDefault,
  );

  String get labelKey => 'billing.scope.$name';
}

/// Whether a rate is in force today, starts later, or has ended.
enum RateStatus {
  active('ACTIVE'),
  planned('PLANNED'),
  ended('ENDED');

  const RateStatus(this.wire);

  final String wire;

  static RateStatus parse(String? raw) => RateStatus.values.firstWhere(
    (status) => status.wire == raw,
    orElse: () => RateStatus.active,
  );

  String get labelKey => 'billing.rateStatus.$name';
}

/// The target of a rate: what a timeline is asked for.
class RateTarget extends Equatable {
  const RateTarget({
    required this.kind,
    required this.scope,
    this.scopeId,
    this.secondaryId,
    this.label,
  });

  final RateKind kind;
  final RateScope scope;
  final String? scopeId;

  /// The person of a member rate.
  final String? secondaryId;

  /// What the sheet calls it; not sent.
  final String? label;

  RateTarget withKind(RateKind next) => RateTarget(
    kind: next,
    scope: scope,
    scopeId: scopeId,
    secondaryId: secondaryId,
    label: label,
  );

  @override
  List<Object?> get props => [kind, scope, scopeId, secondaryId];
}

/// One rate for one target over one span of days.
class BillingRate extends Equatable {
  const BillingRate({
    required this.id,
    required this.kind,
    required this.scope,
    required this.amountCents,
    required this.currency,
    required this.validFrom,
    required this.status,
    this.scopeId,
    this.secondaryId,
    this.projectId,
    this.validTo,
    this.targetLabel,
    this.targetDetail,
    this.memberLabel,
  });

  final String id;
  final RateKind kind;
  final RateScope scope;
  final String? scopeId;
  final String? secondaryId;
  final String? projectId;
  final int amountCents;
  final String currency;
  final DateTime validFrom;

  /// Last day in force, inclusive; null while it runs on.
  final DateTime? validTo;
  final RateStatus status;
  final String? targetLabel;
  final String? targetDetail;
  final String? memberLabel;

  RateTarget get target => RateTarget(
    kind: kind,
    scope: scope,
    scopeId: scopeId,
    secondaryId: secondaryId,
    label: targetLabel,
  );

  factory BillingRate.fromJson(Map<String, dynamic> json) => BillingRate(
    id: json['id'] as String? ?? '',
    kind: RateKind.parse(json['kind'] as String?),
    scope: RateScope.parse(json['scope'] as String?),
    scopeId: json['scopeId'] as String?,
    secondaryId: json['secondaryId'] as String?,
    projectId: json['projectId'] as String?,
    amountCents: (json['amountCents'] as num?)?.toInt() ?? 0,
    currency: json['currency'] as String? ?? 'EUR',
    validFrom: parseDate(json['validFrom']) ?? DateTime(1970),
    validTo: parseDate(json['validTo']),
    status: RateStatus.parse(json['status'] as String?),
    targetLabel: json['targetLabel'] as String?,
    targetDetail: json['targetDetail'] as String?,
    memberLabel: json['memberLabel'] as String?,
  );

  @override
  List<Object?> get props => [
    id,
    kind,
    scope,
    scopeId,
    secondaryId,
    amountCents,
    validFrom,
    validTo,
    status,
    targetLabel,
    memberLabel,
  ];
}

/// Which money report.
enum BillingReportKind {
  billing('billing'),
  profitability('profitability'),
  utilization('utilization');

  const BillingReportKind(this.wire);

  final String wire;

  String get labelKey => 'billing.report.kind.$name';
}

/// What a money report adds up by. Profitability and utilization never group
/// by person (R7).
enum BillingGroupBy {
  project('PROJECT'),
  issue('ISSUE'),
  user('USER'),
  team('TEAM'),
  day('DAY'),
  week('WEEK'),
  month('MONTH');

  const BillingGroupBy(this.wire);

  final String wire;

  bool get time => this == day || this == week || this == month;

  static BillingGroupBy parse(String? raw) => BillingGroupBy.values.firstWhere(
    (group) => group.wire == raw,
    orElse: () => BillingGroupBy.project,
  );

  /// The groupings [kind] allows.
  static List<BillingGroupBy> forKind(
    BillingReportKind kind, {
    required bool people,
  }) => switch (kind) {
    BillingReportKind.billing => [
      project,
      issue,
      if (people) user,
      team,
      day,
      week,
      month,
    ],
    BillingReportKind.profitability => [project, issue, team, day, week, month],
    BillingReportKind.utilization => [project, team, day, week, month],
  };
}

/// One group of a money report, or its totals. Absent figures are null.
class BillingRow extends Equatable {
  const BillingRow({
    this.key,
    this.label,
    this.detail,
    this.minutes = 0,
    this.billableMinutes = 0,
    this.revenueCents,
    this.unratedBillableMinutes,
    this.costCents,
    this.unratedMinutes,
    this.marginCents,
    this.marginPermille,
    this.billablePermille,
    this.capacityMinutes,
    this.capacityPermille,
  });

  final String? key;
  final String? label;
  final String? detail;
  final int minutes;
  final int billableMinutes;
  final int? revenueCents;

  /// Billable minutes no rate covered: billed at nothing.
  final int? unratedBillableMinutes;
  final int? costCents;
  final int? unratedMinutes;
  final int? marginCents;
  final int? marginPermille;
  final int? billablePermille;
  final int? capacityMinutes;
  final int? capacityPermille;

  /// The first day of a time bucket.
  DateTime? get day => parseDate(key);

  static int? _int(Object? value) => (value as num?)?.toInt();

  factory BillingRow.fromJson(Map<String, dynamic> json) => BillingRow(
    key: json['key'] as String?,
    label: json['label'] as String?,
    detail: json['detail'] as String?,
    minutes: _int(json['minutes']) ?? 0,
    billableMinutes: _int(json['billableMinutes']) ?? 0,
    revenueCents: _int(json['revenueCents']),
    unratedBillableMinutes: _int(json['unratedBillableMinutes']),
    costCents: _int(json['costCents']),
    unratedMinutes: _int(json['unratedMinutes']),
    marginCents: _int(json['marginCents']),
    marginPermille: _int(json['marginPermille']),
    billablePermille: _int(json['billablePermille']),
    capacityMinutes: _int(json['capacityMinutes']),
    capacityPermille: _int(json['capacityPermille']),
  );

  @override
  List<Object?> get props => [
    key,
    label,
    minutes,
    billableMinutes,
    revenueCents,
    costCents,
    marginCents,
    billablePermille,
    capacityMinutes,
  ];
}

/// The head of a money report: what it is, in which currency, its totals.
class BillingReportHead extends Equatable {
  const BillingReportHead({
    required this.kind,
    required this.groupBy,
    required this.currency,
    required this.totals,
    required this.costs,
  });

  final BillingReportKind kind;
  final BillingGroupBy groupBy;
  final String currency;
  final BillingRow totals;
  final bool costs;

  @override
  List<Object?> get props => [kind, groupBy, currency, totals, costs];
}

/// Invoice or credit note.
enum InvoiceKind {
  invoice,
  creditNote;

  static InvoiceKind parse(String? raw) =>
      raw == 'CREDIT_NOTE' ? InvoiceKind.creditNote : InvoiceKind.invoice;
}

/// Where a record stands. `issuing` is a moment, shown as a draft.
enum InvoiceStatus {
  draft('DRAFT'),
  issuing('ISSUING'),
  issued('ISSUED');

  const InvoiceStatus(this.wire);

  final String wire;

  static InvoiceStatus parse(String? raw) => InvoiceStatus.values.firstWhere(
    (status) => status.wire == raw,
    orElse: () => InvoiceStatus.draft,
  );
}

/// What one line of an invoice adds up.
enum InvoiceGrouping {
  issue('ISSUE'),
  project('PROJECT'),
  user('USER'),
  day('DAY');

  const InvoiceGrouping(this.wire);

  final String wire;

  static InvoiceGrouping parse(String? raw) => InvoiceGrouping.values
      .firstWhere((group) => group.wire == raw, orElse: () => issue);

  String get labelKey => 'billing.invoice.grouping.$name';
}

/// Who an invoice is addressed to. Free text.
class InvoiceRecipient extends Equatable {
  const InvoiceRecipient({this.name, this.address, this.vatId});

  final String? name;
  final String? address;
  final String? vatId;

  bool get isEmpty =>
      (name ?? '').isEmpty && (address ?? '').isEmpty && (vatId ?? '').isEmpty;

  factory InvoiceRecipient.fromJson(Map<String, dynamic>? json) =>
      InvoiceRecipient(
        name: json?['name'] as String?,
        address: json?['address'] as String?,
        vatId: json?['vatId'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'name': name ?? '',
    'address': address ?? '',
    'vatId': vatId ?? '',
  };

  @override
  List<Object?> get props => [name, address, vatId];
}

/// Net, tax and gross in cents, and the minutes billed.
class InvoiceTotals extends Equatable {
  const InvoiceTotals({
    this.minutes = 0,
    this.netCents = 0,
    this.taxCents = 0,
    this.grossCents = 0,
  });

  final int minutes;
  final int netCents;
  final int taxCents;
  final int grossCents;

  factory InvoiceTotals.fromJson(Map<String, dynamic>? json) => InvoiceTotals(
    minutes: (json?['minutes'] as num?)?.toInt() ?? 0,
    netCents: (json?['netCents'] as num?)?.toInt() ?? 0,
    taxCents: (json?['taxCents'] as num?)?.toInt() ?? 0,
    grossCents: (json?['grossCents'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [minutes, netCents, taxCents, grossCents];
}

/// One invoice or credit note in a list.
class InvoiceSummary extends Equatable {
  const InvoiceSummary({
    required this.id,
    required this.kind,
    required this.status,
    required this.totals,
    required this.currency,
    this.number,
    this.projectId,
    this.projectKey,
    this.projectName,
    this.periodFrom,
    this.periodTo,
    this.recipientName,
    this.issuedAt,
    this.createdAt,
    this.creditNoteId,
    this.creditedInvoiceId,
  });

  final String id;
  final InvoiceKind kind;
  final String? number;
  final InvoiceStatus status;
  final String? projectId;
  final String? projectKey;

  /// Null where the reader is not in the project (HIN-129).
  final String? projectName;
  final DateTime? periodFrom;
  final DateTime? periodTo;
  final String currency;
  final String? recipientName;
  final InvoiceTotals totals;
  final DateTime? issuedAt;
  final DateTime? createdAt;
  final String? creditNoteId;
  final String? creditedInvoiceId;

  bool get isDraft => status != InvoiceStatus.issued;
  bool get isCredited => creditNoteId != null;

  factory InvoiceSummary.fromJson(Map<String, dynamic> json) => InvoiceSummary(
    id: json['id'] as String? ?? '',
    kind: InvoiceKind.parse(json['kind'] as String?),
    number: json['number'] as String?,
    status: InvoiceStatus.parse(json['status'] as String?),
    projectId: json['projectId'] as String?,
    projectKey: json['projectKey'] as String?,
    projectName: json['projectName'] as String?,
    periodFrom: parseDate(json['periodFrom']),
    periodTo: parseDate(json['periodTo']),
    currency: json['currency'] as String? ?? 'EUR',
    recipientName: json['recipientName'] as String?,
    totals: InvoiceTotals.fromJson(json['totals'] as Map<String, dynamic>?),
    issuedAt: parseInstant(json['issuedAt']),
    createdAt: parseInstant(json['createdAt']),
    creditNoteId: json['creditNoteId'] as String?,
    creditedInvoiceId: json['creditedInvoiceId'] as String?,
  );

  @override
  List<Object?> get props => [
    id,
    kind,
    number,
    status,
    projectId,
    totals,
    issuedAt,
    creditNoteId,
    recipientName,
  ];
}

/// One record in full, without its lines (those come in pages).
class InvoiceDetail extends Equatable {
  const InvoiceDetail({
    required this.summary,
    required this.grouping,
    required this.recipient,
    required this.taxBasisPoints,
    required this.lineCount,
    required this.unratedLines,
    required this.editable,
    this.notes,
    this.creditedInvoiceNumber,
    this.creditNoteNumber,
  });

  final InvoiceSummary summary;
  final InvoiceGrouping grouping;
  final InvoiceRecipient recipient;
  final String? notes;

  /// 1900 = 19 %.
  final int taxBasisPoints;
  final int lineCount;
  final int unratedLines;
  final bool editable;
  final String? creditedInvoiceNumber;
  final String? creditNoteNumber;

  factory InvoiceDetail.fromJson(Map<String, dynamic> json) => InvoiceDetail(
    summary: InvoiceSummary.fromJson(
      json['summary'] as Map<String, dynamic>? ?? const {},
    ),
    grouping: InvoiceGrouping.parse(json['grouping'] as String?),
    recipient: InvoiceRecipient.fromJson(
      json['recipient'] as Map<String, dynamic>?,
    ),
    notes: json['notes'] as String?,
    taxBasisPoints: (json['taxBasisPoints'] as num?)?.toInt() ?? 0,
    lineCount: (json['lineCount'] as num?)?.toInt() ?? 0,
    unratedLines: (json['unratedLines'] as num?)?.toInt() ?? 0,
    editable: json['editable'] as bool? ?? false,
    creditedInvoiceNumber: json['creditedInvoiceNumber'] as String?,
    creditNoteNumber: json['creditNoteNumber'] as String?,
  );

  @override
  List<Object?> get props => [
    summary,
    grouping,
    recipient,
    notes,
    taxBasisPoints,
    lineCount,
    unratedLines,
    editable,
    creditNoteNumber,
  ];
}

/// One line of an invoice.
class InvoiceLine extends Equatable {
  const InvoiceLine({
    required this.id,
    required this.description,
    required this.entries,
    required this.minutes,
    required this.rateCents,
    required this.amountCents,
    this.unrated = false,
  });

  final String id;
  final String description;
  final int entries;
  final int minutes;
  final int rateCents;
  final int amountCents;

  /// No rate covered it; an invoice with such a line is not issued.
  final bool unrated;

  factory InvoiceLine.fromJson(Map<String, dynamic> json) => InvoiceLine(
    id: json['id'] as String? ?? '',
    description: json['description'] as String? ?? '',
    entries: (json['entries'] as num?)?.toInt() ?? 0,
    minutes: (json['minutes'] as num?)?.toInt() ?? 0,
    rateCents: (json['rateCents'] as num?)?.toInt() ?? 0,
    amountCents: (json['amountCents'] as num?)?.toInt() ?? 0,
    unrated: json['unrated'] as bool? ?? false,
  );

  @override
  List<Object?> get props => [id, description, minutes, amountCents, unrated];
}

/// What a draft is built from.
class InvoiceDraftRequest extends Equatable {
  const InvoiceDraftRequest({
    required this.projectId,
    required this.from,
    required this.to,
    this.grouping = InvoiceGrouping.issue,
    this.recipient = const InvoiceRecipient(),
    this.notes,
    this.taxBasisPoints = 0,
  });

  final String projectId;
  final DateTime from;
  final DateTime to;
  final InvoiceGrouping grouping;
  final InvoiceRecipient recipient;
  final String? notes;
  final int taxBasisPoints;

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    'from': formatDateOnly(from),
    'to': formatDateOnly(to),
    'grouping': grouping.wire,
    if (!recipient.isEmpty) 'recipient': recipient.toJson(),
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
    'taxBasisPoints': taxBasisPoints,
  };

  @override
  List<Object?> get props => [
    projectId,
    from,
    to,
    grouping,
    recipient,
    notes,
    taxBasisPoints,
  ];
}
