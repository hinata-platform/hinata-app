import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_usage_models.dart';

void main() {
  group('BudgetGauge', () {
    test('stays within below the warning share', () {
      const gauge = BudgetGauge(used: 79, limit: 100);
      expect(gauge.level, BudgetLevel.within);
      expect(gauge.left, 21);
      expect(gauge.overBy, 0);
    });

    test('is near from the warning share up to the limit', () {
      expect(const BudgetGauge(used: 80, limit: 100).level, BudgetLevel.near);
      expect(const BudgetGauge(used: 99, limit: 100).level, BudgetLevel.near);
    });

    test('is over from the limit on, and reached exactly at it', () {
      const at = BudgetGauge(used: 100, limit: 100);
      expect(at.level, BudgetLevel.over);
      expect(at.reached, isTrue);
      expect(at.overBy, 0);
      const past = BudgetGauge(used: 125, limit: 100);
      expect(past.level, BudgetLevel.over);
      expect(past.reached, isFalse);
      expect(past.overBy, 25);
      expect(past.left, 0);
    });

    test('rounds the percent down so 99.6 never reads as 100', () {
      expect(const BudgetGauge(used: 996, limit: 1000).percent, 99);
    });

    test('follows the project warning share', () {
      expect(
        const BudgetGauge(used: 70, limit: 100, nearPercent: 70).level,
        BudgetLevel.near,
      );
    });

    test('is absent without a limit', () {
      expect(BudgetGauge.of(10, null), isNull);
      expect(BudgetGauge.of(10, 0), isNull);
      expect(BudgetGauge.of(null, 60)?.used, 0);
    });
  });

  test('a project reads its budget and its summed estimates', () {
    final usage = ProjectTimeUsage.fromJson(const {
      'projectId': 'p1',
      'budgetMinutes': 600,
      'usedMinutes': 480,
      'estimatedMinutes': 0,
      'nearPercent': 75,
    });
    expect(
      usage.budget,
      const BudgetGauge(used: 480, limit: 600, nearPercent: 75),
    );
    expect(usage.estimates, isNull);
  });

  test('an issue without an estimate has no gauge', () {
    final usage = IssueTimeUsage.fromJson(const {
      'issueId': 'i1',
      'projectId': 'p1',
      'estimateMinutes': null,
      'spentMinutes': 30,
    });
    expect(usage.estimate, isNull);
    expect(usage.nearPercent, BudgetGauge.defaultNearPercent);
  });
}
