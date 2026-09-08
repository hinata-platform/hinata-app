/// What a scrolling month puts in front of a reader: the day, what it came to,
/// as many of its entries as the cell is tall enough to name — and, as the
/// finger moves, which month it is now in and which months it needs.
///
/// One `testWidgets` on purpose. The cells print real durations, so this pumps
/// the real message bundle — and the asset-backed i18next delegate only
/// resolves in the first widget test of a file, so a second one would render an
/// empty tree and assert nothing. (Same reason `fmt_duration_test` is shaped
/// this way.)
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/i18n/i18n.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:hinata/core/widgets/time_grid/time_grid_model.dart';
import 'package:hinata/core/widgets/time_grid/time_month_grid.dart';
import 'package:hinata/core/widgets/time_grid/time_month_layout.dart';

void main() {
  testWidgets('a month of days, what was logged on them, and where it scrolls', (
    tester,
  ) async {
    TimeGridItem entry(String id, int day, int hour, {int minutes = 60}) =>
        TimeGridItem(
          id: id,
          start: DateTime(2026, 9, day, hour),
          end: DateTime(2026, 9, day, hour).add(Duration(minutes: minutes)),
          title: id,
          minutes: minutes,
        );

    DateTime? tapped;
    final needed = <int>{};
    final retried = <DateTime>[];
    var named = <DateTime>[];

    Future<void> pump({
      List<TimeGridItem> items = const [],
      Size size = const Size(400, 900),
      Key? key,
      Brightness brightness = Brightness.light,
      DateTime? anchor,
      int jump = 0,
      String? Function(int monthKey)? failureFor,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tapped = null;
      retried.clear();
      needed.clear();
      named = [];
      final byDay = groupItemsByDay(items);
      // The app sets this once per frame from the resolved theme; the neutral
      // tokens are read off it as widgets build. A harness that only hands
      // `ThemeData` a brightness would leave every colour on its light value.
      AppColors.brightness = brightness;
      await tester.pumpWidget(
        MaterialApp(
          key: key,
          theme: ThemeData(brightness: brightness),
          locale: const Locale('de'),
          supportedLocales: I18n.supportedLocales,
          localizationsDelegates: I18n.delegates(),
          home: Scaffold(
            body: TimeMonthScroller(
              anchor: anchor ?? DateTime(2026, 9),
              jump: jump,
              revision: 0,
              now: DateTime(2026, 9, 8, 10),
              itemsForDay: (key) => byDay[key] ?? const [],
              failureFor: failureFor,
              onNeedMonths: (months) => needed.addAll(months.map(monthKey)),
              onRetryMonth: (month) => retried.add(month),
              onMonthChanged: (month) => named.add(month),
              onTapDay: (day) => tapped = day,
            ),
          ),
        ),
      );
      // The bundle comes from a real asset: let the I/O run, then give the
      // delegate the timed frame on which it hands its translations down.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    addTearDown(tester.view.reset);
    addTearDown(() => AppColors.brightness = Brightness.light);

    // ── A day names its entries, and says what they came to ──
    await pump(
      key: const ValueKey('named'),
      items: [
        entry('Standup', 7, 9, minutes: 90),
        entry('Review', 7, 14, minutes: 30),
      ],
    );
    expect(find.text('Standup'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('2 h'), findsOneWidget);

    // ── It says which month it is in, and asks for that one and its neighbours ──
    expect(named, [DateTime(2026, 9)]);
    expect(needed, {
      monthKey(DateTime(2026, 8)),
      monthKey(DateTime(2026, 9)),
      monthKey(DateTime(2026, 10)),
    });

    // ── An entry with no hours counts towards its day ──
    // A plain duration begins and ends at midnight; it has no span at all, and
    // is exactly the entry the hour canvas cannot draw.
    await pump(
      key: const ValueKey('untimed'),
      items: [
        TimeGridItem(
          id: 'logged',
          start: DateTime(2026, 9, 7),
          end: DateTime(2026, 9, 7),
          title: 'Notiz',
          minutes: 45,
        ),
      ],
    );
    expect(find.text('Notiz'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);

    // ── More entries than the cell can name ──
    await pump(
      key: const ValueKey('crowded'),
      items: [for (var i = 0; i < 12; i++) entry('Eintrag $i', 7, 8 + i)],
    );
    expect(find.text('Eintrag 0'), findsOneWidget);
    // The whole string, not a prefix: German's singular is "weiterer" and its
    // plural "weitere", so `textContaining('weitere')` would match both and
    // could not tell a working plural from a broken one.
    expect(find.textContaining(RegExp(r'^\+\d+ weitere$')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // ── Tapping a day reports it ──
    // The scroller builds the months either side of the one on screen, so a
    // date number is not unique in the tree. Take the one inside the month it
    // opened on: that block starts at the top of the viewport and is five rows
    // tall.
    Offset centreOfDay(String label) {
      for (final element in find.text(label).evaluate()) {
        final box = element.renderObject! as RenderBox;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        if (rect.top >= 0 && rect.bottom <= kMonthWeekExtent * 5) {
          return rect.center;
        }
      }
      fail('no "$label" inside the month on screen');
    }

    await pump(key: const ValueKey('tap'));
    await tester.tapAt(centreOfDay('15'));
    expect(tapped, DateTime(2026, 9, 15));

    // ── Scrolling on reaches the next month, names it, and asks for it ──
    await pump(key: const ValueKey('forward'));
    // September 2026 is five rows; half a row past its last leaves the top of
    // the viewport inside October, with room to spare either side of the touch
    // slop the drag spends getting started.
    await tester.drag(
      find.byType(TimeMonthScroller),
      const Offset(0, -kMonthWeekExtent * 5.5),
    );
    await tester.pumpAndSettle();
    expect(named.last, DateTime(2026, 10));
    expect(needed, contains(monthKey(DateTime(2026, 11))));

    // ── And scrolling back reaches the month before the one it opened on ──
    await pump(key: const ValueKey('back'));
    await tester.drag(
      find.byType(TimeMonthScroller),
      const Offset(0, kMonthWeekExtent * 2),
    );
    await tester.pumpAndSettle();
    expect(named.last, DateTime(2026, 8));
    expect(needed, contains(monthKey(DateTime(2026, 7))));
    expect(tester.takeException(), isNull);

    // ── A theme change throws the held blocks away ──
    // The app's neutral tokens are a global the widgets read as they build, so
    // a month kept across a theme change keeps the ink it was born with — light
    // navy numbers on the dark canvas, very nearly invisible.
    await pump(key: const ValueKey('theme'));
    Color inkOf(String text) =>
        tester.widget<Text>(find.text(text).first).style!.color!;
    final light = inkOf('15');

    await pump(key: const ValueKey('theme'), brightness: Brightness.dark);

    expect(
      inkOf('15'),
      isNot(light),
      reason: 'the numbers are re-inked for the theme they are drawn in',
    );
    expect(tester.takeException(), isNull);

    // ── A jump re-centres even when the anchor is the month already held ──
    // Scrolling does not move the anchor, so "today" while anchored on this
    // month hands the scroller a value it has already seen. Re-centring only on
    // a *changed* anchor left it where the finger stopped while the title above
    // it named somewhere else.
    await pump(key: const ValueKey('jump'));
    await tester.drag(
      find.byType(TimeMonthScroller),
      const Offset(0, -kMonthWeekExtent * 5.5),
    );
    await tester.pumpAndSettle();
    expect(named.last, DateTime(2026, 10));

    await pump(key: const ValueKey('jump'), jump: 1);
    expect(
      named.last,
      DateTime(2026, 9),
      reason: 'the same anchor, asked for again, is still a jump',
    );
    expect(tester.takeException(), isNull);

    // ── Month heights are remembered per month, not per scroll offset ──
    // Offset 0 means a different month after a jump. Keyed on the offset, a
    // month was measured with the height of whichever month sat at that offset
    // before it, and every scroll after that named the month next door — the
    // title, the prefetch and the window a save re-fetches, all wrong together.
    //
    // Measured rather than predicted: the row a month ends on depends on the
    // day the harness's locale starts a week on, and the point here is that the
    // scroller measures *each* month for itself. Driven by the scroll position
    // rather than by a drag, because a synthetic drag spends an unknowable part
    // of itself on the touch slop.
    ScrollPosition positionOf() =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position;

    /// How many rows the month at the top occupies, read off the row on which
    /// the scroller starts naming the next one.
    Future<int> rowsOfAnchor() async {
      final start = named.last;
      for (var row = 1; row <= 6; row++) {
        positionOf().jumpTo(kMonthWeekExtent * row);
        await tester.pump();
        if (named.last != start) return row;
      }
      fail('the month never changed within six rows');
    }

    // September 2026 is five rows and August 2026 is six, whichever day the
    // week starts on — so this says something about the scroller and nothing
    // about the locale the harness happened to resolve.
    await pump(key: const ValueKey('heights'));
    expect(await rowsOfAnchor(), 5, reason: 'September, in five rows');

    await pump(
      key: const ValueKey('heights'),
      anchor: DateTime(2026, 8),
      jump: 1,
    );
    expect(named.last, DateTime(2026, 8), reason: 'the jump re-centred on it');
    expect(
      await rowsOfAnchor(),
      6,
      reason: 'August is measured by its own rows, not by September\'s',
    );
    expect(tester.takeException(), isNull);

    // ── A month that could not be read says so, where that month belongs ──
    // Drawn as thirty empty cells it is the calendar telling somebody they did
    // not work that month, which is the one thing a record of hours must not
    // do — and it is worse now that days with nothing on them are no longer
    // faded, because an unread month and a genuinely empty one look identical.
    await pump(
      key: const ValueKey('failed'),
      failureFor: (key) =>
          key == monthKey(DateTime(2026, 9)) ? 'errors.unexpected' : null,
    );

    // By its glyph, not its label: this file pumps the real message bundle, so
    // the words are German and would move with the translation.
    expect(find.byIcon(LucideIcons.cloudOff), findsOneWidget);
    expect(
      find.byIcon(LucideIcons.refreshCw),
      findsOneWidget,
      reason: 'and a way to ask again',
    );
    await tester.tap(find.byIcon(LucideIcons.refreshCw));
    await tester.pump();
    expect(retried, [DateTime(2026, 9)]);
    expect(tester.takeException(), isNull);
  });
}
