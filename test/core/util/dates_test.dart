import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/util/dates.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' show DateFormat;

/// A list tells a date per row, and building a formatter parses its pattern:
/// one formatter per pattern and locale serves every row.
void main() {
  setUpAll(() => initializeDateFormatting('de'));

  test('the same pattern in the same language is one formatter', () {
    final first = dateFormatFor(DateFormat.ABBR_MONTH_DAY, 'de');

    expect(dateFormatFor(DateFormat.ABBR_MONTH_DAY, 'de'), same(first));
    expect(dateFormatFor(DateFormat.ABBR_MONTH_DAY, 'en'), isNot(same(first)));
    expect(first.format(DateTime(2026, 10, 22)), '22. Okt.');
  });
}
