import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/lexical/hinata_markdown_preview.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/features/moderation/house_rules_sheet.dart';

import '../../support/recording_fake.dart';
import 'moderation_test_support.dart';

/// The house rules opened from where none are loaded (HIN-176): a refused text
/// pointing at the rules it broke, a notice. The sheet reads them itself, and
/// says so when that fails.
void main() {
  final rules = HouseRules(
    version: 3,
    markdown: 'Seid freundlich zueinander.',
    createdAt: DateTime.utc(2026, 10, 2),
  );

  Future<FakeAccountRepository> open(
    WidgetTester tester,
    FakeAccountRepository account,
  ) async {
    await tester.pumpWidget(
      moderationApp(
        account: account,
        textScale: 1,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showHouseRulesSheet(context),
              child: const Text('rules'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('rules'));
    await tester.pumpAndSettle();
    return account;
  }

  testWidgets('reads the rules and shows them', (tester) async {
    await open(
      tester,
      FakeAccountRepository()..answer<HouseRules>(#houseRules, rules),
    );

    expect(find.byType(HinataMarkdownPreview), findsOneWidget);
    expect(find.text('moderation.rules.versionSince'), findsOneWidget);
  });

  testWidgets('a failed read says why and reads again', (tester) async {
    final account = FakeAccountRepository()
      ..fail(#houseRules, ApiFailure('errors.network'));
    await open(tester, account);

    expect(find.text('errors.network'), findsOneWidget);

    account.answer<HouseRules>(#houseRules, rules);
    await tester.tap(find.text('common.retry'));
    await tester.pumpAndSettle();

    expect(find.byType(HinataMarkdownPreview), findsOneWidget);
    expect(find.text('moderation.rules.versionSince'), findsOneWidget);
  });
}
