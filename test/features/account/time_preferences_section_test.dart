import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/time_preferences_cubit.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/repositories/account_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/account/time_preferences_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Settings → Time tracking: six numbers and a switch, all of them the
/// person's own.
///
/// What is worth pinning is that a step writes, and that a refused save puts
/// the old value back rather than leaving a lie on screen — the panel shows the
/// new number at once, because a stepper that only moved after a round trip
/// would feel broken.
void main() {
  late _FakeAccountRepository account;
  late TimePreferencesCubit cubit;

  setUp(() {
    AppColors.brightness = Brightness.light;
    account = _FakeAccountRepository();
    cubit = TimePreferencesCubit(account);
  });

  tearDown(() => cubit.close());

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(1200, 900)),
      child: MaterialApp(
        home: Scaffold(
          body: BlocProvider<TimePreferencesCubit>.value(
            value: cubit,
            child: const SingleChildScrollView(child: TimePreferencesSection()),
          ),
        ),
      ),
    ),
  );

  testWidgets('a step moves the value and writes it', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    // The focus interval steps by five: the numbers people reach for are 20,
    // 25 and 30, not 24.
    await tester.tap(find.byIcon(LucideIcons.plus).first);
    await tester.pumpAndSettle();

    expect(cubit.state.pomodoroWork, 30);
    expect(account.saved!.pomodoroWork, 30);
  });

  testWidgets('a refused save puts the old value back', (tester) async {
    account.refuse = true;
    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.plus).first);
    await tester.pumpAndSettle();

    expect(cubit.state.pomodoroWork, 25);
  });

  testWidgets('the sound is a switch, and it is on by default', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('account.time.sound'), findsOneWidget);
    expect(cubit.state.sound, isTrue);
  });

  group('the cubit', () {
    test('a save that fails leaves the held value alone', () async {
      account.refuse = true;

      final ok = await cubit.save(const TimePreferences(pomodoroWork: 50));

      expect(ok, isFalse);
      expect(cubit.state.pomodoroWork, 25);
    });

    test('a read that fails leaves the defaults, which are usable', () async {
      account.refuseRead = true;

      await cubit.load();

      expect(cubit.state, const TimePreferences());
    });

    test('saving what is already held asks the server nothing', () async {
      final ok = await cubit.save(const TimePreferences());

      expect(ok, isTrue);
      expect(account.saved, isNull);
    });
  });
}

class _FakeAccountRepository implements AccountRepository {
  bool refuse = false;
  bool refuseRead = false;
  TimePreferences? saved;

  @override
  Future<Me> meAccount() async {
    if (refuseRead) throw ApiFailure('offline');
    return _me(const TimePreferences());
  }

  @override
  Future<Me> updateMyProfile({
    String? displayName,
    String? title,
    String? pronouns,
    String? locale,
    String? timezone,
    TimePreferences? timePreferences,
  }) async {
    if (refuse) throw ApiFailure('nope');
    saved = timePreferences;
    return _me(timePreferences ?? const TimePreferences());
  }

  Me _me(TimePreferences preferences) => Me(
    id: 'u1',
    displayName: 'Me',
    username: 'me',
    email: 'me@example.org',
    emailVerified: true,
    origin: AuthOrigin.local,
    roles: const ['MEMBER'],
    active: true,
    twoFactor: const TwoFactor(
      enabled: false,
      method: 'TOTP',
      recoveryRemaining: 0,
    ),
    notificationPreferences: NotifPrefs.fromJson(const {}),
    timePreferences: preferences,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
