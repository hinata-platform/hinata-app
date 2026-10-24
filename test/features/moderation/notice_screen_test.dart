import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/core/repositories/moderation_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/moderation/notice/notice_screen.dart';

import '../../support/recording_fake.dart';

/// The notice page (HIN-173): every statement DSA Art. 17(3) asks for, the
/// way to appeal while it is open, and what stands there once it is gone.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  const statement = Statement(
    caseId: 'k1',
    headline: 'Eine Entscheidung der Moderation zu deinem Inhalt',
    measure: 'Dein Kommentar vom 21. Okt. in MESSE-14 wurde entfernt.',
    scope: RemovalScope.whole,
    basis: 'Meldungen von Mitgliedern.',
    facts: 'Der Kommentar wertet eine Kollegin ab.',
    automation: 'Eine Person hat geprüft und entschieden.',
    groundText: 'Hausregel 2: Niemanden herabsetzen',
    rulesUrl: '/api/v1/public/rules?version=2',
    appealable: true,
    appeal: 'Du kannst bis zum 23. April 2027 widersprechen.',
    courtsNote: 'Der Weg zu den Gerichten steht dir offen.',
    messageToAuthor: 'Bitte bleib sachlich.',
  );

  late FakeModerationRepository moderation;

  setUp(
    () => moderation = FakeModerationRepository()
      ..answerWith(
        #page,
        (call) =>
            Uri.parse('https://server.test${call.positionalArguments[0]}'),
      ),
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepositoryProvider<ModerationRepository>.value(
        value: moderation,
        child: MaterialApp(
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: app!,
          ),
          home: const Scaffold(body: NoticeScreen(caseId: 'k1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every statement, the rules and the appeal, at twice the '
      'text size on a phone', (tester) async {
    moderation.answer<Statement>(#notice, statement);
    await pump(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(statement.headline), findsOneWidget);
    for (final label in const [
      'moderation.statement.measure',
      'moderation.statement.basis',
      'moderation.statement.rule',
      'moderation.statement.automation',
      'moderation.statement.message',
      'moderation.statement.remedies',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.ensureVisible(find.text('moderation.notice.appeal'));
    expect(find.text('moderation.notice.rules'), findsOneWidget);
    expect(find.text('moderation.notice.appeal'), findsOneWidget);
  });

  testWidgets('past the deadline there is no appeal to offer', (tester) async {
    moderation.answer<Statement>(
      #notice,
      const Statement(
        caseId: 'k1',
        headline: 'Eine Entscheidung der Moderation zu deinem Inhalt',
        measure: 'Dein Kommentar wurde entfernt.',
        scope: RemovalScope.whole,
      ),
    );
    await pump(tester);
    expect(find.text('moderation.notice.appeal'), findsNothing);
  });

  testWidgets('a notice that is gone says so, with the way to the rules', (
    tester,
  ) async {
    moderation.fail(#notice, ApiFailure('Nicht gefunden', statusCode: 404));
    await pump(tester);
    expect(find.text('moderation.notice.goneTitle'), findsOneWidget);
    expect(find.text('moderation.notice.rules'), findsOneWidget);
  });

  test('the path of a notice is safe for any case id', () {
    expect(noticeLocation('6718a/b'), '/notices/6718a%2Fb');
  });
}
