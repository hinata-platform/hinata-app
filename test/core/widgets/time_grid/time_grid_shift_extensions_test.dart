import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/widgets/time_grid/time_day_dots.dart';
import 'package:hinata/core/widgets/time_grid/time_grid.dart';
import 'package:hinata/core/widgets/time_grid/time_grid_geometry.dart';
import 'package:hinata/core/widgets/time_grid/time_grid_model.dart';
import 'package:hinata/core/widgets/time_grid/time_month_grid.dart';
import 'package:hinata/core/widgets/time_grid/time_week_strip.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The three things shift planning needed from the shared calendar surface
/// (HIN-160): a glyph on a block, a month that only marks its days, and the
/// week strip as a widget of its own with two marks a day. The time calendar
/// uses none of them, so each is checked to be off by default too.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  final monday = DateTime(2026, 10, 19);

  Widget grid(List<TimeGridLayer> layers) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 600,
        height: 600,
        child: TimeGrid(
          days: [monday],
          layers: layers,
          now: DateTime(2026, 10, 19, 9),
          metrics: const TimeGridMetrics(hourExtent: 60),
          initialScrollHour: 8,
        ),
      ),
    ),
  );

  TimeGridItem item(String id, {IconData? glyph}) => TimeGridItem(
    id: id,
    start: DateTime(2026, 10, 19, 10),
    end: DateTime(2026, 10, 19, 12),
    title: id,
    subtitle: '1 / 2',
    glyph: glyph,
  );

  group('block glyph', () {
    testWidgets('a block layer puts its glyph on every block', (tester) async {
      await tester.pumpWidget(
        grid([
          TimeGridLayer(
            id: 'mine',
            items: [item('Kasse')],
            glyph: LucideIcons.check,
          ),
        ]),
      );
      await tester.pump();
      expect(find.text('Kasse'), findsOneWidget);
      expect(find.byIcon(LucideIcons.check), findsOneWidget);
    });

    testWidgets('an item adds its own glyph beside the layer one', (
      tester,
    ) async {
      await tester.pumpWidget(
        grid([
          TimeGridLayer(
            id: 'mine',
            items: [item('Aufbau', glyph: LucideIcons.triangleAlert)],
            glyph: LucideIcons.check,
          ),
        ]),
      );
      await tester.pump();
      expect(find.byIcon(LucideIcons.check), findsOneWidget);
      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
    });

    testWidgets('without a glyph a block draws none, as before', (
      tester,
    ) async {
      await tester.pumpWidget(
        grid([
          TimeGridLayer(id: 'entries', items: [item('Entry')]),
        ]),
      );
      await tester.pump();
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('edge: false drops the tinted bar, the default keeps it', (
      tester,
    ) async {
      Border? borderOf(WidgetTester tester, String title) {
        final box = tester.widget<Container>(
          find
              .ancestor(of: find.text(title), matching: find.byType(Container))
              .first,
        );
        return (box.decoration as BoxDecoration?)?.border as Border?;
      }

      await tester.pumpWidget(
        grid([
          TimeGridLayer(id: 'entries', items: [item('Edged')]),
        ]),
      );
      await tester.pump();
      expect(borderOf(tester, 'Edged')?.left.width, 2.5);

      await tester.pumpWidget(
        grid([
          TimeGridLayer(id: 'shifts', items: [item('Plain')], edge: false),
        ]),
      );
      await tester.pump();
      expect(borderOf(tester, 'Plain'), isNull);
    });
  });

  group('month, marks only', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool marksOnly,
      TimeDayDots? Function(DateTime)? dotsOn,
      void Function(DateTime)? onTapDay,
    }) async {
      tester.view
        ..physicalSize = const Size(320, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeMonthScroller(
              anchor: DateTime(2026, 10),
              jump: 0,
              revision: 0,
              now: DateTime(2026, 10, 8, 10),
              itemsForDay: (key) => [
                TimeGridItem(
                  id: 'x$key',
                  start: DateTime(2026, 10, 8, 10),
                  end: DateTime(2026, 10, 8, 12),
                  title: 'Messestand',
                ),
              ],
              onNeedMonths: (_) {},
              onMonthChanged: (_) {},
              onTapDay: onTapDay,
              marksOnly: marksOnly,
              dotsOn: dotsOn,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('writes no chips and draws the dots', (tester) async {
      await pump(
        tester,
        marksOnly: true,
        dotsOn: (day) => day.day == 24
            ? const TimeDayDots(dot: true, ring: true, label: 'both')
            : null,
      );
      expect(find.text('Messestand'), findsNothing);
      expect(find.byType(TimeDayDotsRow), findsWidgets);
    });

    testWidgets('a tapped day is reported', (tester) async {
      DateTime? tapped;
      await pump(tester, marksOnly: true, onTapDay: (day) => tapped = day);
      await tester.tap(find.text('15').first);
      expect(tapped, DateTime(2026, 10, 15));
    });

    testWidgets('off by default: chips as before', (tester) async {
      await pump(tester, marksOnly: false);
      expect(find.text('Messestand'), findsWidgets);
      expect(find.byType(TimeDayDotsRow), findsNothing);
    });

    testWidgets('a cell is at least 44 wide on a 320 phone', (tester) async {
      await pump(tester, marksOnly: true);
      final cell = tester.getSize(
        find
            .ancestor(of: find.text('15').first, matching: find.byType(InkWell))
            .first,
      );
      expect(cell.width, greaterThanOrEqualTo(44));
    });
  });

  group('TimeWeekStrip', () {
    final days = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];

    Future<void> pump(
      WidgetTester tester, {
      TimeDayDots? Function(DateTime)? dotsOn,
      void Function(DateTime)? onTap,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 312,
              height: dotsOn == null ? kTimeWeekStrip : kTimeWeekStripWithDots,
              child: TimeWeekStrip(
                days: days,
                focused: DateTime(2026, 10, 24),
                today: DateTime(2026, 10, 20),
                onTap: onTap ?? (_) {},
                dotsOn: dotsOn,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('without marks it draws none', (tester) async {
      await pump(tester);
      expect(find.byType(TimeDayDotsRow), findsNothing);
      expect(find.text('24'), findsOneWidget);
    });

    testWidgets('marks a day and names the marks', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        dotsOn: (day) => day.day == 22
            ? const TimeDayDots(dot: true, label: 'Eigene Schicht')
            : null,
      );
      expect(find.byType(TimeDayDotsRow), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Eigene Schicht')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a day is a 44 point target on a 320 phone', (tester) async {
      DateTime? tapped;
      await pump(tester, onTap: (day) => tapped = day);
      final size = tester.getSize(find.byType(TimeWeekStripDay).first);
      expect(size.width, greaterThanOrEqualTo(44));
      await tester.tap(find.text('21'));
      expect(tapped, DateTime(2026, 10, 21));
    });
  });
}
