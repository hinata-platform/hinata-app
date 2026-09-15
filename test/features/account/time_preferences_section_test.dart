import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/time_policy_cubit.dart';
import 'package:hinata/core/blocs/time_preferences_cubit.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/repositories/account_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/widgets/hive_widgets.dart' show HiveSwitch;
import 'package:hinata/features/account/time_preferences_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../time/fake_time_policy_cubit.dart';

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
  late FakeTimePolicyCubit policy;

  setUp(() {
    AppColors.brightness = Brightness.light;
    account = _FakeAccountRepository();
    cubit = TimePreferencesCubit(account);
    policy = FakeTimePolicyCubit(TimePolicySnapshot.none, _NoTimeRepository());
  });

  tearDown(() async {
    await cubit.close();
    await policy.close();
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(1200, 900)),
      child: MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<TimePreferencesCubit>.value(value: cubit),
              BlocProvider<TimePolicyCubit>.value(value: policy),
            ],
            child: const SingleChildScrollView(child: TimePreferencesSection()),
          ),
        ),
      ),
    ),
  );

  Finder switchOf(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
    matching: find.byType(HiveSwitch),
  );

  // The reminders sit below the pomodoro rows, past the bottom of the test
  // surface, so every tap scrolls its target into view first. A switch settles
  // sooner than the cubit collects a burst of taps, so the write is waited for.
  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  group('reminders (HIN-92)', () {
    testWidgets('are not offered while the operator has them off', (
      tester,
    ) async {
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('account.timeTracking.reminders'), findsNothing);
      expect(policy.loads, 1);
    });

    testWidgets('say that only the person is reminded, and start off', (
      tester,
    ) async {
      policy.emit(const TimePolicySnapshot(targetRemindersEnabled: true));
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('account.timeTracking.remindersHint'), findsOneWidget);
      expect(find.text('account.timeTracking.target'), findsNothing);
      expect(cubit.state.dailyTargetMinutes, isNull);
    });

    testWidgets('a target switched on starts at what the operator suggests', (
      tester,
    ) async {
      policy.emit(
        const TimePolicySnapshot(
          targetRemindersEnabled: true,
          suggestedDailyTargetMinutes: 450,
        ),
      );
      await pump(tester);
      await tester.pumpAndSettle();

      await tapVisible(tester, switchOf('account.timeTracking.dailyTarget'));

      expect(cubit.state.dailyTargetMinutes, 450);
      expect(account.saved!.toJson()['dailyTargetMinutes'], 450);
      expect(find.text('account.timeTracking.remindAt'), findsOneWidget);
      // The suggestion is what was taken, so there is nothing left to offer.
      expect(find.text('account.timeTracking.useSuggestion'), findsNothing);
    });

    testWidgets('a different target keeps the suggestion one tap away', (
      tester,
    ) async {
      policy.emit(
        const TimePolicySnapshot(
          targetRemindersEnabled: true,
          suggestedWeeklyTargetMinutes: 2400,
        ),
      );
      cubit.adopt(const TimePreferences(weeklyTargetMinutes: 1200));
      await pump(tester);
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('account.timeTracking.useSuggestion'));

      expect(cubit.state.weeklyTargetMinutes, 2400);
    });

    testWidgets('switching a target off removes it on the server', (
      tester,
    ) async {
      policy.emit(const TimePolicySnapshot(targetRemindersEnabled: true));
      cubit.adopt(const TimePreferences(dailyTargetMinutes: 480));
      await pump(tester);
      await tester.pumpAndSettle();

      await tapVisible(tester, switchOf('account.timeTracking.dailyTarget'));

      expect(cubit.state.dailyTargetMinutes, isNull);
      // Absent would keep the stored target; zero is how it is removed.
      expect(account.saved!.toJson()['dailyTargetMinutes'], 0);
    });
  });

  group('the preferences on the wire', () {
    test('read what the server sends, with its defaults', () {
      final prefs = TimePreferences.fromJson(const {
        'dailyTargetMinutes': 420,
        'weeklyReminderDay': 'MONDAY',
      });

      expect(prefs.dailyTargetMinutes, 420);
      expect(prefs.weeklyTargetMinutes, isNull);
      expect(prefs.weeklyReminderDay, DateTime.monday);
      expect(prefs.dailyReminderAt, 17 * 60);
      expect(prefs.toJson()['weeklyReminderDay'], 'MONDAY');
    });
  });

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

    expect(find.text('account.timeTracking.sound'), findsOneWidget);
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

class _NoTimeRepository implements TimeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
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
