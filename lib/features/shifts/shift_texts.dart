/// Every coverage, status and time text of the shift planning module, in one
/// place (HIN-44). The rows, the hero, the sheet and the event page all ask
/// here, so one shift never reads two ways on two surfaces.
library;

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/i18n/i18n.dart';
import '../../core/models/shift_models.dart';

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toLanguageTag();

/// `2 / 3`, or `4 / 3 · max. 5` where an upper limit differs from the need.
String coverageFigure(BuildContext context, Coverage c) {
  final max = c.max;
  if (max == null || max == c.required) {
    return context.t(
      'shifts.coverage.figure',
      variables: {'assigned': c.assigned, 'required': c.required},
    );
  }
  return context.t(
    'shifts.coverage.figureMax',
    variables: {'assigned': c.assigned, 'required': c.required, 'max': max},
  );
}

/// The state in words: who is missing, met, over, or full.
String coverageWords(BuildContext context, Coverage c) => switch (c.state) {
  CoverageState.under => context.t('shifts.coverage.missing', count: c.missing),
  CoverageState.met => context.t('shifts.coverage.met'),
  CoverageState.over => context.t(
    'shifts.coverage.over',
    count: c.assigned - c.required,
  ),
  CoverageState.full => context.t(
    'shifts.coverage.full',
    variables: {'assigned': c.assigned, 'max': c.max ?? c.assigned},
  ),
};

/// What a screen reader says for a coverage figure: count and state together.
String coverageSemantics(BuildContext context, Coverage c) => context.t(
  'shifts.coverage.semantics',
  variables: {
    'assigned': c.assigned,
    'required': c.required,
    'state': coverageWords(context, c),
  },
);

/// The status of the caller's place, as a badge says it.
String statusLabel(BuildContext context, ShiftAssignmentStatus status) =>
    context.t(switch (status) {
      ShiftAssignmentStatus.assigned => 'shifts.status.assigned',
      ShiftAssignmentStatus.confirmed => 'shifts.status.confirmed',
      ShiftAssignmentStatus.declined => 'shifts.status.declined',
      ShiftAssignmentStatus.released => 'shifts.status.released',
      ShiftAssignmentStatus.waiting => 'shifts.status.waiting',
      ShiftAssignmentStatus.unknown => 'shifts.status.mine',
    });

/// `Sa., 24. Okt.`
String dayLabel(BuildContext context, DateTime day) =>
    DateFormat.MMMEd(_locale(context)).format(day);

/// `18:00`
String clockLabel(BuildContext context, DateTime time) =>
    DateFormat.Hm(_locale(context)).format(time);

/// `bis 22:00`
String untilLabel(BuildContext context, DateTime end) => context.t(
  'shifts.time.until',
  variables: {'time': clockLabel(context, end)},
);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// `18:00 bis 22:00`, or with the days in front when it runs over midnight
/// into a day the reader has to be told about.
String spanLabel(BuildContext context, DateTime start, DateTime end) {
  if (_sameDay(start, end) ||
      // A night shift ending in the small hours reads as one evening.
      (end.difference(start).inHours < 24 &&
          !_sameDay(start, end) &&
          end.hour < 12 &&
          _sameDay(start.add(const Duration(days: 1)), end))) {
    return context.t(
      'shifts.time.span',
      variables: {
        'from': clockLabel(context, start),
        'to': clockLabel(context, end),
      },
    );
  }
  return context.t(
    'shifts.time.span',
    variables: {
      'from': '${dayLabel(context, start)}, ${clockLabel(context, start)}',
      'to': '${dayLabel(context, end)}, ${clockLabel(context, end)}',
    },
  );
}

/// An event's stretch: one day with times, or the days it spans.
String eventSpanLabel(BuildContext context, DateTime start, DateTime end) {
  if (_sameDay(start, end) || end.difference(start).inHours < 24) {
    return '${dayLabel(context, start)}, ${spanLabel(context, start, end)}';
  }
  return context.t(
    'shifts.time.span',
    variables: {'from': dayLabel(context, start), 'to': dayLabel(context, end)},
  );
}

/// `3 Std.`, `2 Std. 30 Min.`, `45 Min.`
String durationLabel(BuildContext context, Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final parts = [
    if (hours > 0) context.t('shifts.time.hours', count: hours),
    if (minutes > 0 || hours == 0)
      context.t('shifts.time.minutes', count: minutes),
  ];
  return parts.join(' ');
}

/// `in 18 Std.`, `in 3 Tagen`, or `läuft gerade` once it has begun.
String relativeStart(BuildContext context, DateTime start, DateTime now) {
  final d = start.difference(now);
  if (d.isNegative) return context.t('shifts.time.running');
  if (d.inMinutes < 60) {
    return context.t('shifts.time.inMinutes', count: d.inMinutes.clamp(1, 59));
  }
  if (d.inHours < 24) return context.t('shifts.time.inHours', count: d.inHours);
  return context.t('shifts.time.inDays', count: (d.inHours / 24).round());
}

/// The zone hint, or null when the device already reads the event's wall
/// clock. Decided without a zone database: where the instant on this device
/// and the wall clock the server sent disagree, the zones do too.
String? zoneHint(BuildContext context, Shift shift, String? timezone) {
  if (timezone == null || timezone.isEmpty) return null;
  final here = shift.startsAt;
  final there = shift.startsLocal;
  if (here.hour == there.hour &&
      here.minute == there.minute &&
      _sameDay(here, there)) {
    return null;
  }
  return context.t('shifts.zone', variables: {'zone': timezone});
}

/// `1 Schicht braucht noch Leute` or `Alles besetzt`.
String eventStaffingLabel(BuildContext context, int understaffed) =>
    understaffed > 0
    ? context.t('shifts.event.understaffed', count: understaffed)
    : context.t('shifts.event.allStaffed');
