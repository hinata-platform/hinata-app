import 'package:equatable/equatable.dart';

/// How far a gauge has run, in the three steps every budget surface shows
/// (HIN-151): under the warning share, from it up to the limit, and from the
/// limit on.
enum BudgetLevel { within, near, over }

/// One amount measured against one limit: recorded minutes against a budget or
/// an estimate, or cents against a money budget.
///
/// A value, nothing more. Where the numbers come from is the repository's job;
/// what they look like is the widget's. Both units are whole numbers, so the
/// same gauge serves minutes and cents without a conversion step.
class BudgetGauge extends Equatable {
  const BudgetGauge({
    required this.used,
    required this.limit,
    this.nearPercent = defaultNearPercent,
  });

  /// From this share of the limit on, a gauge reads as [BudgetLevel.near].
  /// Mirrors the server's default budget alert threshold.
  static const defaultNearPercent = 80;

  final int used;

  /// Always above zero: a limit of nothing is no limit, and the surfaces show
  /// nothing at all for it rather than an endless "over".
  final int limit;

  final int nearPercent;

  /// Used against the limit; above 1 once the limit is passed.
  double get fraction => used / limit;

  /// Whole percent, rounded towards the limit's side: down below it, so
  /// 99.6 % never reads as a reached 100 %, and up past it, so 100.4 % never
  /// reads as "exactly used up".
  int get percent =>
      used > limit ? (used * 100 + limit - 1) ~/ limit : (used * 100) ~/ limit;

  /// What is still available; zero once the limit is reached.
  int get left => used >= limit ? 0 : limit - used;

  /// How far past the limit; zero while under it.
  int get overBy => used > limit ? used - limit : 0;

  /// Exactly at the limit: already [BudgetLevel.over], because from 100 %
  /// on the form speaks in the danger colour, but nothing to be "over by".
  bool get reached => used == limit;

  BudgetLevel get level {
    if (used >= limit) return BudgetLevel.over;
    if (used * 100 >= limit * nearPercent) return BudgetLevel.near;
    return BudgetLevel.within;
  }

  /// A gauge, or null when there is no limit to measure against.
  static BudgetGauge? of(int? used, int? limit, {int? nearPercent}) {
    if (limit == null || limit <= 0) return null;
    return BudgetGauge(
      used: used ?? 0,
      limit: limit,
      nearPercent: nearPercent ?? defaultNearPercent,
    );
  }

  @override
  List<Object?> get props => [used, limit, nearPercent];
}

/// What a project has used against its budget and estimates (HIN-152).
///
/// Sums of the whole project, whoever recorded them; the server never answers
/// them per person.
class ProjectTimeUsage extends Equatable {
  const ProjectTimeUsage({
    required this.projectId,
    this.budgetMinutes,
    this.usedMinutes = 0,
    this.estimatedMinutes = 0,
    this.nearPercent = BudgetGauge.defaultNearPercent,
    this.budgetWarns = true,
    this.estimateWarns = true,
    this.budgetCents,
    this.usedCents,
    this.currency,
    this.costBudget = false,
    this.unbilledMinutes = 0,
    this.unratedMinutes = 0,
  });

  factory ProjectTimeUsage.fromJson(Map<String, dynamic> json) =>
      ProjectTimeUsage(
        // Anything but an explicit OPEN warns: WARN is the server's default.
        budgetWarns: json['budgetLimitMode'] != 'OPEN',
        estimateWarns: json['estimateLimitMode'] != 'OPEN',
        budgetCents: (json['budgetCents'] as num?)?.toInt(),
        usedCents: (json['usedCents'] as num?)?.toInt(),
        currency: json['currency'] as String?,
        costBudget: json['budgetRateKind'] == 'COST',
        unbilledMinutes: (json['unbilledMinutes'] as num?)?.toInt() ?? 0,
        unratedMinutes: (json['unratedMinutes'] as num?)?.toInt() ?? 0,
        projectId: json['projectId'] as String,
        budgetMinutes: (json['budgetMinutes'] as num?)?.toInt(),
        usedMinutes: (json['usedMinutes'] as num?)?.toInt() ?? 0,
        estimatedMinutes: (json['estimatedMinutes'] as num?)?.toInt() ?? 0,
        nearPercent:
            (json['nearPercent'] as num?)?.toInt() ??
            BudgetGauge.defaultNearPercent,
      );

  final String projectId;

  /// Null when the project has no time budget.
  final int? budgetMinutes;
  final int usedMinutes;

  /// The open issues' estimates added up; zero when none is estimated.
  final int estimatedMinutes;

  /// The share from which the surfaces warn: the project's own budget alert
  /// threshold or the server's default.
  final int nearPercent;

  /// Whether the form says so while recording (HIN-153): the project's budget
  /// mode is WARN rather than OPEN. Recording is never refused either way.
  final bool budgetWarns;

  /// The same for its issues' estimates.
  final bool estimateWarns;

  /// The money budget and what it has used, in cents of [currency]
  /// (HIN-155); null for a reader who may not see them, and without one.
  final int? budgetCents;
  final int? usedCents;
  final String? currency;

  /// Valued at cost rates rather than revenue.
  final bool costBudget;

  /// Recorded minutes the money budget does not count (HIN-158): entries
  /// that are not billable, which a revenue budget leaves out, and entries no
  /// rate was in force for on their day. Zero without a money budget.
  final int unbilledMinutes;
  final int unratedMinutes;

  /// Used against the money budget, or null.
  BudgetGauge? get money => currency == null
      ? null
      : BudgetGauge.of(usedCents, budgetCents, nearPercent: nearPercent);

  /// Recorded time against the budget, or null without one.
  BudgetGauge? get budget =>
      BudgetGauge.of(usedMinutes, budgetMinutes, nearPercent: nearPercent);

  /// Recorded time against the summed estimates, or null without any.
  BudgetGauge? get estimates =>
      BudgetGauge.of(usedMinutes, estimatedMinutes, nearPercent: nearPercent);

  @override
  List<Object?> get props => [
    projectId,
    budgetMinutes,
    usedMinutes,
    estimatedMinutes,
    nearPercent,
    budgetWarns,
    estimateWarns,
    budgetCents,
    usedCents,
    currency,
    costBudget,
    unbilledMinutes,
    unratedMinutes,
  ];
}

/// What one issue has used against its own estimate (HIN-152).
class IssueTimeUsage extends Equatable {
  const IssueTimeUsage({
    required this.issueId,
    required this.projectId,
    this.estimateMinutes,
    this.spentMinutes = 0,
    this.nearPercent = BudgetGauge.defaultNearPercent,
    this.warns = true,
  });

  factory IssueTimeUsage.fromJson(Map<String, dynamic> json) => IssueTimeUsage(
    warns: json['estimateLimitMode'] != 'OPEN',
    issueId: json['issueId'] as String,
    projectId: json['projectId'] as String,
    estimateMinutes: (json['estimateMinutes'] as num?)?.toInt(),
    spentMinutes: (json['spentMinutes'] as num?)?.toInt() ?? 0,
    nearPercent:
        (json['nearPercent'] as num?)?.toInt() ??
        BudgetGauge.defaultNearPercent,
  );

  final String issueId;
  final String projectId;

  /// Null when the issue is not estimated.
  final int? estimateMinutes;
  final int spentMinutes;
  final int nearPercent;

  /// Whether the form says so while recording (HIN-153).
  final bool warns;

  /// Spent time against the estimate, or null without one.
  BudgetGauge? get estimate =>
      BudgetGauge.of(spentMinutes, estimateMinutes, nearPercent: nearPercent);

  @override
  List<Object?> get props => [
    issueId,
    projectId,
    estimateMinutes,
    spentMinutes,
    nearPercent,
    warns,
  ];
}

/// The fullest budgets the reader can see, for the dashboard (HIN-152).
class TopBudgets extends Equatable {
  const TopBudgets({
    this.items = const [],
    this.names = const {},
    this.total = 0,
    this.forecasts = const {},
  });

  factory TopBudgets.fromJson(Map<String, dynamic> json) => TopBudgets(
    items: [
      for (final row in (json['items'] as List<dynamic>? ?? const []))
        ProjectTimeUsage.fromJson(row as Map<String, dynamic>),
    ],
    names: {
      for (final entry
          in (json['names'] as Map<String, dynamic>? ?? const {}).entries)
        entry.key: '${entry.value}',
    },
    total: (json['total'] as num?)?.toInt() ?? 0,
    forecasts: {
      for (final entry
          in (json['forecasts'] as Map<String, dynamic>? ?? const {}).entries)
        entry.key: BudgetForecast.fromJson(entry.value as Map<String, dynamic>),
    },
  );

  /// Fullest first.
  final List<ProjectTimeUsage> items;

  /// Project names by id, for the items.
  final Map<String, String> names;

  /// Every budget the reader can see, of which [items] are the first.
  final int total;

  /// The forecast of each item by project, sent along so a card asks
  /// nothing more (HIN-156). Empty from a server that does not send them.
  final Map<String, BudgetForecast> forecasts;

  @override
  List<Object?> get props => [items, names, total, forecasts];
}

/// Recorded minutes per day for a project's burn-down (HIN-156): the days in
/// a span with time on them, and the sum of everything before it.
class BudgetHistory extends Equatable {
  const BudgetHistory({
    required this.from,
    required this.to,
    this.before = 0,
    this.days = const [],
  });

  factory BudgetHistory.fromJson(Map<String, dynamic> json) => BudgetHistory(
    from: DateTime.parse(json['from'] as String),
    to: DateTime.parse(json['to'] as String),
    before: (json['before'] as num?)?.toInt() ?? 0,
    days: [
      for (final row in (json['days'] as List<dynamic>? ?? const []))
        (
          date: DateTime.parse((row as Map<String, dynamic>)['date'] as String),
          minutes: (row['minutes'] as num).toInt(),
        ),
    ],
  );

  final DateTime from;
  final DateTime to;

  /// Everything recorded before [from].
  final int before;
  final List<({DateTime date, int minutes})> days;

  /// The running total at the end of each day of the span, every day
  /// included, so a line drawn from it has no gaps.
  List<({DateTime date, int total})> get cumulative {
    final byDay = {for (final day in days) _key(day.date): day.minutes};
    final out = <({DateTime date, int total})>[];
    var total = before;
    for (
      var day = DateTime(from.year, from.month, from.day);
      !day.isAfter(to);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      total += byDay[_key(day)] ?? 0;
      out.add((date: day, total: total));
    }
    return out;
  }

  static String _key(DateTime day) => '${day.year}-${day.month}-${day.day}';

  @override
  List<Object?> get props => [from, to, before, days];
}

/// When a budget runs out at the present pace (HIN-156).
class BudgetForecast extends Equatable {
  const BudgetForecast({
    this.dailyMinutes = 0,
    this.dataDays = 0,
    this.leftMinutes,
    this.exhaustedOn,
    this.lowConfidence = true,
  });

  factory BudgetForecast.fromJson(Map<String, dynamic> json) => BudgetForecast(
    dailyMinutes: (json['dailyMinutes'] as num?)?.toInt() ?? 0,
    dataDays: (json['dataDays'] as num?)?.toInt() ?? 0,
    leftMinutes: (json['leftMinutes'] as num?)?.toInt(),
    exhaustedOn: json['exhaustedOn'] == null
        ? null
        : DateTime.parse(json['exhaustedOn'] as String),
    lowConfidence: json['confidence'] != 'OK',
  );

  /// Recorded per working day, over the last fourteen days.
  final int dailyMinutes;
  final int dataDays;

  /// Null without a budget.
  final int? leftMinutes;
  final DateTime? exhaustedOn;

  /// Fewer than three days with time: too little to say.
  final bool lowConfidence;

  @override
  List<Object?> get props => [
    dailyMinutes,
    dataDays,
    leftMinutes,
    exhaustedOn,
    lowConfidence,
  ];
}

/// A sprint's budget and what it has used (HIN-156).
class SprintTimeUsage extends Equatable {
  const SprintTimeUsage({
    required this.sprintId,
    this.budgetMinutes,
    this.usedMinutes = 0,
    this.nearPercent = BudgetGauge.defaultNearPercent,
    this.canEdit = false,
  });

  factory SprintTimeUsage.fromJson(Map<String, dynamic> json) =>
      SprintTimeUsage(
        sprintId: json['sprintId'] as String,
        budgetMinutes: (json['budgetMinutes'] as num?)?.toInt(),
        usedMinutes: (json['usedMinutes'] as num?)?.toInt() ?? 0,
        nearPercent:
            (json['nearPercent'] as num?)?.toInt() ??
            BudgetGauge.defaultNearPercent,
        canEdit: json['canEdit'] as bool? ?? false,
      );

  final String sprintId;
  final int? budgetMinutes;
  final int usedMinutes;
  final int nearPercent;

  /// Whether the reader leads one of the board's projects and may set it.
  final bool canEdit;

  BudgetGauge? get gauge =>
      BudgetGauge.of(usedMinutes, budgetMinutes, nearPercent: nearPercent);

  @override
  List<Object?> get props => [
    sprintId,
    budgetMinutes,
    usedMinutes,
    nearPercent,
    canEdit,
  ];
}

/// A running sprint with a budget, on a board the reader sees (HIN-157).
class BudgetedSprint extends Equatable {
  const BudgetedSprint({
    required this.id,
    required this.name,
    required this.board,
    this.gauge,
  });

  factory BudgetedSprint.fromJson(Map<String, dynamic> json) => BudgetedSprint(
    id: json['sprintId'] as String,
    name: json['name'] as String? ?? '',
    board: json['boardName'] as String? ?? '',
    gauge: BudgetGauge.of(
      (json['usedMinutes'] as num?)?.toInt(),
      (json['budgetMinutes'] as num?)?.toInt(),
      nearPercent: (json['nearPercent'] as num?)?.toInt(),
    ),
  );

  final String id;
  final String name;

  /// The board's name.
  final String board;
  final BudgetGauge? gauge;

  @override
  List<Object?> get props => [id, name, board, gauge];
}

/// One page of the budget report (HIN-157): budgets ranked like the
/// dashboard's, and on the first page the running sprints with a budget.
class BudgetReportPage extends Equatable {
  const BudgetReportPage({
    this.budgets = const TopBudgets(),
    this.sprints = const [],
  });

  factory BudgetReportPage.fromJson(Map<String, dynamic> json) =>
      BudgetReportPage(
        budgets: TopBudgets.fromJson(json),
        sprints: [
          for (final row in (json['sprints'] as List<dynamic>? ?? const []))
            BudgetedSprint.fromJson(row as Map<String, dynamic>),
        ],
      );

  final TopBudgets budgets;
  final List<BudgetedSprint> sprints;

  @override
  List<Object?> get props => [budgets, sprints];
}
