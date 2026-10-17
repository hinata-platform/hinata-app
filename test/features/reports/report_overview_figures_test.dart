import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/content_models.dart';
import 'package:hinata/core/models/report_overview_models.dart';
import 'package:hinata/features/reports/report_overview_figures.dart';

/// What the report overview derives from its answer: the open-issue trend
/// and the exported files.
void main() {
  TrendPoint day(int d, int created, int resolved) => TrendPoint(
    date: DateTime(2026, 10, d),
    created: created,
    resolved: resolved,
  );

  final overview = ReportOverview(
    projectId: 'p1',
    days: 90,
    byState: const {'Open': 4, 'Done': 6},
    byPriority: const {'HIGH': 3},
    byAssignee: const {'u1': 2, ReportOverview.unassigned: 1},
    trend: [day(1, 2, 0), day(2, 0, 1), day(3, 1, 0)],
    timePerActivity: const {'work': 90},
  );

  test('the trend ends at today\'s open count and is worked back from it', () {
    final burn = burndownOf(overview, {'Done'});

    expect(burn.remaining, 4);
    // Open at the end of each day: today's 4, less what the later days added.
    expect(burn.points.map((p) => p.remaining), [4.0, 3.0, 4.0]);
    // The straight line runs from the first day's count to zero.
    expect(burn.points.first.ideal, 4.0);
    expect(burn.points.last.ideal, 0.0);
  });

  test('fewer than two days draw no trend but still count the open', () {
    final short = ReportOverview(
      projectId: 'p1',
      byState: const {'Open': 3},
      trend: [day(1, 1, 0)],
    );

    final burn = burndownOf(short, const {});
    expect(burn.points, isEmpty);
    expect(burn.remaining, 3);
  });

  String label(OverviewSection section, String key) =>
      key == ReportOverview.unassigned ? 'Niemand, "nobody"' : key;

  test('the CSV names every section and quotes what needs it', () {
    final csv = overviewCsv(overview, label).trim().split('\n');

    expect(csv.first, 'report,label,value');
    expect(csv, contains('issues-by-state,Open,4'));
    expect(csv, contains('issues-by-assignee,"Niemand, ""nobody""",1'));
    expect(csv, contains('time-per-activity,work,90'));
  });

  test('the JSON carries the span, the moment and every section', () {
    final json =
        jsonDecode(
              overviewJson(
                overview,
                projectName: 'Hinata',
                label: label,
                generatedAt: DateTime.utc(2026, 10, 17, 12),
              ),
            )
            as Map<String, dynamic>;

    expect(json['project'], 'Hinata');
    expect(json['days'], 90);
    expect(json['generatedAt'], '2026-10-17T12:00:00.000Z');
    expect((json['reports'] as Map).keys, [
      'issues-by-state',
      'issues-by-priority',
      'issues-by-assignee',
      'time-per-activity',
    ]);
  });
}
