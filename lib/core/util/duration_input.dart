/// Reading a duration the way a person types it.
///
/// The field this backs is the fastest way into the app: somebody who knows
/// they worked an hour and a half types "1:30" or "1.5h" or "90m" and expects
/// all three to mean the same thing. Refusing two of the three because the
/// field wanted the other one is the kind of small friction that makes a
/// tracker go unused.
///
/// Deliberately *not* localized, and evenly so: the accepted words are the
/// ASCII unit abbreviations and their English expansions — `h`, `hr`, `hour`,
/// `m`, `min`, `minute` — which is what a duration field takes everywhere. It
/// used to accept `Stunden` and `Minuten` as well, which privileged one of the
/// nine languages the app speaks and left a French user's `1 heure` refused;
/// the abbreviations are what everyone types anyway. Both decimal separators
/// are accepted, because a German keyboard produces a comma.
///
/// What *is* localized is how a duration is shown — `fmtDuration`.
library;

/// Minutes meant by [input], or null when it says nothing usable.
///
/// Accepted, case- and space-insensitively:
///
/// * `90`, `90m`, `90 min`, `90 minutes` — plain minutes
/// * `2h`, `2 hrs`, `2 hours` — whole hours
/// * `1h30`, `1h 30m`, `1 h 30 min` — hours and minutes
/// * `1:30` — the clock notation
/// * `1.5h`, `1,5h`, `1.5` — fractional hours, rounded to the nearest minute
///
/// A bare number is minutes, not hours: on a form that logs work, "45" means
/// three quarters of an hour to everyone who has ever filled one in. A bare
/// *fractional* number is hours, because "1.5" minutes is not a thing anybody
/// means. And `1.30` is hours-with-a-decimal — an hour and 18 minutes — not
/// "1:30"; the colon is the notation for the latter and it is unambiguous,
/// which is why the two are kept apart rather than guessed between.
int? parseDurationInput(String? input) {
  if (input == null) return null;
  final text = input.trim().toLowerCase().replaceAll(',', '.');
  if (text.isEmpty) return null;

  // 1:30 — hours and minutes, the clock notation.
  final clock = RegExp(r'^(\d{1,3}):([0-5]?\d)$').firstMatch(text);
  if (clock != null) {
    return int.parse(clock.group(1)!) * 60 + int.parse(clock.group(2)!);
  }

  // 1h30, 1h 30m, 2h, 90m — a unit-tagged form. At least one unit must appear,
  // or "12" would parse here as 12 hours.
  final tagged = RegExp(
    r'^(?:(\d+(?:\.\d+)?)\s*(?:h|hrs?|hours?)'
    r'(?:\s*(\d{1,2})\s*(?:m|mins?|minutes?)?)?'
    r'|(\d+(?:\.\d+)?)\s*(?:m|mins?|minutes?))$',
  ).firstMatch(text);
  if (tagged != null) {
    if (tagged.group(3) != null) {
      return double.parse(tagged.group(3)!).round();
    }
    final hours = double.parse(tagged.group(1)!);
    final minutes = tagged.group(2) == null ? 0 : int.parse(tagged.group(2)!);
    // "1.5h 30m" is contradictory; the fraction wins and the trailing minutes
    // are added, which is the only reading that loses nothing.
    return (hours * 60).round() + minutes;
  }

  // A bare number: minutes if whole, hours if fractional.
  final bare = RegExp(r'^(\d+(?:\.\d+)?)$').firstMatch(text);
  if (bare != null) {
    final value = double.parse(bare.group(1)!);
    return value == value.roundToDouble()
        ? value.round()
        : (value * 60).round();
  }
  return null;
}

/// The plain text form of [minutes] for the field to hold — `1h 30m`, `45m`,
/// `2h`. Round-trips through [parseDurationInput].
///
/// Not for display: a person reads `fmtDuration`, which is localized. This is
/// what goes back into an input the person is about to edit, so it has to be in
/// the notation that input accepts.
String formatDurationInput(int minutes) {
  final safe = minutes < 0 ? 0 : minutes;
  final h = safe ~/ 60;
  final m = safe % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}
