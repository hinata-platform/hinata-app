import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/widgets/time_grid/time_month_grid.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Holidays, absences and days nobody works, in the month (HIN-91, HIN-116).
///
/// The day canvas and the week canvas both marked them from the start; the
/// month did not, so a grid of thirty cells gave no sign that the third of
/// October was a public holiday. A month is the span people scan for exactly
/// that.
///
/// The grid is handed a glyph and a sentence rather than the availability
/// model: it belongs to the core and draws hours, and the day it had to know
/// what a holiday calendar is would be the day it could not be built without
/// one.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  Future<void> pump(
    WidgetTester tester, {
    ({IconData glyph, String label})? Function(DateTime day)? markOn,
  }) async {
    tester.view
      ..physicalSize = const Size(400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      // No localisation delegates: loading the real bundle works exactly once
      // per test file, and after that the app renders nothing at all. Widget
      // tests here render raw i18n keys anyway, and nothing this test looks at
      // is translated — the day numbers are numbers, and the mark's glyph and
      // sentence come from the callback under test.
      MaterialApp(
        home: Scaffold(
          body: TimeMonthScroller(
            anchor: DateTime(2026, 10),
            jump: 0,
            revision: 0,
            now: DateTime(2026, 10, 8, 10),
            itemsForDay: (key) => const [],
            onNeedMonths: (_) {},
            onMonthChanged: (_) {},
            markOn: markOn,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    // The month has to be on screen, or every `findsNothing` below would pass
    // for the wrong reason.
    expect(find.text('3'), findsWidgets, reason: 'the month never rendered');
  }

  testWidgets('a marked day carries its mark and says what it is', (
    tester,
  ) async {
    await pump(
      tester,
      markOn: (day) => day.month == 10 && day.day == 3
          ? (
              glyph: LucideIcons.calendarHeart,
              label: 'Feiertag: Tag der Deutschen Einheit',
            )
          : null,
    );

    expect(find.byIcon(LucideIcons.calendarHeart), findsOneWidget);
    // A cell has no room to write the sentence, so the glyph carries it.
    expect(
      find.byTooltip('Feiertag: Tag der Deutschen Einheit'),
      findsOneWidget,
    );
  });

  testWidgets('a month with nothing marked draws nothing extra', (
    tester,
  ) async {
    await pump(tester);

    // The month is on screen — `pump` does not return until it is — so these
    // two say something about the marks rather than about an empty tree.
    expect(find.text('3'), findsWidgets);
    expect(find.byIcon(LucideIcons.calendarHeart), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('a grid given no lookup at all still draws its month', (
    tester,
  ) async {
    // The timesheet and anything else that reuses this grid need not know about
    // availability, and must not have to pass a stub to say so. Asserted on a
    // day number rather than on the widget: what matters is that the month is
    // on screen, which is also what makes the "nothing marked" test above mean
    // something.
    await pump(tester);

    expect(find.text('3'), findsWidgets);
  });
}
