/// Reading a time of day the way a person types it.
///
/// The picker's wheels are for looking; typing is for knowing. Somebody who
/// started at half past nine types `9:30`, `0930` or `930` and expects all
/// three to mean the same thing, the way [parseDurationInput] reads `1:30`,
/// `90m` and `1.5h` alike.
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';

/// The time of day meant by [input], as `(hour, minute)` on a 24-hour clock, or
/// null when it says nothing usable.
///
/// Accepted, space-insensitively:
///
/// * `9`, `21` — a whole hour
/// * `930`, `0930`, `2130` — hour and minute without a separator
/// * `9:30`, `9.30`, `9h30` — with one
/// * any of those followed by a meridiem (`9:30 pm`, `9pm`), when
///   [meridiems] names the two words the locale uses — `am`/`pm` and `a`/`p`
///   are always understood
///
/// A meridiem makes the hour a twelve-hour one: `12 am` is midnight and
/// `12 pm` noon, and `13 pm` is refused rather than guessed at.
({int hour, int minute})? parseTimeInput(
  String? input, {
  ({String am, String pm})? meridiems,
}) {
  if (input == null) return null;
  var text = input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (text.isEmpty) return null;

  bool? afternoon;
  final am = <String>{'am', 'a', 'a.m.', ?meridiems?.am.toLowerCase()};
  final pm = <String>{'pm', 'p', 'p.m.', ?meridiems?.pm.toLowerCase()};
  // Longest first, so "a.m." is not read as "a" with ".m." left over.
  final words = [
    for (final word in am) (word, false),
    for (final word in pm) (word, true),
  ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));
  for (final (word, isPm) in words) {
    if (word.isNotEmpty && text.endsWith(word)) {
      afternoon = isPm;
      text = text.substring(0, text.length - word.length);
      break;
    }
  }

  int hour;
  int minute;
  final separated = RegExp(r'^(\d{1,2})[:.h](\d{1,2})$').firstMatch(text);
  final bare = RegExp(r'^\d{1,4}$').firstMatch(text);
  if (separated != null) {
    hour = int.parse(separated.group(1)!);
    minute = int.parse(separated.group(2)!);
  } else if (bare != null) {
    // One or two digits are an hour; three or four are an hour and a minute,
    // the minute being always the last two.
    if (text.length <= 2) {
      hour = int.parse(text);
      minute = 0;
    } else {
      hour = int.parse(text.substring(0, text.length - 2));
      minute = int.parse(text.substring(text.length - 2));
    }
  } else {
    return null;
  }
  if (minute > 59) return null;

  if (afternoon != null) {
    if (hour < 1 || hour > 12) return null;
    hour = hour % 12 + (afternoon ? 12 : 0);
  } else if (hour > 23) {
    return null;
  }
  return (hour: hour, minute: minute);
}

/// Writes a 24-hour time into shape as it is typed: `0930` reads `09:30`
/// before the last key is up, and so does `930`.
///
/// The colon comes by itself once the hour is whole — two digits, or one that
/// no hour continues (`9` can only be nine, so it becomes `09:`). A typed
/// colon, point or `h` ends the hour early (`1:` is one o'clock). A key that
/// would make the time impossible — a 25th hour, a 60th minute — is not
/// taken, so the field never shows something it will then refuse.
///
/// Deleting is left alone: backspace on `09:` gives `09`, not `09:` again.
class TimeInputFormatter extends TextInputFormatter {
  const TimeInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(' ', '');
    if (text.isEmpty) return newValue;
    if (!RegExp(r'^[\d:.h]+$').hasMatch(text)) return oldValue;
    final deleting = newValue.text.length < oldValue.text.length;

    final separator = text.indexOf(RegExp(r'[:.h]'));
    final digits = text.replaceAll(RegExp(r'\D'), '');
    final int hourLength;
    if (separator >= 0) {
      final before = text.substring(0, separator).replaceAll(RegExp(r'\D'), '');
      if (before.isEmpty || before.length > 2) return oldValue;
      hourLength = before.length;
    } else if (digits.isEmpty) {
      return oldValue;
    } else {
      hourLength = int.parse(digits[0]) > 2 ? 1 : math.min(2, digits.length);
    }
    var hour = digits.substring(0, hourLength);
    final minute = digits.substring(
      hourLength,
      math.min(digits.length, hourLength + 2),
    );
    if (digits.length > hourLength + 2) return oldValue;

    final hourWhole =
        separator >= 0 ||
        hour.length == 2 ||
        (hour.length == 1 && int.parse(hour) > 2) ||
        minute.isNotEmpty;
    if (hourWhole && hour.length == 1) hour = '0$hour';
    if (int.parse(hour) > 23) return oldValue;
    if (minute.isNotEmpty && int.parse(minute[0]) > 5) return oldValue;

    final shaped = !hourWhole
        ? hour
        : (minute.isEmpty && deleting && separator < 0)
        ? hour
        : '$hour:$minute';
    return TextEditingValue(
      text: shaped,
      selection: TextSelection.collapsed(offset: shaped.length),
    );
  }
}
