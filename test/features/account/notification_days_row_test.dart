import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/account/notification_days_row.dart';

/// HIN-129: the days e-mail and push may arrive on, in the reader's week.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  Future<List<List<int>?>> pump(
    WidgetTester tester, {
    List<int>? weekdays,
    List<int> defaults = const [1, 2, 3, 4, 5],
    Locale locale = const Locale('de'),
    double width = 800,
    double textScale = 1,
  }) async {
    tester.view
      ..physicalSize = Size(width, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final emitted = <List<int>?>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('de'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: NotificationDaysRow(
              weekdays: weekdays,
              defaultWeekdays: defaults,
              onChanged: emitted.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return emitted;
  }

  /// The day toggles' accessible names, in on-screen order.
  List<String> dayOrder(WidgetTester tester) => [
    for (final s in tester.widgetList<Semantics>(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.selected != null,
      ),
    ))
      s.properties.label!,
  ];

  group('order', () {
    test('a week read from Sunday or from Monday', () {
      expect(orderedWeekdays(0), [7, 1, 2, 3, 4, 5, 6]);
      expect(orderedWeekdays(1), [1, 2, 3, 4, 5, 6, 7]);
      expect(orderedWeekdays(6), [6, 7, 1, 2, 3, 4, 5]);
    });

    testWidgets('German weeks start on Monday', (tester) async {
      await pump(tester);
      expect(dayOrder(tester).first, 'Montag');
      expect(dayOrder(tester).last, 'Sonntag');
    });

    testWidgets('American weeks start on Sunday', (tester) async {
      await pump(tester, locale: const Locale('en', 'US'));
      expect(dayOrder(tester).first, 'Sunday');
      expect(dayOrder(tester).last, 'Saturday');
    });
  });

  group('default', () {
    testWidgets('shows the default days and no way back to it', (tester) async {
      await pump(tester);
      expect(
        find.text('account.notifications.days.defaultLine'),
        findsOneWidget,
      );
      expect(find.text('account.notifications.days.useDefault'), findsNothing);
    });

    test('an unbroken run reads as a range, gaps as a list', () {
      String short(int d) =>
          const ['', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'][d];
      String range(String a, String b) => '$a bis $b';

      expect(
        formatDaySpan([1, 2, 3, 4, 5], orderedWeekdays(1), short, range),
        'Mo bis Fr',
      );
      // Sunday to Thursday, read in a week that starts on Saturday.
      expect(
        formatDaySpan([7, 1, 2, 3, 4], orderedWeekdays(6), short, range),
        'So bis Do',
      );
      expect(
        formatDaySpan([1, 3, 5], orderedWeekdays(1), short, range),
        'Mo, Mi, Fr',
      );
    });

    testWidgets('custom days offer the way back to the default', (
      tester,
    ) async {
      final emitted = await pump(tester, weekdays: const [1, 3]);
      await tester.tap(find.text('account.notifications.days.useDefault'));
      expect(emitted.single, isNull);
    });
  });

  group('toggling', () {
    testWidgets('adding Saturday emits the new set, sorted', (tester) async {
      final emitted = await pump(tester);
      await tester.tap(find.bySemanticsLabel('Samstag'));
      expect(emitted.single, [1, 2, 3, 4, 5, 6]);
    });

    testWidgets('removing a day emits the rest', (tester) async {
      final emitted = await pump(tester, weekdays: const [1, 2, 3]);
      await tester.tap(find.bySemanticsLabel('Dienstag'));
      expect(emitted.single, [1, 3]);
    });

    testWidgets('the last day cannot be removed', (tester) async {
      final emitted = await pump(tester, weekdays: const [3]);
      await tester.tap(find.bySemanticsLabel('Mittwoch'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(emitted, isEmpty);
      // The reason shows instead.
      expect(find.text('account.notifications.days.lastDay'), findsOneWidget);
      // And a screen reader hears it, not only the eye.
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('account.notifications.days.lastDay'),
      );
      // Let the tooltip run out so no timer outlives the test.
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('size', () {
    Finder day(String name) => find.bySemanticsLabel(name);

    testWidgets('every day and the way back are at least 48 by 48', (
      tester,
    ) async {
      await pump(tester, weekdays: const [1, 3]);
      for (final name in ['Montag', 'Mittwoch', 'Sonntag']) {
        final size = tester.getSize(day(name));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      final back = tester.getSize(
        find.ancestor(
          of: find.text('account.notifications.days.useDefault'),
          matching: find.byType(TextButton),
        ),
      );
      expect(back.width, greaterThanOrEqualTo(48));
      expect(back.height, greaterThanOrEqualTo(48));
    });

    testWidgets('a phone keeps the week on one line', (tester) async {
      await pump(tester, width: 330);
      final monday = tester.getRect(day('Montag'));
      final sunday = tester.getRect(day('Sonntag'));
      expect(monday.width, greaterThanOrEqualTo(40));
      expect(sunday.top, monday.top);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the narrowest screen at double text keeps one line', (
      tester,
    ) async {
      await pump(tester, width: 280, textScale: 2);
      final monday = tester.getRect(day('Montag'));
      final sunday = tester.getRect(day('Sonntag'));
      expect(sunday.top, monday.top);
      expect(sunday.right, lessThanOrEqualTo(280));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the days grow with the text where there is room', (
      tester,
    ) async {
      await pump(tester, textScale: 2);
      final size = tester.getSize(day('Montag'));
      expect(size.width, greaterThanOrEqualTo(96));
      expect(tester.takeException(), isNull);
    });
  });
}
