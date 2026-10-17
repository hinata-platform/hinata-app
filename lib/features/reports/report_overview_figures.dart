import 'dart:convert';
import 'dart:math' as math;

import '../../core/models/report_overview_models.dart';

/// What the report overview derives from its answer (HIN-157), kept apart from
/// the widgets so it can be tested as plain functions: the open-issue trend,
/// and the CSV and JSON a reader exports.

/// The overview's four distributions, in the order they are drawn and
/// exported. [key] is the name a file uses for the section.
enum OverviewSection {
  state('issues-by-state'),
  priority('issues-by-priority'),
  assignee('issues-by-assignee'),
  activity('time-per-activity');

  const OverviewSection(this.key);
  final String key;

  /// The section's i18n title key.
  String get titleKey => 'reports.$key';

  Map<String, int> valuesOf(ReportOverview overview) => switch (this) {
    state => overview.byState,
    priority => overview.byPriority,
    assignee => overview.byAssignee,
    activity => overview.timePerActivity,
  };
}

/// Names one key of one section for a reader: a state, a priority, a person.
typedef OverviewLabel = String Function(OverviewSection section, String key);

/// One day of the open-issue trend, with the straight line to zero beside it.
typedef OverviewDay = ({int day, double remaining, double ideal});

/// The open issues over the span and how many are open today.
typedef OverviewBurndown = ({List<OverviewDay> points, int remaining});

/// The open issues on each day of the span, worked backwards from today's
/// count (every issue not in one of [resolvedStates]), with a straight line
/// from the first day's count to zero to read it against. No points with
/// fewer than two days.
OverviewBurndown burndownOf(
  ReportOverview overview,
  Set<String> resolvedStates,
) {
  final openNow = overview.byState.entries
      .where((entry) => !resolvedStates.contains(entry.key))
      .fold<int>(0, (sum, entry) => sum + entry.value);
  if (overview.trend.length < 2) {
    return (points: const [], remaining: openNow);
  }
  final running = <int>[];
  var run = 0;
  for (final point in overview.trend) {
    run += point.created - point.resolved;
    running.add(run);
  }
  final remaining = [
    for (final value in running)
      math.max(0, openNow - running.last + value).toDouble(),
  ];
  final start = remaining.first;
  final n = remaining.length;
  return (
    points: [
      for (var i = 0; i < n; i++)
        (day: i, remaining: remaining[i], ideal: start * (1 - i / (n - 1))),
    ],
    remaining: openNow,
  );
}

/// Every section as `report,label,value` rows, values as the server counted
/// them (minutes for the activities).
String overviewCsv(ReportOverview overview, OverviewLabel label) {
  String esc(String s) => s.contains(',') || s.contains('"') || s.contains('\n')
      ? '"${s.replaceAll('"', '""')}"'
      : s;
  final out = StringBuffer('report,label,value\n');
  for (final section in OverviewSection.values) {
    for (final entry in section.valuesOf(overview).entries) {
      out.writeln(
        '${esc(section.key)},${esc(label(section, entry.key))},${entry.value}',
      );
    }
  }
  return out.toString();
}

/// The same figures as one JSON document, with the project and the moment.
String overviewJson(
  ReportOverview overview, {
  required String projectName,
  required OverviewLabel label,
  required DateTime generatedAt,
}) => const JsonEncoder.withIndent('  ').convert({
  'project': projectName,
  'days': overview.days,
  'generatedAt': generatedAt.toUtc().toIso8601String(),
  'reports': {
    for (final section in OverviewSection.values)
      section.key: {
        for (final entry in section.valuesOf(overview).entries)
          label(section, entry.key): entry.value,
      },
  },
});
