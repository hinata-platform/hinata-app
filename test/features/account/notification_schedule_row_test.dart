import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/widgets/glass_switch_chip.dart';
import 'package:hinata/features/account/notification_schedule_row.dart';

/// HIN-131: always, or chosen days between two times, with the organisation's
/// day count as the default.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  NotifPrefs prefs({
    NotifSchedule? schedule,
    List<int>? weekdays,
    String? from,
    String? until,
    NotifSchedule? defaultSchedule = NotifSchedule.always,
    String? defaultFrom,
    String? defaultUntil,
  }) => NotifPrefs(
    emailEnabled: true,
    pushEnabled: true,
    events: const {},
    schedule: schedule,
    weekdays: weekdays,
    from: from,
    until: until,
    defaultSchedule: defaultSchedule,
    defaultFrom: defaultFrom,
    defaultUntil: defaultUntil,
  );

  Future<List<NotifPrefs>> pump(
    WidgetTester tester,
    NotifPrefs value, {
    bool reduceMotion = false,
  }) async {
    tester.view
      ..physicalSize = const Size(800, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final emitted = <NotifPrefs>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: NotificationScheduleRow(
              prefs: value,
              onChanged: emitted.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return emitted;
  }

  const days = 'Montag';

  /// Taps a switch chip through its callback: the test font draws the keys so
  /// wide that the chip's own hit box lands outside the bar.
  void choose(WidgetTester tester, String key) {
    final chip = tester.widget<GlassSwitchChip>(
      find.ancestor(of: find.text(key), matching: find.byType(GlassSwitchChip)),
    );
    chip.onTap!();
  }

  testWidgets('always shows no days and says it is the default', (
    tester,
  ) async {
    await pump(tester, prefs());
    expect(find.bySemanticsLabel(days), findsNothing);
    expect(
      find.text('account.notifications.schedule.defaultAlways'),
      findsOneWidget,
    );
    expect(
      find.text('account.notifications.schedule.useDefault'),
      findsNothing,
    );
  });

  testWidgets('a first switch to custom starts at office hours', (
    tester,
  ) async {
    final emitted = await pump(tester, prefs());
    choose(tester, 'account.notifications.schedule.custom');
    final chosen = emitted.single;
    expect(chosen.schedule, NotifSchedule.custom);
    expect(chosen.weekdays, [1, 2, 3, 4, 5]);
    expect(chosen.from, '09:00');
    expect(chosen.until, '17:00');
  });

  testWidgets('custom fades the week and the window in', (tester) async {
    await pump(
      tester,
      prefs(
        schedule: NotifSchedule.custom,
        weekdays: const [1, 2, 3],
        from: '08:30',
        until: '16:00',
      ),
    );
    expect(find.bySemanticsLabel(days), findsOneWidget);
    expect(find.text('08:30'), findsOneWidget);
    expect(find.text('16:00'), findsOneWidget);
    expect(find.byType(FadeTransition), findsWidgets);
  });

  testWidgets('an organisation in working days defaults to office hours', (
    tester,
  ) async {
    await pump(
      tester,
      prefs(
        defaultSchedule: NotifSchedule.custom,
        defaultFrom: '09:00',
        defaultUntil: '17:00',
      ),
    );
    // Following the default, the custom controls already show.
    expect(find.bySemanticsLabel(days), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);
    expect(
      find.text('account.notifications.schedule.defaultCustom'),
      findsOneWidget,
    );
  });

  testWidgets('days picked before schedules read as the whole day', (
    tester,
  ) async {
    await pump(tester, prefs(weekdays: const [6, 7]));
    expect(find.bySemanticsLabel(days), findsOneWidget);
    expect(
      find.text('account.notifications.schedule.allDay'),
      findsNWidgets(2),
    );
  });

  testWidgets('a night window says where it belongs', (tester) async {
    await pump(
      tester,
      prefs(
        schedule: NotifSchedule.custom,
        weekdays: const [5],
        from: '22:00',
        until: '06:00',
      ),
    );
    expect(
      find.text('account.notifications.schedule.overnight'),
      findsOneWidget,
    );
  });

  testWidgets('switching back to always keeps the rest', (tester) async {
    final emitted = await pump(
      tester,
      prefs(schedule: NotifSchedule.custom, weekdays: const [1]),
    );
    choose(tester, 'account.notifications.schedule.always');
    expect(emitted.single.schedule, NotifSchedule.always);
    expect(emitted.single.weekdays, [1]);
  });

  testWidgets('use default clears every choice', (tester) async {
    final emitted = await pump(
      tester,
      prefs(
        schedule: NotifSchedule.custom,
        weekdays: const [1],
        from: '10:00',
        until: '12:00',
      ),
    );
    await tester.tap(find.text('account.notifications.schedule.useDefault'));
    final back = emitted.single;
    expect(back.followsDefault, isTrue);
    expect(back.from, isNull);
    expect(back.until, isNull);
  });

  testWidgets('without motion the block appears at once', (tester) async {
    await pump(
      tester,
      prefs(schedule: NotifSchedule.custom, weekdays: const [1]),
      reduceMotion: true,
    );
    expect(find.bySemanticsLabel(days), findsOneWidget);
  });

  test('the wire carries the schedule and the window', () {
    final json = prefs(
      schedule: NotifSchedule.custom,
      weekdays: const [1, 5],
      from: '09:00',
      until: '17:00',
    ).toJson();
    expect(json['schedule'], 'CUSTOM');
    expect(json['weekdays'], ['MONDAY', 'FRIDAY']);
    expect(json['from'], '09:00');
    expect(json.containsKey('defaultSchedule'), isFalse);

    final read = NotifPrefs.fromJson(const {
      'schedule': 'ALWAYS',
      'defaultSchedule': 'CUSTOM',
      'defaultFrom': '09:00',
      'defaultUntil': '17:00',
    });
    expect(read.effectiveSchedule, NotifSchedule.always);
    expect(read.defaultFrom, '09:00');
  });
}
