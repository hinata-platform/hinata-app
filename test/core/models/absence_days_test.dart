import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/absence_models.dart';

/// Days travel as thousandths of a working day, the way the server stores them.
///
/// The arithmetic never happens here — a balance is the server's sum — but the
/// two conversions at the edges do, and both have a way of going quietly wrong.
/// A field that dropped the comma would turn two and a half days into
/// twenty-five, and a display that rounded 8.333 down would tell somebody they
/// have less leave than § 5 Abs. 2 BUrlG gave them.
void main() {
  group('showing an amount', () {
    test('a whole number of days carries no decimals', () {
      expect(formatDays(20 * kMilliDay), '20');
      expect(formatDays(0), '0');
    });

    test('half a day is half a day, not nought point five nought', () {
      expect(formatDays(500), '0.5');
      expect(formatDays(2500), '2.5');
    });

    test('a twelfth keeps two places rather than becoming a whole day', () {
      // Five twelfths of twenty days. Rounding it to 8 on the way in would be
      // telling somebody they are owed a third of a day less than they are.
      expect(formatDays(8333), '8.33');
    });

    test('a negative balance keeps its sign', () {
      expect(formatDays(-1500), '-1.5');
    });

    test('the separator follows the reader, not the storage', () {
      expect(formatDays(2500, decimalSeparator: ','), '2,5');
    });
  });

  group('reading an amount', () {
    test('both separators are accepted, because both keyboards exist', () {
      expect(parseDays('2.5'), 2500);
      expect(parseDays('2,5'), 2500);
    });

    test('an empty or unreadable field is nothing, never a crash', () {
      expect(parseDays(''), 0);
      expect(parseDays('   '), 0);
      expect(parseDays('abc'), 0);
    });

    test('a third of a day survives the round trip', () {
      expect(formatDays(parseDays('8,33')), '8.33');
    });
  });

  group('reading a correction', () {
    test('a minus in front takes days away', () {
      expect(parseSignedDays('-2,5'), -2500);
      // The typographic minus too: it is what the journal prints, so it is what
      // somebody copying a line back in will paste.
      expect(parseSignedDays('−2,5'), -2500);
    });

    test('without a sign it adds', () {
      expect(parseSignedDays('2,5'), 2500);
    });

    test('an ordinary amount can never be negative', () {
      // Only a correction may mean it. A quota of minus twenty is a typo.
      expect(parseDays('-20'), 20 * kMilliDay);
    });
  });
}
