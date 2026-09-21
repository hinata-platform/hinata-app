/// What an absence type is called, drawn with and coloured by — read in one
/// place, because the keeper's list, the balance card and the journal all have
/// to say the same thing about the same type.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/absence_models.dart';
import '../../core/theme/app_colors.dart';

/// The icons an absence type may carry, mirroring `TimeOffIcons.ALLOWED` in
/// hinata-server.
///
/// The server keeps the allow-list because the value is chosen by one person
/// and rendered by every client; this map is the other half of it. A name that
/// is not here draws the neutral mark rather than a hole — a server one version
/// ahead may already offer a fifteenth.
const Map<String, IconData> kAbsenceIcons = {
  'calendar-off': LucideIcons.calendarOff,
  'palmtree': LucideIcons.palmtree,
  'thermometer': LucideIcons.thermometer,
  'baby': LucideIcons.baby,
  'graduation-cap': LucideIcons.graduationCap,
  'heart-pulse': LucideIcons.heartPulse,
  'scale': LucideIcons.scale,
  'plane': LucideIcons.plane,
  'home': LucideIcons.house,
  'gavel': LucideIcons.gavel,
  'church': LucideIcons.church,
  'users': LucideIcons.users,
  'clock': LucideIcons.clock,
  'ban': LucideIcons.ban,
};

/// The icon for a stored name, or the neutral mark for one nobody knows.
IconData absenceIcon(String? name) =>
    kAbsenceIcons[name] ?? LucideIcons.calendarOff;

/// The colour of a type's hue, or the app's accent when it carries none.
///
/// Full saturation would put fourteen shouting dots in a list; this is the same
/// restraint the tag colours use, and it survives dark mode because the
/// lightness follows the theme rather than the stored value.
Color absenceColor(BuildContext context, int? hue) {
  if (hue == null) return AppColors.accentStrong;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return HSLColor.fromAHSL(
    1,
    (hue % 360).toDouble(),
    dark ? 0.52 : 0.58,
    dark ? 0.62 : 0.46,
  ).toColor();
}

/// Text and icon drawn on a pale wash of [absenceColor]: the same hue, dark
/// enough in light mode and light enough in dark mode to read on it (HIN-118).
Color absenceInk(BuildContext context, int? hue) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (hue == null) return dark ? AppColors.accent : AppColors.accentText;
  return HSLColor.fromAHSL(
    1,
    (hue % 360).toDouble(),
    dark ? 0.60 : 0.62,
    dark ? 0.80 : 0.22,
  ).toColor();
}

/// What a type is called: what an operator typed, or the translated label of a
/// built-in nobody renamed.
///
/// A built-in ships without a name on purpose — a name stored as data would
/// leave a German instance reading "Vacation" until somebody renamed three
/// rows — so the fallback is not a nicety, it is where the word comes from.
String absenceTypeName(BuildContext context, AbsenceType type) {
  final own = type.name?.trim() ?? '';
  if (own.isNotEmpty) return own;
  final key = type.systemLabelKey;
  if (key != null) return context.t(key);
  return context.t(type.kind.labelKey);
}

/// "3,5 Tage" — the amount with the grammatical number it deserves.
///
/// [count] is the grammatical selector, not the amount: i18next picks between
/// the key and its `_plural` sibling on one is/is-not-one decision, and 8.33
/// days is plural in every language that has the distinction.
String daysLabel(BuildContext context, int milliDays) => context.t(
  'absence.days',
  count: milliDays == kMilliDay ? 1 : 2,
  variables: {
    'days': formatDays(milliDays, decimalSeparator: _decimal(context)),
  },
);

/// The same with a sign in front, for a journal where the direction is the
/// point. A booking that took days away reads "−2", never "2".
String signedDaysLabel(BuildContext context, int milliDays) {
  final label = daysLabel(context, milliDays.abs());
  if (milliDays == 0) return label;
  // The typographic minus, not the hyphen: it lines up with the digits, which
  // is what a column of amounts is read down.
  return milliDays > 0 ? '+$label' : '−$label';
}

/// § 3 Abs. 1 BUrlG: four weeks of leave, whatever the working week looks like.
/// Mirrors `TimeOffLegalFloor.WEEKS` on the server.
const int kLegalLeaveWeeks = 4;

/// The week to assume where there is no person to ask about — the editor where a
/// quota is typed, not a balance. Mirrors `TimeOffLegalFloor.STANDARD_WORKING_DAYS`.
///
/// It is a figure to compare against, never one to decide with: whose week it
/// really is, only that person's pattern says, and the server computes the floor
/// per person and sends it with every balance.
const int kStandardWorkingDays = 5;

/// The statutory minimum for a week of [workingDaysPerWeek] days, in thousandths.
int legalMinimumMilliDays(int workingDaysPerWeek) =>
    workingDaysPerWeek.clamp(0, 7) * kLegalLeaveWeeks * kMilliDay;

/// The separator the reader's locale puts between the whole days and the rest.
/// A number of days, written the way the reader's locale writes numbers.
///
/// Every amount on a screen goes through this or through [daysLabel]. Calling
/// [formatDays] directly prints a full stop wherever the reader expects a
/// comma, which puts "8,33 Anspruch" beside "8.33 Rest" on the same card.
String days(BuildContext context, int milliDays) =>
    formatDays(milliDays, decimalSeparator: _decimal(context));

String _decimal(BuildContext context) =>
    const {
      'de',
      'es',
      'fr',
      'ru',
    }.contains(Localizations.localeOf(context).languageCode)
    ? ','
    : '.';

final Map<String, DateFormat> _spanFormats = {};

/// "15 – 19 Jun 2026", or one date where both ends are the same day.
///
/// One place for it: the request form, the sick report, the request card and
/// the absence sheet all name a span, and two copies had already drifted to
/// two formats once.
String spanLabel(BuildContext context, DateTime from, DateTime to) {
  // Kept per language rather than built per row: a list of absences calls this
  // once a card, and building a DateFormat parses its pattern each time.
  final format = _spanFormats.putIfAbsent(
    Localizations.localeOf(context).toLanguageTag(),
    () => DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()),
  );
  if (DateUtils.isSameDay(from, to)) return format.format(from);
  return '${format.format(from)} – ${format.format(to)}';
}

final Map<String, DateFormat> _dayFormats = {};

/// "31. März 2027": one day, written the way the reader's locale writes it —
/// for a deadline, where the year matters as much as the day.
String dayMonthLabel(BuildContext context, DateTime day) {
  final format = _dayFormats.putIfAbsent(
    Localizations.localeOf(context).toLanguageTag(),
    () => DateFormat.yMMMMd(Localizations.localeOf(context).toLanguageTag()),
  );
  return format.format(day);
}
