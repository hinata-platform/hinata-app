/// Reading a decimal number the way a person types it into a money or an
/// hours field: `95`, `95,5`, `1.234,56`, `95.50`.
library;

/// Hundredths of the number in [raw], or null when it is no number.
///
/// Both separators are accepted, and the last one is the decimal mark only
/// when one or two digits follow it, so `1.000` is a thousand in every locale
/// and `7,5` is seven and a half. Spaces, including the no-break ones a copied
/// amount carries, are ignored. [unit], a pattern, may follow the number, the
/// way `h` follows a typed budget. A whole part longer than [maxWholeDigits]
/// is refused rather than overflowing.
int? parseHundredths(String raw, {String unit = '', int maxWholeDigits = 9}) {
  final text = raw.trim().replaceAll(RegExp(r'[\s  ]'), '');
  if (text.isEmpty) return null;
  final match = RegExp(
    '^(\\d[\\d.,]*?)(?:[.,](\\d{1,2}))?(?:$unit)?\$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  final whole = match.group(1)!.replaceAll(RegExp(r'[.,]'), '');
  if (whole.isEmpty || whole.length > maxWholeDigits) return null;
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return int.parse(whole) * 100 + int.parse(fraction);
}
