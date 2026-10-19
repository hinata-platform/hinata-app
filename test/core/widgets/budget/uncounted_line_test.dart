import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/budget/uncounted_line.dart';

/// HIN-158: a money budget at zero beside hours that clearly moved has to say
/// why, and has to say nothing when every hour counts.
void main() {
  Future<void> pump(WidgetTester tester, int unbilled, int unrated) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UncountedLine(
              unbilledMinutes: unbilled,
              unratedMinutes: unrated,
            ),
          ),
        ),
      );

  testWidgets('names each reason that applies', (tester) async {
    await pump(tester, 60, 30);
    expect(find.text('budget.money.unbilled'), findsOneWidget);
    expect(find.text('budget.money.unrated'), findsOneWidget);
  });

  testWidgets('says only the reason there is', (tester) async {
    await pump(tester, 60, 0);
    expect(find.text('budget.money.unbilled'), findsOneWidget);
    expect(find.text('budget.money.unrated'), findsNothing);
  });

  testWidgets('is silent when every hour counts', (tester) async {
    await pump(tester, 0, 0);
    expect(find.byType(Text), findsNothing);
  });
}
