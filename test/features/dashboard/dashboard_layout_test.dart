import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/content_models.dart';
import 'package:hinata/core/responsive/golden_columns.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/dashboard/dashboard_columns.dart';
import 'package:hinata/features/dashboard/dashboard_screen.dart';

/// The dashboard on a wide window (HIN-110): the first view holds what the
/// job needs every time — the sprint, today's focus and the four key figures
/// in one row — and the panels below fill the width instead of running long.
///
/// Widget tests render i18n keys (and every glyph one em wide), so the labels
/// measured here are the keys and the widths are generous for it.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    required Size screen,
    double? width,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width ?? screen.width, child: child),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('key figures', () {
    const kpis = DashboardKpis(
      today: 7,
      completion: ProjectCompletion(
        done: 21,
        inProgress: 14,
        backlog: 23,
        total: 58,
      ),
    );
    const labels = [
      'dashboard.kpiToday',
      'dashboard.inProgress',
      'dashboard.backlog',
      'dashboard.done',
    ];
    List<double> tops(WidgetTester tester) => [
      for (final label in labels) tester.getTopLeft(find.text(label)).dy,
    ];

    testWidgets('on a wide page the four tiles share one row', (tester) async {
      await pump(tester, kpis, screen: const Size(1800, 900), width: 1500);

      expect(tops(tester).toSet(), hasLength(1));
      // Nothing is cut: every label stands on one line in full.
      for (final label in labels) {
        expect(tester.getSize(find.text(label)).height, lessThan(20));
      }
    });

    testWidgets('where a row would squeeze the labels it stays two by two', (
      tester,
    ) async {
      await pump(tester, kpis, screen: const Size(1024, 900), width: 680);

      final [today, progress, backlog, done] = tops(tester);
      expect(progress, today);
      expect(done, backlog);
      expect(backlog, greaterThan(today));
    });

    testWidgets('a large text size is room the row no longer has', (
      tester,
    ) async {
      await pump(
        tester,
        kpis,
        screen: const Size(1800, 900),
        width: 1500,
        textScale: 2,
      );

      expect(tops(tester).toSet(), hasLength(2));
    });

    testWidgets('a phone keeps the two by two grid', (tester) async {
      await pump(tester, kpis, screen: const Size(390, 844));

      expect(tops(tester).toSet(), hasLength(2));
    });
  });

  group('focus time', () {
    final week = [
      for (var day = 1; day <= 7; day++)
        TrackerDay(date: DateTime(2026, 10, day), focusMinutes: 0),
    ];

    testWidgets('with nothing tracked it is its title and one sentence', (
      tester,
    ) async {
      await pump(
        tester,
        DashboardTrackerCard(week: week, month: const []),
        screen: const Size(1440, 900),
        width: 900,
      );

      expect(find.text('dashboard.focusTime'), findsOneWidget);
      expect(find.text('dashboard.focusTimeNone'), findsOneWidget);
      // No chart of zeros: no day labels, no total, no range switch.
      expect(find.text('Thu'), findsNothing);
      expect(find.text('dashboard.hours'), findsNothing);
      expect(find.text('dashboard.week'), findsNothing);
      expect(
        tester.getSize(find.byType(DashboardTrackerCard)).height,
        lessThan(120),
      );
    });

    testWidgets('an empty week keeps the switch for a month that has some', (
      tester,
    ) async {
      await pump(
        tester,
        DashboardTrackerCard(
          week: week,
          month: const [TrackerWeek(week: 39, focusMinutes: 90)],
        ),
        screen: const Size(1440, 900),
        width: 900,
      );

      expect(find.text('dashboard.focusTimeNone'), findsOneWidget);
      expect(find.text('Thu'), findsNothing);

      await tester.tap(find.text('dashboard.month'));
      await tester.pumpAndSettle();

      expect(find.text('dashboard.focusTimeNone'), findsNothing);
      expect(find.text('dashboard.weekLabel'), findsOneWidget);
    });

    testWidgets('with focus time it draws the week', (tester) async {
      await pump(
        tester,
        DashboardTrackerCard(
          week: [
            ...week.take(6),
            TrackerDay(date: DateTime(2026, 10, 7), focusMinutes: 45),
          ],
          month: const [],
        ),
        screen: const Size(1440, 900),
        width: 900,
      );

      expect(find.text('dashboard.focusTimeNone'), findsNothing);
      expect(find.text('Thu'), findsOneWidget);
    });
  });

  group('panel columns', () {
    const all = {
      DashboardCard.hero,
      DashboardCard.kpis,
      DashboardCard.focus,
      DashboardCard.away,
      DashboardCard.completion,
      DashboardCard.tracker,
      DashboardCard.git,
      DashboardCard.ranking,
    };
    Widget columns(Set<String> shown) => DashboardColumns(
      shown: shown,
      card: (key) => SizedBox(key: ValueKey(key), height: 120),
    );
    Set<double> lefts(WidgetTester tester, Set<String> shown) => {
      for (final key in shown.difference({DashboardCard.kpis}))
        tester.getTopLeft(find.byKey(ValueKey(key))).dx,
    };

    testWidgets('a very wide page deals the panels into three columns', (
      tester,
    ) async {
      await pump(tester, columns(all), screen: const Size(1920, 1080));

      expect(lefts(tester, all), hasLength(3));
      // The key figures span the columns, above them.
      final kpis = find.byKey(const ValueKey(DashboardCard.kpis));
      expect(tester.getSize(kpis).width, 1920);
      expect(
        tester.getTopLeft(kpis).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('hero'))).dy),
      );
    });

    testWidgets('below that two columns', (tester) async {
      await pump(tester, columns(all), screen: const Size(1440, 900));

      expect(lefts(tester, all), hasLength(2));
    });

    testWidgets('one column in the phone order once two would squeeze', (
      tester,
    ) async {
      await pump(tester, columns(all), screen: const Size(800, 900));

      expect(lefts(tester, all), hasLength(1));
      final order = [
        for (final key in dashboardStackOrder)
          tester.getTopLeft(find.byKey(ValueKey(key))).dy,
      ];
      expect(order, [...order]..sort());
    });

    testWidgets('a card the reader hid is not dealt at all', (tester) async {
      final shown = all.difference({DashboardCard.git, DashboardCard.kpis});
      await pump(tester, columns(shown), screen: const Size(1920, 1080));

      expect(find.byKey(const ValueKey(DashboardCard.git)), findsNothing);
      expect(find.byKey(const ValueKey(DashboardCard.kpis)), findsNothing);
      expect(find.byKey(const ValueKey(DashboardCard.hero)), findsOneWidget);
    });

    test('the column count follows the content width', () {
      expect(dashboardColumnCount(680), 1);
      expect(dashboardColumnCount(1100), 2);
      expect(dashboardColumnCount(kDashboardThreeColumns - 1), 2);
      expect(dashboardColumnCount(kDashboardThreeColumns), 3);
    });

    test(
      'today\'s focus opens the column beside the hero, whatever is shown',
      () {
        const optional = [
          DashboardCard.away,
          DashboardCard.completion,
          DashboardCard.tracker,
          DashboardCard.git,
          DashboardCard.ranking,
        ];
        for (var mask = 0; mask < 1 << optional.length; mask++) {
          final shown = {
            DashboardCard.hero,
            DashboardCard.focus,
            for (final (i, key) in optional.indexed)
              if (mask & (1 << i) != 0) key,
          };
          for (final count in [2, 3]) {
            final arrangement = arrangeBalanced(
              dashboardPanelGroups(shown.contains),
              count,
            );
            expect(arrangement.columns.first.first, DashboardCard.hero);
            expect(
              arrangement.columns[1].first,
              DashboardCard.focus,
              reason: '$shown in $count columns',
            );
          }
        }
      },
    );
  });
}
