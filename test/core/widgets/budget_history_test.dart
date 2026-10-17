import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_usage_models.dart';
import 'package:hinata/core/widgets/budget/budget.dart';

void main() {
  test('the running total counts every day of the span, with gaps filled', () {
    final history = BudgetHistory.fromJson(const {
      'from': '2026-09-01',
      'to': '2026-09-04',
      'before': 100,
      'days': [
        {'date': '2026-09-01', 'minutes': 30},
        {'date': '2026-09-03', 'minutes': 60},
      ],
    });
    expect(history.cumulative.map((day) => day.total), [130, 130, 190, 190]);
  });

  test('a forecast says LOW unless the server says OK', () {
    expect(BudgetForecast.fromJson(const {}).lowConfidence, isTrue);
    final ok = BudgetForecast.fromJson(const {
      'confidence': 'OK',
      'leftMinutes': 600,
      'exhaustedOn': '2026-11-14',
    });
    expect(ok.exhaustedOn, DateTime(2026, 11, 14));
  });

  Future<String?> sentence(WidgetTester tester, BudgetForecast forecast) async {
    String? out;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            out = ForecastLine.sentence(context, forecast);
            return const SizedBox();
          },
        ),
      ),
    );
    return out;
  }

  testWidgets('the forecast line picks its sentence', (tester) async {
    expect(await sentence(tester, const BudgetForecast()), isNull);
    expect(
      await sentence(tester, const BudgetForecast(leftMinutes: 0)),
      'budget.forecast.spent',
    );
    expect(
      await sentence(tester, const BudgetForecast(leftMinutes: 60)),
      'budget.forecast.tooLittle',
    );
    expect(
      await sentence(
        tester,
        const BudgetForecast(leftMinutes: 60, lowConfidence: false),
      ),
      'budget.forecast.noPace',
    );
  });

  testWidgets('the burn-down draws with and past a budget', (tester) async {
    final history = BudgetHistory(
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 10),
      before: 0,
      days: [
        (date: DateTime(2026, 9, 2), minutes: 300),
        (date: DateTime(2026, 9, 8), minutes: 600),
      ],
    );
    for (final limit in [null, 1200, 600]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BurnDownChart(
              history: history,
              limitMinutes: limit,
              estimatedMinutes: 800,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
