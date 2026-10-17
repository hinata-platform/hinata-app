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

  test('money is a gauge only for a reader the server gave it to', () {
    final lead = ProjectTimeUsage.fromJson(const {
      'projectId': 'p',
      'budgetCents': 600000,
      'usedCents': 480000,
      'currency': 'EUR',
      'budgetRateKind': 'BILLABLE',
    });
    expect(lead.money?.percent, 80);
    expect(lead.costBudget, isFalse);
    final member = ProjectTimeUsage.fromJson(const {'projectId': 'p'});
    expect(member.money, isNull);
  });

  test('a report page reads its ranked budgets, forecasts and sprints', () {
    final page = BudgetReportPage.fromJson(const {
      'items': [
        {'projectId': 'p1', 'budgetMinutes': 600, 'usedMinutes': 540},
      ],
      'names': {'p1': 'Hinata'},
      'total': 7,
      'forecasts': {
        'p1': {'dailyMinutes': 30, 'dataDays': 5, 'confidence': 'OK'},
      },
      'sprints': [
        {
          'sprintId': 's1',
          'name': 'Sprint 1',
          'boardName': 'Board',
          'budgetMinutes': 120,
          'usedMinutes': 60,
          'nearPercent': 80,
        },
      ],
    });

    expect(page.budgets.total, 7);
    expect(page.budgets.names['p1'], 'Hinata');
    expect(page.budgets.forecasts['p1']?.lowConfidence, isFalse);
    expect(page.sprints.single.board, 'Board');
    expect(page.sprints.single.gauge?.percent, 50);
  });

  test('a server that sends no forecasts leaves none', () {
    expect(TopBudgets.fromJson(const {'items': []}).forecasts, isEmpty);
  });
}
