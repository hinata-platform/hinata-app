import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/features/account/account_cubit.dart';
import 'package:hinata/features/account/account_modals.dart';

import '../../support/recording_fake.dart';
import '../../support/tint_fakes.dart';

/// The profile when the text check refuses a name (HIN-176): the fields keep
/// what was typed and the modal says why, on a phone at twice the text size.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  Future<void> open(
    WidgetTester tester,
    AccountCubit cubit, {
    required Size screen,
    required double textScale,
  }) async {
    tester.view
      ..physicalSize = screen
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showEditProfile(
                  context,
                  cubit,
                  FakeTintAccountRepository.me(TintPreferences.standard),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a refused name stays in its field, with the reason beside it', (
    tester,
  ) async {
    final account = FakeAccountRepository()
      ..fail(
        #updateMyProfile,
        ApiFailure(
          'Not allowed here',
          statusCode: 422,
          details: const {'code': 'moderation.refused', 'terms': 'Spoiler'},
        ),
      );
    final cubit = AccountCubit(account);
    addTearDown(cubit.close);
    await open(tester, cubit, screen: const Size(390, 844), textScale: 2);

    await tester.enterText(find.widgetWithText(TextField, 'Me'), 'Kim Spoiler');
    await tester.tap(find.text('account.editModal.save'));
    await tester.pumpAndSettle();

    expect(find.text('moderation.refused.title'), findsOneWidget);
    expect(find.text('Kim Spoiler'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel and save sit at the end of the footer', (tester) async {
    final cubit = AccountCubit(FakeAccountRepository());
    addTearDown(cubit.close);
    await open(tester, cubit, screen: const Size(1200, 900), textScale: 1);

    final save = tester.getRect(
      find.ancestor(
        of: find.text('account.editModal.save'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    final cancel = tester.getRect(
      find.ancestor(
        of: find.text('common.cancel'),
        matching: find.byType(TextButton),
      ),
    );
    // The nearest one: the footer's own, inside its padding.
    final footer = tester.getRect(
      find
          .ancestor(
            of: find.text('account.editModal.save'),
            matching: find.byType(SafeArea),
          )
          .first,
    );

    // Side by side where they fit, else one under the other; the test font
    // draws the raw keys wide enough for the second.
    expect(save.right, footer.right);
    expect(cancel.right, anyOf(footer.right, save.left - 8));
  });
}
