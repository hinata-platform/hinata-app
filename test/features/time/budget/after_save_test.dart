import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/models/time_usage_models.dart';
import 'package:hinata/features/time/budget/after_save.dart';

void main() {
  // Widget tests render i18n keys, which is what is asserted: the sentence
  // chosen, not its wording.
  Future<String?> lineFor(
    WidgetTester tester,
    List<BudgetWarning> warnings,
  ) async {
    String? line;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            line = budgetLine(context, warnings);
            return const SizedBox();
          },
        ),
      ),
    );
    return line;
  }

  testWidgets('a limit passed comes before one that is only near', (
    tester,
  ) async {
    final line = await lineFor(tester, const [
      BudgetWarning(
        kind: 'ESTIMATE',
        over: false,
        used: 95,
        limit: 100,
        percent: 95,
      ),
      BudgetWarning(
        kind: 'BUDGET',
        over: true,
        used: 130,
        limit: 120,
        percent: 109,
      ),
    ]);
    expect(line, 'budget.toast.over.BUDGET');
  });

  testWidgets('exactly at the limit is said as used up', (tester) async {
    final line = await lineFor(tester, const [
      BudgetWarning(
        kind: 'ESTIMATE',
        over: true,
        used: 60,
        limit: 60,
        percent: 100,
      ),
    ]);
    expect(line, 'budget.toast.reached.ESTIMATE');
  });

  testWidgets('no warning, no sentence', (tester) async {
    expect(await lineFor(tester, const []), isNull);
  });

  test('a saved entry reads the warnings it came with', () {
    final saved = SavedTimeEntry.fromJson(const {
      'entry': {
        'id': 'w1',
        'userId': 'u1',
        'durationMinutes': 30,
        'date': '2026-10-17',
      },
      'overlaps': <String>[],
      'budgetWarnings': [
        {
          'kind': 'BUDGET',
          'level': 'NEAR',
          'subjectId': 'p1',
          'used': 90,
          'limit': 100,
          'percent': 90,
        },
      ],
    });
    expect(saved.budgetWarnings.single.over, isFalse);
    expect(saved.budgetWarnings.single.percent, 90);
  });

  test('the modes travel, and only an explicit OPEN stops the note', () {
    final settings = ProjectTimeSettings.fromJson(const {
      'budgetLimitMode': 'OPEN',
    });
    expect(settings.toJson()['budgetLimitMode'], 'OPEN');
    expect(settings.toJson().containsKey('estimateLimitMode'), isFalse);
    final usage = ProjectTimeUsage.fromJson(const {
      'projectId': 'p',
      'budgetLimitMode': 'OPEN',
    });
    expect(usage.budgetWarns, isFalse);
    expect(usage.estimateWarns, isTrue);
  });
}
