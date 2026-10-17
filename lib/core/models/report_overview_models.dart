import 'package:equatable/equatable.dart';

import 'content_models.dart' show TrendPoint;

/// Everything the report overview draws for one project, in one answer
/// (HIN-157): the three distributions, the trend and the time per activity.
class ReportOverview extends Equatable {
  const ReportOverview({
    required this.projectId,
    this.days = 30,
    this.byState = const {},
    this.byPriority = const {},
    this.byAssignee = const {},
    this.trend = const [],
    this.timePerActivity = const {},
  });

  factory ReportOverview.fromJson(Map<String, dynamic> json) {
    Map<String, int> counts(Object? raw) => {
      for (final entry in (raw as Map<String, dynamic>? ?? const {}).entries)
        entry.key: (entry.value as num).toInt(),
    };
    return ReportOverview(
      projectId: json['projectId'] as String,
      days: (json['days'] as num?)?.toInt() ?? 30,
      byState: counts(json['byState']),
      byPriority: counts(json['byPriority']),
      byAssignee: counts(json['byAssignee']),
      trend: [
        for (final row in (json['trend'] as List<dynamic>? ?? const []))
          TrendPoint.fromJson(row as Map<String, dynamic>),
      ],
      timePerActivity: counts(json['timePerActivity']),
    );
  }

  final String projectId;
  final int days;
  final Map<String, int> byState;
  final Map<String, int> byPriority;
  final Map<String, int> byAssignee;
  final List<TrendPoint> trend;

  /// Minutes per activity over the same span.
  final Map<String, int> timePerActivity;

  int get totalIssues => byState.values.fold(0, (sum, count) => sum + count);

  int get createdInSpan => trend.fold(0, (sum, point) => sum + point.created);

  int get resolvedInSpan => trend.fold(0, (sum, point) => sum + point.resolved);

  int get minutesInSpan =>
      timePerActivity.values.fold(0, (sum, minutes) => sum + minutes);

  @override
  List<Object?> get props => [
    projectId,
    days,
    byState,
    byPriority,
    byAssignee,
    trend,
    timePerActivity,
  ];
}
