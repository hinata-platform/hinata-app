import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/util/duration_input.dart';

/// What a person types into a duration field, and what it has to mean. The
/// interesting part is the ambiguity: a bare number, a decimal point, a colon.
void main() {
  group('the notations people actually type', () {
    test('plain minutes, tagged or not', () {
      expect(parseDurationInput('90'), 90);
      expect(parseDurationInput('90m'), 90);
      expect(parseDurationInput('90 min'), 90);
      expect(parseDurationInput('90 minutes'), 90);
    });

    test('whole hours', () {
      expect(parseDurationInput('2h'), 120);
      expect(parseDurationInput('2 hrs'), 120);
      expect(parseDurationInput('2 hours'), 120);
    });

    test('hours and minutes together', () {
      expect(parseDurationInput('1h30'), 90);
      expect(parseDurationInput('1h 30m'), 90);
      expect(parseDurationInput('1 h 30 min'), 90);
      expect(parseDurationInput('1H30M'), 90);
    });

    test('the clock notation', () {
      expect(parseDurationInput('1:30'), 90);
      expect(parseDurationInput('0:45'), 45);
      expect(parseDurationInput('12:05'), 725);
    });

    test('fractional hours, with either decimal separator', () {
      expect(parseDurationInput('1.5h'), 90);
      // A German keyboard types a comma and means the same thing.
      expect(parseDurationInput('1,5h'), 90);
      expect(parseDurationInput('0.25h'), 15);
      // Rounded to the nearest minute rather than refused.
      expect(parseDurationInput('1.33h'), 80);
    });
  });

  group('the ambiguous cases, decided once', () {
    test('a bare whole number is minutes', () {
      // On a form that logs work, "45" is three quarters of an hour to everyone
      // who has ever filled one in.
      expect(parseDurationInput('45'), 45);
      expect(parseDurationInput('8'), 8);
    });

    test('a bare fractional number is hours', () {
      // Nobody means one and a half minutes.
      expect(parseDurationInput('1.5'), 90);
      expect(parseDurationInput('0.5'), 30);
    });

    test('1.30 is a decimal hour and 1:30 is an hour and a half', () {
      // Kept apart rather than guessed between: the colon is the notation for
      // the clock reading, and it is unambiguous.
      expect(parseDurationInput('1.30'), 78);
      expect(parseDurationInput('1:30'), 90);
    });
  });

  group('what is not a duration', () {
    test('nothing, blanks and prose', () {
      for (final input in [
        null,
        '',
        '   ',
        'about an hour',
        'h',
        '-30',
        '1:99',
      ]) {
        expect(parseDurationInput(input), isNull, reason: '$input');
      }
    });

    test('a spelled-out unit in any one language, including German', () {
      // The field takes the ASCII abbreviations, which everybody types. It
      // used to also take `Stunden` and `Minuten`, which privileged one of the
      // nine languages the app speaks and left `1 heure` refused. Pinned here
      // so re-adding one language's words fails rather than passes.
      for (final input in ['2 Stunden', '45 Minuten', '1 heure', '2 horas']) {
        expect(parseDurationInput(input), isNull, reason: input);
      }
    });
  });

  group('round trip', () {
    test('what the field shows is what the field accepts', () {
      for (final minutes in [1, 5, 45, 60, 90, 125, 480, 1440]) {
        expect(
          parseDurationInput(formatDurationInput(minutes)),
          minutes,
          reason: '$minutes',
        );
      }
    });

    test('formatting never produces a negative or a stray zero', () {
      expect(formatDurationInput(0), '0m');
      expect(formatDurationInput(-5), '0m');
      expect(formatDurationInput(120), '2h');
      expect(formatDurationInput(61), '1h 1m');
    });
  });
}
