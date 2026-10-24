import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/auth_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/auth/register_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recording_fake.dart';
import '../moderation/moderation_test_support.dart';

/// The registration when the text check refuses a name (HIN-176): the form
/// keeps everything typed and says why, with the way to the rules the
/// instance publishes, on a phone at twice the text size.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  testWidgets('a refused name keeps the form and leads to the rules', (
    tester,
  ) async {
    onPhone(tester);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // The server switcher on the page reads the stored servers: none here.
    final storage = AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    final auth = FakeAuthRepository()
      ..fail(
        #register,
        ApiFailure(
          'Not allowed here',
          statusCode: 422,
          details: const {
            'code': 'error.moderation.refused',
            'terms': 'Spoiler',
          },
        ),
      );
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AuthRepository>.value(value: auth),
          RepositoryProvider<AppStorage>.value(value: storage),
        ],
        child: moderationApp(
          account: FakeAccountRepository(),
          moderation: const ModerationMeta(
            version: 1,
            rulesUrl: 'https://track.example.org/api/v1/public/rules',
          ),
          child: const RegisterScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> type(String label, String text) async {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, text);
    }

    await type('register.displayName', 'Kim Spoiler');
    await type('register.email', 'kim@example.org');
    await type('register.username', 'kim');
    await type('register.password', 'ein langes Passwort');
    await type('register.confirmPassword', 'ein langes Passwort');
    final submit = find.text('register.submit');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('moderation.refused.title'), findsOneWidget);
    expect(find.text('moderation.refused.readRules'), findsOneWidget);
    expect(find.text('Kim Spoiler'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
