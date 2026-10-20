import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/widgets/time_grid/time_grid.dart';
import 'package:hinata/core/widgets/time_grid/time_grid_geometry.dart';
import 'package:hinata/core/widgets/time_grid/time_grid_model.dart';
import 'package:hinata/core/widgets/time_grid/time_month_grid.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// What the grids give the shift calendar to plan with (HIN-166): the week
/// scrolls again when told, a sweep is drawn in the tint the block will get,
/// and a month day offers a "+" to a pointer and to the keyboard.
void main() {
  final monday = DateTime(2026, 9, 7);

  group('TimeGrid', () {
    Widget host({
      required int hour,
      Object? scrollKey,
      Color? createTint,
      void Function(TimeGridSpan)? onCreate,
    }) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 500,
          child: TimeGrid(
            days: [monday],
            layers: const [TimeGridLayer(id: 'none', items: [])],
            now: DateTime(2026, 9, 7, 10),
            metrics: const TimeGridMetrics(hourExtent: 60),
            initialScrollHour: hour,
            scrollKey: scrollKey,
            createTint: createTint,
            onCreate: onCreate,
          ),
        ),
      ),
    );

    double offset(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(TimeGrid),
                matching: find.byType(Scrollable),
              )
              .at(1),
        )
        .position
        .pixels;

    testWidgets('scrolls to the hour again when the key changes', (
      tester,
    ) async {
      await tester.pumpWidget(host(hour: 8, scrollKey: 'a'));
      await tester.pump();
      final atEight = offset(tester);
      expect(atEight, closeTo(8 * 60 - 10, 1));

      // The same key: the reader's scroll is left alone.
      await tester.pumpWidget(host(hour: 5, scrollKey: 'a'));
      await tester.pump();
      expect(offset(tester), atEight);

      await tester.pumpWidget(host(hour: 5, scrollKey: 'b'));
      await tester.pump();
      expect(offset(tester), closeTo(5 * 60 - 10, 1));
    });

    testWidgets('a sweep is drawn in the create tint, without an edge', (
      tester,
    ) async {
      final tint = AppColors.pastelFor(3);
      await tester.pumpWidget(
        host(hour: 8, createTint: tint, onCreate: (_) {}),
      );
      await tester.pump();
      final canvas = tester.getRect(find.byType(TimeGrid));
      final gesture = await tester.startGesture(
        Offset(canvas.left + kTimeGridGutter + 40, canvas.top + 200),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 90));
      await tester.pump();
      final preview = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color == tint)
          .toList();
      expect(preview, hasLength(1));
      final border = preview.single.border! as Border;
      // The hairline every block without an edge has, never the accent.
      expect(border.top.color, AppColors.hairline);
      expect(border.left.width, 1);
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('TimeMonthScroller, marks only', () {
    Future<void> pump(
      WidgetTester tester, {
      void Function(DateTime, Rect)? onAddOnDay,
      void Function(DateTime, Rect)? onDayMenu,
    }) async {
      tester.view
        ..physicalSize = const Size(1000, 900)
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
              itemsForDay: (_) => const [],
              onNeedMonths: (_) {},
              onMonthChanged: (_) {},
              onTapDay: (_) {},
              marksOnly: true,
              onAddOnDay: onAddOnDay,
              onDayMenu: onDayMenu,
              addLabel: (day) => 'Schicht am ${day.day}.${day.month}. anlegen',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    Finder plusOf(int day) => find.byWidgetPredicate(
      (w) =>
          w is Semantics && w.properties.label == 'Schicht am $day.10. anlegen',
    );

    double opacityOf(WidgetTester tester, int day) => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: plusOf(day),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    testWidgets('the "+" shows on hover and hands back its day', (
      tester,
    ) async {
      DateTime? added;
      Rect? anchor;
      await pump(
        tester,
        onAddOnDay: (day, rect) {
          added = day;
          anchor = rect;
        },
      );
      expect(opacityOf(tester, 15), 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(plusOf(15)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacityOf(tester, 15), 1);
      expect(opacityOf(tester, 16), 0);

      await tester.tap(plusOf(15));
      expect(added, DateTime(2026, 10, 15));
      expect(anchor!.width, greaterThanOrEqualTo(44));
      expect(anchor!.height, greaterThanOrEqualTo(44));
    });

    testWidgets('the "+" is reached with the keyboard and shown on focus', (
      tester,
    ) async {
      DateTime? added;
      await pump(tester, onAddOnDay: (day, _) => added = day);
      // Tab through the days until a "+" holds the focus: it shows then.
      var shown = false;
      for (var i = 0; i < 200 && !shown; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump(const Duration(milliseconds: 150));
        shown = tester
            .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
            .any((o) => o.opacity == 1);
      }
      expect(shown, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(added, isNotNull);
    });

    testWidgets('no "+" without a handler; a right click opens the day menu', (
      tester,
    ) async {
      DateTime? menu;
      await pump(tester, onDayMenu: (day, _) => menu = day);
      expect(find.byIcon(LucideIcons.plus), findsNothing);
      await tester.tap(find.text('20').first, buttons: kSecondaryButton);
      expect(menu, DateTime(2026, 10, 20));
    });
  });
}
