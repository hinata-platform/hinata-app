import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/features/moderation/notice/appeal_sheet.dart';
import 'package:hinata/features/moderation/notice/notice_cubit.dart';

import '../../support/recording_fake.dart';
import 'moderation_test_support.dart';

/// An appeal against a decision (HIN-173): nothing goes out empty, a refusal
/// keeps what was written, and one that is in closes the sheet with thanks.
void main() {
  const appealed = Statement(
    caseId: 'k1',
    appeal: 'Dein Widerspruch liegt vor.',
  );
  late FakeModerationRepository moderation;

  setUp(() => moderation = FakeModerationRepository());

  Future<void> open(WidgetTester tester) async {
    final cubit = NoticeCubit(moderation, 'k1');
    addTearDown(cubit.close);
    await tester.pumpWidget(
      moderationApp(
        account: FakeAccountRepository(),
        textScale: 1,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppealSheet(context, cubit),
              child: const Text('appeal'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('appeal'));
    await tester.pumpAndSettle();
  }

  Iterable<Invocation> sent() =>
      moderation.calls.where((call) => call.memberName == #appeal);

  testWidgets('nothing goes out empty', (tester) async {
    await open(tester);

    await tester.tap(find.text('moderation.appeal.send'));
    await tester.pumpAndSettle();

    expect(sent(), isEmpty);
    expect(find.byType(AppealSheet), findsOneWidget);
  });

  testWidgets('a refusal stays in the sheet with the text kept', (
    tester,
  ) async {
    moderation.fail(#appeal, ApiFailure('error.moderation.appealClosed'));
    await open(tester);

    await tester.enterText(find.byType(TextField), 'Das war Satire.');
    await tester.pump();
    await tester.tap(find.text('moderation.appeal.send'));
    await tester.pumpAndSettle();

    expect(find.text('error.moderation.appealClosed'), findsOneWidget);
    expect(find.text('Das war Satire.'), findsOneWidget);
    expect(find.byType(AppealSheet), findsOneWidget);
  });

  testWidgets('an appeal that is in closes the sheet with thanks', (
    tester,
  ) async {
    moderation.answer<Statement>(#appeal, appealed);
    await open(tester);

    await tester.enterText(find.byType(TextField), '  Das war Satire.  ');
    await tester.pump();
    await tester.tap(find.text('moderation.appeal.send'));
    await tester.pumpAndSettle();

    expect(sent().single.positionalArguments, ['k1', 'Das war Satire.']);
    expect(find.byType(AppealSheet), findsNothing);
    expect(find.text('moderation.appeal.sent'), findsOneWidget);
  });
}
