import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_report_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/hue_colors.dart';

/// Words and colours the report views share (HIN-93).

/// The hues a report's series are drawn in, in order: the honey of the brand
/// first, then hues far enough apart to tell neighbours apart. All at the same
/// lightness ([hueColor]), so no series reads as louder than another and each
/// clears 3:1 against the card (measured, `hin-93-review/contrast_*`).
const _seriesHues = [70, 250, 155, 300, 200, 340, 110, 25];

Color seriesColor(int index) =>
    hueColor(_seriesHues[index % _seriesHues.length]);

/// The colour of a group at [index]: a series hue, or a neutral grey for the
/// group of what has none — "no project" is not a project and must not look
/// like one, least of all in a hue that reads as a warning.
Color groupColor(ReportGroup group, int index, {int series = 8}) =>
    group.key == null || index >= series
    ? AppColors.inkFaint
    : seriesColor(index);

/// How much the reader enlarged text, for widths that hold text: a column that
/// fits "25 h 45 min" at 100 % must fit it at 200 %.
double textFactor(BuildContext context) =>
    (MediaQuery.textScalerOf(context).scale(10) / 10).clamp(1.0, 2.0);

/// A bucket's day on a chart axis, short enough for a phone: "1.9.", "Sep".
String axisLabel(
  BuildContext context,
  ReportGroupBy groupBy,
  ReportGroup group,
) {
  final day = group.day;
  if (day == null) return group.key ?? '';
  final locale = Localizations.localeOf(context).toLanguageTag();
  return groupBy == ReportGroupBy.month
      ? DateFormat.MMM(locale).format(day)
      : DateFormat.Md(locale).format(day);
}

/// What a group reads as: a name, the day a bucket starts, or "no project".
String groupLabel(
  BuildContext context,
  ReportGroupBy groupBy,
  ReportGroup group,
) {
  if (group.key == null) {
    return context.t('time.reports.none.${groupBy.wire.toLowerCase()}');
  }
  final locale = Localizations.localeOf(context).toLanguageTag();
  if (groupBy.time) {
    final day = group.day;
    if (day == null) return group.key!;
    return switch (groupBy) {
      ReportGroupBy.month => DateFormat.yMMMM(locale).format(day),
      ReportGroupBy.week => context.t(
        'time.reports.weekOf',
        variables: {'day': DateFormat.MMMd(locale).format(day)},
      ),
      _ => DateFormat.MMMEd(locale).format(day),
    };
  }
  return group.label ?? group.key!;
}

/// The second line of a group: a project's key, an issue's readable id.
String? groupDetail(ReportGroupBy groupBy, ReportGroup group) =>
    switch (groupBy) {
      ReportGroupBy.project ||
      ReportGroupBy.issue ||
      ReportGroupBy.team => group.detail,
      _ => null,
    };

/// The window of a query as the reader reads it: "1.–31. Sep. 2026".
String windowLabel(BuildContext context, DateTime from, DateTime to) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  if (from == to) return DateFormat.yMMMd(locale).format(from);
  if (from.year == to.year && from.month == to.month) {
    return '${DateFormat.d(locale).format(from)}–'
        '${DateFormat.yMMMd(locale).format(to)}';
  }
  final year = from.year == to.year;
  return '${(year ? DateFormat.MMMd(locale) : DateFormat.yMMMd(locale)).format(from)}'
      ' – ${DateFormat.yMMMd(locale).format(to)}';
}

/// A signed difference in hours and minutes: "+3 h 30 min", "−22 h".
String signedDuration(
  BuildContext context,
  int minutes,
  String Function(int) format,
) {
  if (minutes == 0) return format(0);
  return '${minutes > 0 ? '+' : '−'}${format(minutes.abs())}';
}
