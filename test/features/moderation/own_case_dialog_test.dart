import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/features/moderation/person/own_case_dialog.dart';

import '../../support/recording_fake.dart';
import 'moderation_test_support.dart';

/// Why moderation opens a case of its own on a person (HIN-174): the reason
/// picked from the list a report shows, and what was found.
void main() {
  Future<List<OwnCase?>> open(WidgetTester tester) async {
    final answers = <OwnCase?>[];
    await tester.pumpWidget(
      moderationApp(
        account: FakeAccountRepository(),
        textScale: 1,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  answers.add(await askOwnCase(context, 'Jonas')),
              child: const Text('suspend'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('suspend'));
    await tester.pumpAndSettle();
    return answers;
  }

  testWidgets(
    'the reason comes from the report list, and goes with the facts',
    (tester) async {
      final answers = await open(tester);

      await tester.tap(find.text('moderation.category.harassment'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('moderation.category.spam'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('moderation.category.spam'));
      await tester.pumpAndSettle();
      expect(find.text('moderation.category.spam'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        'Schickt seit Tagen dieselbe Werbung in jedes Projekt.',
      );
      await tester.pump();
      await tester.tap(find.text('moderation.suspension.ownNext'));
      await tester.pumpAndSettle();

      expect(answers, [
        (
          category: ReportCategory.spam,
          facts: 'Schickt seit Tagen dieselbe Werbung in jedes Projekt.',
        ),
      ]);
    },
  );

  testWidgets('too few words found go nowhere', (tester) async {
    final answers = await open(tester);

    await tester.enterText(find.byType(TextField), 'Werbung');
    await tester.pump();
    await tester.tap(find.text('moderation.suspension.ownNext'));
    await tester.pumpAndSettle();

    expect(answers, isEmpty);
  });
}
