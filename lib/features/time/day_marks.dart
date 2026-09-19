import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/availability_models.dart';
import '../../core/theme/app_colors.dart';

/// The words and the mark of a marked day (HIN-91): a holiday, an absence, or a
/// day without planned hours.
///
/// A tone and a sentence, and never a warning. Recording time on such a day is
/// as open as on any other (R9): § 9 ArbZG forbids the work, not its record. The
/// tone is [AppColors.recess], the weekend's quiet wash, so a marked day never
/// speaks the language of a frozen one ([AppColors.closed] and a padlock).

/// The sentence for [mark]: "Holiday: Christmas Day", "Away: Vacation",
/// "Not a regular working day".
String dayMarkLabel(BuildContext context, DayMark mark) => switch (mark.kind) {
  DayMarkKind.holiday => context.t(
    mark.halfDay
        ? 'availability.mark.holidayHalf'
        : 'availability.mark.holiday',
    variables: {'name': mark.name ?? ''},
  ),
  DayMarkKind.absence => context.t(
    mark.halfDay ? 'availability.mark.absentHalf' : 'availability.mark.absent',
    variables: {
      'type': context.t((mark.absenceType ?? TimeOffType.other).labelKey),
    },
  ),
  DayMarkKind.nonRegular => context.t('availability.mark.nonRegular'),
};

IconData dayMarkIcon(DayMark mark) => switch (mark.kind) {
  DayMarkKind.holiday => LucideIcons.calendarHeart,
  DayMarkKind.absence => timeOffIcon(mark.absenceType ?? TimeOffType.other),
  DayMarkKind.nonRegular => LucideIcons.calendarOff,
};

IconData timeOffIcon(TimeOffType type) => switch (type) {
  TimeOffType.vacation => LucideIcons.treePalm,
  TimeOffType.sick => LucideIcons.thermometer,
  TimeOffType.other => LucideIcons.calendarOff,
};

/// A marked day as a small chip beside the day, the size of a hint chip.
class DayMarkChip extends StatelessWidget {
  const DayMarkChip({super.key, required this.mark, this.onTap});

  final DayMark mark;

  /// Opens what the mark is about — an absence opens its sheet. Null draws a
  /// chip that only says.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = dayMarkLabel(context, mark);
    return _Tappable(
      onTap: onTap,
      child: Tooltip(
        message: label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.recess,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.hairline2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(dayMarkIcon(mark), size: 11, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A chip that opens something when there is something to open, and stays a
/// plain label otherwise — with the pointer that says which.
class _Tappable extends StatelessWidget {
  const _Tappable({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    if (tap == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: tap, child: child),
    );
  }
}

/// A day inside an absence somebody asked for and nobody has decided yet
/// (HIN-117).
///
/// Its own chip rather than a [DayMarkChip]: a marking says what the day *is*,
/// and this says what it may turn out to be. The hourglass is the same glyph the
/// calendar puts beside such a date, and the tone is the accent rather than
/// [AppColors.closed] — nothing is frozen here and time is recorded on the day
/// like on any other (R9).
class RequestedDayChip extends StatelessWidget {
  const RequestedDayChip({super.key, this.onTap});

  /// Opens the request the day belongs to.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = context.t('absence.calendar.requested');
    return _Tappable(
      onTap: onTap,
      child: Tooltip(
        message: context.t('absence.calendar.requestedHint'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.accentStrong.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.accentStrong.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.hourglass,
                size: 11,
                color: AppColors.accentStrong,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentStrong,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A span of days as a reader says it: one day, or first and last.
String formatDaySpan(BuildContext context, DateTime from, DateTime to) {
  final localizations = MaterialLocalizations.of(context);
  if (DateUtils.isSameDay(from, to)) {
    return localizations.formatMediumDate(from);
  }
  return '${localizations.formatShortDate(from)} – '
      '${localizations.formatShortDate(to)}';
}
