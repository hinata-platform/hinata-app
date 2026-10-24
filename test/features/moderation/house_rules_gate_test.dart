import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/moderation/app_terms_screen.dart';
import 'package:hinata/features/moderation/house_rules_gate_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recording_fake.dart';
import 'moderation_test_support.dart';

/// The two agreements of HIN-175 as a person meets them on a phone with the
/// largest text: the app's terms before anything else, the instance's house
/// rules after signing in. Neither can be skipped, and neither is a dead end.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  HouseRules rules({int version = 3, int? accepted}) => HouseRules(
    version: version,
    markdown: '# Hausregeln\n\nSeid freundlich.',
    createdAt: DateTime.utc(2026, 10, 2),
    acceptedVersion: accepted,
  );

  group('the app terms', () {
    testWidgets('fit a phone at twice the text size, and agreeing is stored '
        'before the app moves on', (tester) async {
      onPhone(tester);
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final storage = AppStorage(
        await SharedPreferences.getInstance(),
        const FlutterSecureStorage(),
      );
      var done = 0;
      await tester.pumpWidget(
        moderationApp(
          account: FakeAccountRepository(),
          child: AppTermsScreen(storage: storage, onDone: () => done++),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('moderation.appTerms.body'), findsOneWidget);
      expect(find.text('moderation.appTerms.read'), findsOneWidget);
      final accept = find.text('moderation.appTerms.accept');
      await tester.ensureVisible(accept);
      await tester.tap(accept);
      await tester.pumpAndSettle();

      expect(storage.appTermsAccepted, isTrue);
      expect(done, 1);
    });
  });

  group('the house rules', () {
    testWidgets('sum the rules up on a phone at twice the text size, and '
        'agreeing accepts the version on screen and re-checks the session', (
      tester,
    ) async {
      onPhone(tester);
      final account = FakeAccountRepository()
        ..answer<HouseRules>(#houseRules, rules())
        ..answer<void>(#acceptHouseRules, null);
      final auth = RecordingAuth();
      await tester.pumpWidget(
        moderationApp(
          account: account,
          auth: auth,
          child: const HouseRulesGateScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('moderation.rules.gateTitle'), findsOneWidget);
      expect(find.text('moderation.rules.gateLead'), findsOneWidget);
      for (final line in ['respect', 'lawful', 'report', 'consequences']) {
        expect(find.text('moderation.rules.$line'), findsOneWidget);
      }
      final accept = find.text('moderation.rules.accept');
      await tester.ensureVisible(accept);
      await tester.tap(accept);
      // Not settled: the button turns into a spinner until the router leaves.
      await tester.pump();
      await tester.pump();

      expect(account.callTo(#acceptHouseRules).positionalArguments, [3]);
      expect(auth.events, [const AuthChecked()]);
      expect(find.text('moderation.rules.accept'), findsNothing);
    });

    testWidgets('a person who agreed to an earlier version is told they '
        'changed', (tester) async {
      onPhone(tester);
      final account = FakeAccountRepository()
        ..answer<HouseRules>(#houseRules, rules(accepted: 2));
      await tester.pumpWidget(
        moderationApp(account: account, child: const HouseRulesGateScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('moderation.rules.gateChanged'), findsOneWidget);
      expect(find.text('moderation.rules.gateLead'), findsNothing);
    });

    testWidgets('a newer version that arrived meanwhile is shown to be '
        'accepted on its own', (tester) async {
      onPhone(tester);
      var version = 3;
      final account = FakeAccountRepository()
        ..answerWith(#houseRules, (_) async => rules(version: version))
        ..answerWith(#acceptHouseRules, (_) async {
          version = 4;
          throw ApiFailure('error.rules.notCurrent', statusCode: 409);
        });
      final auth = RecordingAuth();
      await tester.pumpWidget(
        moderationApp(
          account: account,
          auth: auth,
          child: const HouseRulesGateScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final accept = find.text('moderation.rules.accept');
      await tester.ensureVisible(accept);
      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(auth.events, isEmpty);

      await tester.ensureVisible(accept);
      await tester.tap(accept);
      await tester.pumpAndSettle();
      final accepted = account.calls
          .where((call) => call.memberName == #acceptHouseRules)
          .map((call) => call.positionalArguments.single);
      expect(accepted, [3, 4]);
    });

    testWidgets('rules that cannot be read still leave trying again and '
        'signing out', (tester) async {
      onPhone(tester);
      final account = FakeAccountRepository()
        ..fail(#houseRules, ApiFailure('errors.connection'));
      final auth = RecordingAuth();
      await tester.pumpWidget(
        moderationApp(
          account: account,
          auth: auth,
          child: const HouseRulesGateScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('moderation.rules.loadFailed'), findsOneWidget);
      expect(find.text('common.retry'), findsOneWidget);
      final signOut = find.text('account.signOut');
      await tester.ensureVisible(signOut);
      await tester.tap(signOut);
      expect(auth.events, [const LogoutRequested()]);
    });
  });
}
