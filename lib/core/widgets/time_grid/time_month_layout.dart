/// Where a month's days land on a seven-column grid, and which entries belong
/// to each of them.
///
/// Split out of the widget because it is arithmetic, and arithmetic about
/// weekdays is where a calendar goes quietly wrong: an off-by-one in the
/// leading blanks moves every entry in the month by a day, and it looks
/// perfectly plausible. Here it can be tested without a widget tree, in every
/// locale the app speaks.
library;

import 'package:flutter/foundation.dart';

import 'time_grid_model.dart';

@immutable
class MonthLayout {
  const MonthLayout._(this._days, this._leading, this.weeks);

  /// Lays [days] — one month, ascending, at local midnight — out in weeks that
  /// begin on [firstDayOfWeekIndex] (0 Sunday … 6 Saturday, as
  /// `MaterialLocalizations` reports it).
  factory MonthLayout.of(
    List<DateTime> days, {
    required int firstDayOfWeekIndex,
  }) {
    if (days.isEmpty) return const MonthLayout._([], 0, 0);
    final leading = leadingBlanks(
      days.first,
      firstDayOfWeekIndex: firstDayOfWeekIndex,
    );
    return MonthLayout._(days, leading, weekRows(leading, days.length));
  }

  final List<DateTime> _days;

  /// Blank cells before the first of the month.
  final int _leading;

  /// Rows the month occupies — four to six, depending on where it starts.
  final int weeks;

  /// The day in row [week], column [column], or null for a cell outside the
  /// month.
  DateTime? dayAt(int week, int column) {
    final index = week * 7 + column - _leading;
    return index >= 0 && index < _days.length ? _days[index] : null;
  }
}

/// Blank cells before [first] — the first of a month — on a week beginning on
/// [firstDayOfWeekIndex] (0 Sunday … 6 Saturday, as `MaterialLocalizations`
/// reports it).
///
/// `weekday` is 1 Monday … 7 Sunday; `% 7` turns it into the 0 Sunday … 6
/// Saturday the first-day index is counted in.
int leadingBlanks(DateTime first, {required int firstDayOfWeekIndex}) =>
    (first.weekday % 7 - firstDayOfWeekIndex + 7) % 7;

/// Rows a month of [length] days occupies after [leading] blanks — four to six.
int weekRows(int leading, int length) => ((leading + length) / 7).ceil();

/// Rows [month] occupies on a week beginning on [firstDayOfWeekIndex].
///
/// The scroller measures a month block with this and [MonthLayout] lays one out
/// with it, which is the point of it being one function. The scroller turns a
/// scroll offset into "which month is at the top" by adding these heights up,
/// so a second copy of the arithmetic that drifted by a row would name the
/// wrong month and fetch the wrong window — and would look entirely plausible
/// doing it.
int weeksInMonth(DateTime month, {required int firstDayOfWeekIndex}) =>
    weekRows(
      leadingBlanks(
        DateTime(month.year, month.month),
        firstDayOfWeekIndex: firstDayOfWeekIndex,
      ),
      // The 0th of the next month is the last of this one.
      DateTime(month.year, month.month + 1, 0).day,
    );

/// Whole calendar days from [from] to [to], counted on the calendar rather than
/// on the clock.
///
/// `Duration.inDays` on two local midnights is off by one wherever the clocks
/// moved in between: the span is 23 or 25 hours short of a whole number of
/// days, and truncation eats the remainder. Re-reading both as UTC makes every
/// day exactly 24 hours long again, which is what "how many days apart" means.
int daysBetween(DateTime from, DateTime to) =>
    _daysSinceEpoch(to) - _daysSinceEpoch(from);

int _daysSinceEpoch(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).difference(_epoch).inDays;

final DateTime _epoch = DateTime.utc(1970);

/// A day, without the time of day — so an entry at 22:00 and the midnight a
/// column is keyed on are the same key. Ascending with the calendar, so keys
/// can be compared as well as looked up.
int dayKey(DateTime moment) =>
    moment.year * 10000 + moment.month * 100 + moment.day;

/// A month, as one comparable number — the key months are held under while the
/// calendar scrolls through them.
int monthKey(DateTime moment) => moment.year * 100 + moment.month;

/// Every item of [items], filed under [TimeGridItem.filedOn], with no window to
/// fall outside of.
///
/// The windowed [groupByDay] is the same act for a view that knows which days
/// it draws. A month that scrolls does not: the days it will reach are decided
/// by a finger, so it files everything it has been given and looks each day up
/// as it is drawn.
/// Deduplicated by id, because the caller's pool can hold the same entry twice:
/// windows are fetched a month at a time and a save invalidates them one at a
/// time, so a stale month and a fresh one can both be held for a moment. Drawn
/// twice, an entry is two blocks on the canvas and its minutes are counted
/// twice into a day.
Map<int, List<TimeGridItem>> groupItemsByDay(Iterable<TimeGridItem> items) {
  final byDay = <int, List<TimeGridItem>>{};
  final seen = <String>{};
  for (final item in items) {
    if (!seen.add(item.id)) continue;
    (byDay[dayKey(item.filedOn)] ??= []).add(item);
  }
  for (final entries in byDay.values) {
    entries.sort(_chronological);
  }
  return byDay;
}

/// Chronological, with the id as a tiebreaker so two entries logged for the
/// same minute keep one order between builds instead of swapping places.
int _chronological(TimeGridItem a, TimeGridItem b) {
  final byStart = a.start.compareTo(b.start);
  return byStart != 0 ? byStart : a.id.compareTo(b.id);
}

/// Every item in [layers], filed under the day of [days] it belongs to.
///
/// **By the day it is filed under, and once.** An entry that runs past midnight
/// is drawn in both of the columns it touches on the hour canvas, because there
/// it is a shape with two ends; a month cell is a list of what was logged, and
/// the list, the timesheet and the server all file that entry under one day.
/// Putting it in both cells would show eight hours twice and make the month the
/// one view that disagrees with the others about a week's total.
///
/// That day is [TimeGridItem.filedOn], not the day the item starts on, and the
/// difference is not academic: an entry's reporting day is a separate field the
/// server selects this very window by, and editing only an interval moves the
/// hours without moving the day. Keyed on the start, an entry moved into the
/// next month would vanish from both months — from the one that no longer
/// contains its hours, and from the one whose window never returned it.
///
/// Items outside [days] are dropped — a window is what was asked for, and a
/// stray entry on either side of it has no cell to go in.
Map<DateTime, List<TimeGridItem>> groupByDay(
  List<TimeGridLayer> layers,
  List<DateTime> days,
) {
  final known = {for (final day in days) dayKey(day): day};
  final byDay = <DateTime, List<TimeGridItem>>{};
  for (final layer in layers) {
    for (final item in layer.items) {
      final day = known[dayKey(item.filedOn)];
      if (day == null) continue;
      (byDay[day] ??= []).add(item);
    }
  }
  for (final entries in byDay.values) {
    entries.sort(_chronological);
  }
  return byDay;
}
