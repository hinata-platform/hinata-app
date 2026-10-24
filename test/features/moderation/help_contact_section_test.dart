import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/features/moderation/help_contact_section.dart';

import '../../support/recording_fake.dart';
import 'moderation_test_support.dart';

/// Settings › Help and contact (HIN-175): how to reach the instance's
/// moderation, its house rules with the person's own agreement, a report of
/// something without a menu of its own, the imprint, and the app's provider.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  const moderation = ModerationMeta(
    version: 1,
    contactEmail: 'moderation@werkhaus.example',
    imprintUrl: 'https://werkhaus.example/impressum',
  );

  final accepted = HouseRules(
    version: 3,
    markdown: '# Hausregeln',
    createdAt: DateTime.utc(2026, 10, 1),
    acceptedVersion: 3,
    acceptedAt: DateTime.utc(2026, 10, 2),
  );

  late FakeModerationRepository reports;

  Iterable<Invocation> sent() =>
      reports.calls.where((c) => c.memberName == #report);

  Future<FakeAccountRepository> pump(
    WidgetTester tester, {
    ModerationMeta meta = moderation,
    double textScale = 1.0,
  }) async {
    final account = FakeAccountRepository()
      ..answer<HouseRules>(#houseRules, accepted);
    reports = FakeModerationRepository()..answer<void>(#report, null);
    await tester.pumpWidget(
      moderationApp(
        account: account,
        moderationRepository: reports,
        moderation: meta,
        textScale: textScale,
        child: const Scaffold(
          body: SingleChildScrollView(child: HelpContactSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return account;
  }

  testWidgets('names the contact, the rules agreed to, reporting, the imprint '
      'and the app, at twice the text size on a phone', (tester) async {
    onPhone(tester);
    await pump(tester, textScale: 2.0);

    expect(find.text('moderation.help.moderation'), findsOneWidget);
    expect(find.text('moderation@werkhaus.example'), findsOneWidget);
    expect(find.text('moderation.rules.title'), findsOneWidget);
    expect(find.text('moderation.help.rulesAccepted'), findsOneWidget);
    expect(find.text('moderation.help.reportElsewhere'), findsOneWidget);
    expect(find.text('moderation.help.imprint'), findsOneWidget);
    expect(find.text('moderation.help.aboutApp'), findsOneWidget);
  });

  testWidgets('a server without moderation leaves only the app', (
    tester,
  ) async {
    final account = await pump(tester, meta: const ModerationMeta());

    expect(find.text('moderation.help.aboutApp'), findsOneWidget);
    expect(find.text('moderation.help.reportElsewhere'), findsNothing);
    expect(find.text('moderation.rules.title'), findsNothing);
    expect(account.calls, isEmpty);
  });

  testWidgets('about the app names its provider, its terms, its privacy '
      'policy and its imprint (HIN-178)', (tester) async {
    await pump(tester);

    await tester.tap(find.text('moderation.help.aboutApp'));
    await tester.pumpAndSettle();

    expect(find.text('moderation.help.provider'), findsOneWidget);
    expect(find.text('auth.termsOfService'), findsOneWidget);
    expect(find.text('auth.privacyPolicy'), findsOneWidget);
    expect(find.text('moderation.help.appImprint'), findsOneWidget);
  });

  testWidgets('reporting something else asks why, then where, and sends it '
      'as a report of kind other', (tester) async {
    await pump(tester);

    await tester.tap(find.text('moderation.help.reportElsewhere'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('moderation.category.spam'));
    await tester.tap(find.text('moderation.category.spam'));
    await tester.pumpAndSettle();

    // Where it is cannot be left out.
    await tester.ensureVisible(find.text('moderation.report.send'));
    await tester.tap(find.text('moderation.report.send'));
    await tester.pumpAndSettle();
    expect(find.text('moderation.report.locationRequired'), findsOneWidget);
    expect(sent(), isEmpty);

    await tester.enterText(
      find.byType(TextField).first,
      '  Board "Messe 2026"  ',
    );
    await tester.ensureVisible(find.text('moderation.report.send'));
    await tester.tap(find.text('moderation.report.send'));
    await tester.pumpAndSettle();

    final call = sent().single;
    expect(call.positionalArguments, [
      TargetRef.elsewhere,
      ReportCategory.spam,
    ]);
    expect(call.namedArguments[#location], 'Board "Messe 2026"');
    expect(call.namedArguments[#explanation], isNull);
    expect(find.text('moderation.report.thanks'), findsOneWidget);
  });

  testWidgets('a reason that needs explaining is not sent without one', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('moderation.help.reportElsewhere'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('moderation.category.other'));
    await tester.tap(find.text('moderation.category.other'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Team Aufbau');
    await tester.enterText(find.byType(TextField).last, 'kurz');
    await tester.ensureVisible(find.text('moderation.report.send'));
    await tester.tap(find.text('moderation.report.send'));
    await tester.pumpAndSettle();

    expect(find.text('moderation.report.explanationTooShort'), findsOneWidget);
    expect(sent(), isEmpty);
  });
}
