import 'package:equatable/equatable.dart';

/// How far a gauge has run, in the three steps every budget surface shows
/// (HIN-151): under the warning share, from it up to the limit, and from the
/// limit on.
enum BudgetLevel { within, near, over }

/// One amount measured against one limit: recorded minutes against a budget or
/// an estimate, or later cents against a money budget.
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
  });

  factory ProjectTimeUsage.fromJson(Map<String, dynamic> json) =>
      ProjectTimeUsage(
        // Anything but an explicit OPEN warns: WARN is the server's default.
        budgetWarns: json['budgetLimitMode'] != 'OPEN',
        estimateWarns: json['estimateLimitMode'] != 'OPEN',
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
  );

  /// Fullest first.
  final List<ProjectTimeUsage> items;

  /// Project names by id, for the items.
  final Map<String, String> names;

  /// Every budget the reader can see, of which [items] are the first.
  final int total;

  @override
  List<Object?> get props => [items, names, total];
}
