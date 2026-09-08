import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/time_grid/time_grid_model.dart';
import 'package:hinata/core/widgets/time_grid/time_month_layout.dart';

/// The arithmetic a month is drawn from. An off-by-one in the leading blanks
/// moves every entry in the month by a day and still looks like a calendar,
/// which is why this is tested away from the widget.
void main() {
  List<DateTime> month(int year, int monthOf) {
    final days = <DateTime>[];
    for (var day = DateTime(year, monthOf); day.month == monthOf;) {
      days.add(day);
      day = DateTime(year, monthOf, day.day + 1);
    }
    return days;
  }

  TimeGridItem at(
    String id,
    DateTime start,
    DateTime end, {
    int? minutes,
    DateTime? day,
  }) => TimeGridItem(
    id: id,
    start: start,
    end: end,
    title: id,
    minutes: minutes,
    day: day,
  );

  group('where the days land', () {
    test(
      'a month that starts on a Tuesday leaves one blank on a German week',
      () {
        // 1 September 2026 is a Tuesday. Weeks starting Monday (index 1) leave
        // exactly one cell before it.
        final layout = MonthLayout.of(month(2026, 9), firstDayOfWeekIndex: 1);

        expect(layout.dayAt(0, 0), isNull);
        expect(layout.dayAt(0, 1), DateTime(2026, 9, 1));
        expect(layout.dayAt(0, 6), DateTime(2026, 9, 6));
        expect(layout.dayAt(1, 0), DateTime(2026, 9, 7));
      },
    );

    test('the same month starts a column later on an American week', () {
      // Weeks starting Sunday (index 0): Monday is one blank, Tuesday is two.
      final layout = MonthLayout.of(month(2026, 9), firstDayOfWeekIndex: 0);

      expect(layout.dayAt(0, 1), isNull);
      expect(layout.dayAt(0, 2), DateTime(2026, 9, 1));
    });

    test('the grid has as many rows as the month needs, and no more', () {
      // 30 days from a Tuesday on a Monday week: 1 blank + 30 = 31 cells = 5.
      expect(MonthLayout.of(month(2026, 9), firstDayOfWeekIndex: 1).weeks, 5);
      // February 2027 has 28 days and begins on a Monday: exactly 4.
      expect(MonthLayout.of(month(2027, 2), firstDayOfWeekIndex: 1).weeks, 4);
      // A 31-day month beginning on a Sunday needs 6 rows on a Monday week.
      expect(MonthLayout.of(month(2026, 8), firstDayOfWeekIndex: 1).weeks, 6);
    });

    test('cells past the end of the month are blank, not the next month', () {
      final layout = MonthLayout.of(month(2026, 9), firstDayOfWeekIndex: 1);

      expect(layout.dayAt(4, 2), DateTime(2026, 9, 30));
      expect(layout.dayAt(4, 3), isNull);
    });

    test('an empty month is a grid with no rows rather than a crash', () {
      final layout = MonthLayout.of(const [], firstDayOfWeekIndex: 1);

      expect(layout.weeks, 0);
      expect(layout.dayAt(0, 0), isNull);
    });
  });

  group('which day an entry belongs to', () {
    final days = month(2026, 9);

    test('an entry is filed under the day it starts on', () {
      final grouped = groupByDay([
        TimeGridLayer(
          id: 'entries',
          items: [at('a', DateTime(2026, 9, 7, 9), DateTime(2026, 9, 7, 11))],
        ),
      ], days);

      expect(grouped[DateTime(2026, 9, 7)]!.single.id, 'a');
    });

    test('a night shift appears once, on the day it began', () {
      // The hour canvas draws this one in both columns, cut at midnight,
      // because there it is a shape with two ends. A month cell is a list of
      // what was logged — and the list, the timesheet and the server all file
      // it under the 7th. Counting it twice would make the month the one view
      // that disagrees about the week's total.
      final grouped = groupByDay([
        TimeGridLayer(
          id: 'entries',
          items: [
            at(
              'night',
              DateTime(2026, 9, 7, 22),
              DateTime(2026, 9, 8, 6),
              minutes: 480,
            ),
          ],
        ),
      ], days);

      expect(grouped[DateTime(2026, 9, 7)]!.single.id, 'night');
      expect(grouped[DateTime(2026, 9, 8)], isNull);
    });

    test('an entry with no hours still lands on its day', () {
      // A plain duration begins and ends at midnight; nothing about its span
      // says which day it is, only where it sits.
      final grouped = groupByDay([
        TimeGridLayer(
          id: 'untimed',
          items: [
            at(
              'logged',
              DateTime(2026, 9, 12),
              DateTime(2026, 9, 12),
              minutes: 90,
            ),
          ],
        ),
      ], days);

      expect(grouped[DateTime(2026, 9, 12)]!.single.id, 'logged');
      expect(grouped[DateTime(2026, 9, 12)]!.single.accounted.inMinutes, 90);
    });

    test('a filed day wins over the day the hours fall on', () {
      // The reporting day is a field of its own on the server, and editing only
      // the interval moves the hours without moving it. Keyed on the start, the
      // 20th would print two hours nobody worked that day and the 10th would
      // print none.
      final grouped = groupByDay([
        TimeGridLayer(
          id: 'entries',
          items: [
            at(
              'moved',
              DateTime(2026, 9, 20, 9),
              DateTime(2026, 9, 20, 11),
              minutes: 120,
              day: DateTime(2026, 9, 10),
            ),
          ],
        ),
      ], days);

      expect(grouped[DateTime(2026, 9, 10)]!.single.id, 'moved');
      expect(grouped[DateTime(2026, 9, 20)], isNull);
    });

    test('an entry filed inside the window is kept, wherever its hours are', () {
      // The window was selected on the filed day, so an entry whose hours have
      // been moved into the next month still belongs to this one. Dropping it
      // would lose the hours from both months at once.
      final grouped = groupByDay([
        TimeGridLayer(
          id: 'entries',
          items: [
            at(
              'spilled',
              DateTime(2026, 10, 2, 9),
              DateTime(2026, 10, 2, 11),
              minutes: 120,
              day: DateTime(2026, 9, 30),
            ),
          ],
        ),
      ], days);

      expect(grouped[DateTime(2026, 9, 30)]!.single.id, 'spilled');
    });

    test('entries outside the window are dropped', () {
      final grouped = groupByDay([
        TimeGridLayer(
          id: 'entries',
          items: [
            at('before', DateTime(2026, 8, 31, 9), DateTime(2026, 8, 31, 10)),
            at('after', DateTime(2026, 10, 1, 9), DateTime(2026, 10, 1, 10)),
          ],
        ),
      ], days);

      expect(grouped, isEmpty);
    });

    test('a day is ordered by time, and ties by id', () {
      final grouped = groupByDay([
        TimeGridLayer(
          id: 'entries',
          items: [
            at('late', DateTime(2026, 9, 7, 16), DateTime(2026, 9, 7, 17)),
            at('b', DateTime(2026, 9, 7, 9), DateTime(2026, 9, 7, 10)),
            at('a', DateTime(2026, 9, 7, 9), DateTime(2026, 9, 7, 10)),
          ],
        ),
      ], days);

      expect(grouped[DateTime(2026, 9, 7)]!.map((item) => item.id), [
        'a',
        'b',
        'late',
      ]);
    });

    test('every layer files into the same day', () {
      final grouped = groupByDay([
        TimeGridLayer(
          id: 'entries',
          items: [
            at('timed', DateTime(2026, 9, 7, 9), DateTime(2026, 9, 7, 10)),
          ],
        ),
        TimeGridLayer(
          id: 'untimed',
          placement: TimeGridPlacement.band,
          items: [
            at(
              'duration',
              DateTime(2026, 9, 7),
              DateTime(2026, 9, 7),
              minutes: 30,
            ),
          ],
        ),
      ], days);

      expect(grouped[DateTime(2026, 9, 7)]!.length, 2);
    });
  });

  group('what an item accounts for', () {
    test('a span measures itself when nothing else is said', () {
      expect(
        at('a', DateTime(2026, 9, 7, 9), DateTime(2026, 9, 7, 11)).accounted,
        const Duration(hours: 2),
      );
    });

    test('logged minutes win over the span', () {
      // The entry's own number is the one the list and the timesheet add up.
      expect(
        at(
          'a',
          DateTime(2026, 9, 7, 9),
          DateTime(2026, 9, 7, 11),
          minutes: 90,
        ).accounted,
        const Duration(minutes: 90),
      );
    });

    test('clipping a block to a column keeps the record\'s own numbers', () {
      // The hour canvas cuts an entry that crosses midnight into both columns.
      // That is a drawing, not a move: the entry has not gone anywhere, so its
      // filed day and its logged minutes must survive being cut.
      final clipped = at(
        'a',
        DateTime(2026, 9, 7, 9),
        DateTime(2026, 9, 7, 11),
        minutes: 120,
        day: DateTime(2026, 9, 7),
      ).movedTo(DateTime(2026, 9, 8, 9), DateTime(2026, 9, 8, 11));

      expect(clipped.minutes, 120);
      expect(clipped.day, DateTime(2026, 9, 7));
    });

    test('a real move re-files the item and re-measures it', () {
      // A drop is the other case: it changes the day the server will file the
      // entry under and the length it will record. Carrying the old pair
      // through left the preview filed where it came from, with the total it
      // used to have — and, filed there, drawn on no canvas at all.
      final moved =
          at(
            'a',
            DateTime(2026, 9, 7, 9),
            DateTime(2026, 9, 7, 11),
            minutes: 120,
            day: DateTime(2026, 9, 7),
          ).movedTo(
            DateTime(2026, 9, 20, 9),
            DateTime(2026, 9, 20, 10),
            day: DateTime(2026, 9, 20),
            keepMinutes: false,
          );

      expect(moved.day, DateTime(2026, 9, 20));
      expect(moved.filedOn, DateTime(2026, 9, 20));
      expect(moved.minutes, isNull);
      expect(moved.accounted, const Duration(hours: 1));
    });

    test('an item that names no day falls back to the day it starts on', () {
      expect(
        at('a', DateTime(2026, 9, 7, 22), DateTime(2026, 9, 8, 6)).filedOn,
        DateTime(2026, 9, 7),
      );
    });
  });

  group('counting days and months', () {
    test('two dates a clock change apart are still a whole number of days', () {
      // `Duration.inDays` on two local midnights across a DST boundary is 23 or
      // 25 hours short of a whole number of days and truncates to one less —
      // which opened the calendar's day pager on yesterday.
      //
      // Honest about its own reach: this only tells the two implementations
      // apart on a host whose zone actually shifts on those dates. On a UTC CI
      // runner it passes either way, so it is a guard for a developer's machine
      // rather than the thing standing between the bug and green.
      expect(daysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
      expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
      expect(daysBetween(DateTime(2026, 1, 1), DateTime(2026, 12, 31)), 364);
      expect(daysBetween(DateTime(2026, 9, 10), DateTime(2026, 9, 8)), -2);
    });

    test('a day key ignores the time of day and orders with the calendar', () {
      expect(
        dayKey(DateTime(2026, 9, 7, 22, 30)),
        dayKey(DateTime(2026, 9, 7)),
      );
      expect(
        dayKey(DateTime(2026, 9, 7)) < dayKey(DateTime(2026, 10, 1)),
        isTrue,
      );
      expect(
        dayKey(DateTime(2026, 12, 31)) < dayKey(DateTime(2027, 1, 1)),
        isTrue,
      );
    });

    test('a month key ignores the day and crosses the year', () {
      expect(monthKey(DateTime(2026, 9, 30)), monthKey(DateTime(2026, 9)));
      expect(
        monthKey(DateTime(2026, 12)) < monthKey(DateTime(2027, 1)),
        isTrue,
      );
    });

    test('a month is as many rows as the grid draws it in', () {
      // The scrolling month turns an offset into "which month is at the top" by
      // adding these up, so a second copy of the arithmetic that drifted by a
      // row would name the wrong month and fetch the wrong window.
      for (final at in [
        DateTime(2026, 9),
        DateTime(2026, 8),
        DateTime(2027, 2),
        DateTime(2026, 2),
      ]) {
        for (final first in [0, 1, 6]) {
          expect(
            weeksInMonth(at, firstDayOfWeekIndex: first),
            MonthLayout.of(
              month(at.year, at.month),
              firstDayOfWeekIndex: first,
            ).weeks,
            reason: '$at on a week starting $first',
          );
        }
      }
    });
  });

  group('grouping without a window', () {
    test('an entry is filed under the day it belongs to', () {
      final grouped = groupItemsByDay([
        at(
          'a',
          DateTime(2026, 9, 20, 9),
          DateTime(2026, 9, 20, 11),
          day: DateTime(2026, 9, 10),
        ),
      ]);

      expect(grouped[dayKey(DateTime(2026, 9, 10))]!.single.id, 'a');
      expect(grouped[dayKey(DateTime(2026, 9, 20))], isNull);
    });

    test('the same entry held twice is filed once', () {
      // Windows are fetched a month at a time and invalidated one at a time, so
      // a stale month and a fresh one can both be held for a moment. Drawn
      // twice, an entry is two blocks and its minutes count into a day twice.
      final item = at(
        'a',
        DateTime(2026, 9, 7, 9),
        DateTime(2026, 9, 7, 11),
        minutes: 120,
      );
      final grouped = groupItemsByDay([item, item]);

      expect(grouped[dayKey(DateTime(2026, 9, 7))], hasLength(1));
    });
  });
}
