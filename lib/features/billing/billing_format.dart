import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../core/util/decimal_input.dart';

/// How money, hours and shares read in billing (HIN-96): in the reader's
/// locale, with the instance's one currency. Amounts arrive in cents.

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toLanguageTag();

/// [cents] in [currency], localized: `1.234,56 €`, `€1,234.56`.
String formatMoney(BuildContext context, int cents, String currency) =>
    NumberFormat.simpleCurrency(
      locale: _locale(context),
      name: currency,
    ).format(cents / 100);

/// [minutes] as decimal hours with two places, localized: `1,50`.
String formatHours(BuildContext context, int minutes) =>
    NumberFormat.decimalPatternDigits(
      locale: _locale(context),
      decimalDigits: 2,
    ).format(minutes / 60);

/// A share in permille as a percentage, one place at most: `42,5 %`.
String formatPermille(BuildContext context, int? permille) {
  if (permille == null) return '–';
  final number = NumberFormat.decimalPatternDigits(
    locale: _locale(context),
    decimalDigits: permille % 10 == 0 ? 0 : 1,
  ).format(permille / 10);
  return '$number\u00a0%';
}

/// A tax rate in basis points as typed in a field: `19`, `7,5`.
String basisPointsText(BuildContext context, int basisPoints) {
  if (basisPoints == 0) return '';
  return NumberFormat.decimalPatternDigits(
    locale: _locale(context),
    decimalDigits: basisPoints % 100 == 0 ? 0 : 2,
  ).format(basisPoints / 100);
}

/// The currency's symbol, for a field's prefix.
String currencySymbol(BuildContext context, String currency) =>
    NumberFormat.simpleCurrency(
      locale: _locale(context),
      name: currency,
    ).currencySymbol;

/// Cents from what somebody typed — `95`, `95,5`, `1.234,56`, `95.50` — or
/// null when it is no amount. Both separators are accepted, the last one is
/// the decimal mark when it is followed by one or two digits.
int? parseCents(String raw) => parseHundredths(raw);

/// Basis points from a typed percentage (`19`, `7,5`), or null.
int? parseBasisPoints(String raw) {
  final cents = parseCents(raw);
  if (cents == null || cents > 10000) return null;
  return cents;
}
