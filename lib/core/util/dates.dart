/// Shared date/time parsing for API payloads.
///
/// The backend sends every absolute timestamp as ISO-8601 **UTC** (trailing
/// `Z`) and every pure calendar date as `yyyy-MM-dd`. These two helpers encode
/// the one rule that keeps the whole app timezone-correct:
///
/// * [parseInstant] — an absolute moment (createdAt, updatedAt, resolvedAt, …).
///   Converted to the device's **local** zone at parse time, so any downstream
///   `DateFormat` / `MaterialLocalizations` renders in the user's timezone
///   automatically. Relative "x ago" helpers are unaffected either way because
///   `DateTime.difference` compares absolute instants.
///
/// * [parseDate] — a pure calendar date (dueDate, startDate, a tracker day, …).
///   It has **no** timezone and must never be shifted across zones, so it is
///   normalized to local midnight of that exact calendar day. Passing it through
///   `toLocal()` would be a bug (it could move the date to the previous day).
library;

import 'package:flutter/material.dart';

/// Parses an absolute timestamp into a **local** [DateTime]. Accepts an
/// ISO-8601 string (UTC or with offset) or a numeric epoch in milliseconds.
/// Returns `null` for null/blank/invalid input.
DateTime? parseInstant(Object? value) {
  if (value == null) return null;
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      value.toInt(),
      isUtc: true,
    ).toLocal();
  }
  if (value is String) {
    if (value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}

/// Parses a pure calendar date into local midnight of that day. Strips any time
/// or zone component so the date stays on the same calendar day everywhere.
DateTime? parseDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final dt = DateTime.tryParse(value);
  if (dt == null) return null;
  return DateTime(dt.year, dt.month, dt.day);
}

/// Formats a [DateTime] as the `yyyy-MM-dd` the backend expects for a pure
/// calendar date — the inverse of [parseDate].
///
/// Reads the wall-clock fields directly rather than going through
/// `toIso8601String()`: a value that is a *day* must be sent as the day it
/// says, and a UTC-flagged `DateTime` would otherwise be formatted in UTC and
/// slide to the previous day for anyone east of Greenwich.
String formatDateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The first day of [day]'s week, at local midnight, in the reader's locale.
///
/// `firstDayOfWeekIndex` is 0 for Sunday and 1 for Monday: German weeks start on
/// Monday, American ones on Sunday, and a grid that always began on Monday was
/// simply wrong for several of the nine languages the app speaks. The server's
/// own weeks stay ISO — approval periods are a different question — and nothing
/// here depends on them, because a range travels as two explicit dates.
///
/// Shared by the calendar and the timesheet on purpose: they are two views of
/// the same week, one chip apart, and a copy corrected in one of them would move
/// a reader between two different weeks wearing the same label.
DateTime weekStartFor(BuildContext context, DateTime day) {
  final first = MaterialLocalizations.of(context).firstDayOfWeekIndex;
  final delta = (day.weekday % 7 - first + 7) % 7;
  return addDays(day, -delta);
}

/// [day] shifted by whole calendar days, at local midnight.
///
/// Through the constructor rather than by adding a [Duration]: a duration is an
/// exact number of hours, so in a week that changes clocks it lands at 23:00 the
/// day before and a whole grid shifts by one column.
DateTime addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);
