import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import 'time_day_dots.dart';

/// Height of the strip on its own.
const double kTimeWeekStrip = 52;

/// Height of the strip with a row of [TimeDayDots] under the numbers.
const double kTimeWeekStripWithDots = 64;

/// The seven days of the week the reader is in, with the one on screen marked.
///
/// A calendar's whole navigation on a phone: tapping a day goes to it, and
/// swiping the canvas below moves through them and on into the weeks either
/// side, which redraws this strip around the new day. Shared since HIN-160:
/// the time calendar draws it plain, shift planning with two marks a day
/// ([dotsOn]) for "you have a shift" and "a shift still needs people".
class TimeWeekStrip extends StatelessWidget {
  const TimeWeekStrip({
    super.key,
    required this.days,
    required this.focused,
    required this.today,
    required this.onTap,
    this.dotsOn,
  });

  final List<DateTime> days;
  final DateTime focused;
  final DateTime today;
  final void Function(DateTime day) onTap;

  /// The marks under a day's number, or null where the strip draws none.
  final TimeDayDots? Function(DateTime day)? dotsOn;

  @override
  Widget build(BuildContext context) {
    final narrow = MaterialLocalizations.of(context).narrowWeekdays;
    return Row(
      children: [
        for (final day in days)
          Expanded(
            child: TimeWeekStripDay(
              day: day,
              letter: narrow[day.weekday % 7],
              focused: DateUtils.isSameDay(day, focused),
              today: DateUtils.isSameDay(day, today),
              onTap: () => onTap(day),
              dots: dotsOn?.call(day),
              withDots: dotsOn != null,
            ),
          ),
      ],
    );
  }
}

/// One day of [TimeWeekStrip].
class TimeWeekStripDay extends StatelessWidget {
  const TimeWeekStripDay({
    super.key,
    required this.day,
    required this.letter,
    required this.focused,
    required this.today,
    required this.onTap,
    this.dots,
    this.withDots = false,
  });

  final DateTime day;
  final String letter;
  final bool focused;
  final bool today;
  final VoidCallback onTap;

  /// This day's marks; null for none.
  final TimeDayDots? dots;

  /// Whether the strip keeps a row for marks at all, so the numbers of every
  /// day stand on one line whether or not their day has one.
  final bool withDots;

  @override
  Widget build(BuildContext context) {
    final weekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    // Today is amber and the day you are reading is a filled disc. When they
    // are the same day the amber wins — it is the louder mark, and it is still
    // the day on screen.
    final Color disc;
    final Color ink;
    if (focused && today) {
      disc = AppColors.accentStrong;
      ink = _stripOnAccent;
    } else if (focused) {
      disc = AppColors.ink;
      ink = AppColors.surface;
    } else {
      disc = Colors.transparent;
      ink = today
          ? AppColors.accentStrong
          : (weekend ? AppColors.inkFaint : AppColors.ink);
    }
    final marks = dots;
    final date = MaterialLocalizations.of(context).formatFullDate(day);
    // Read out as the whole date: the letter and the number alone say "M 6".
    // The subtree is excluded, so the node carries the tap itself.
    return Semantics(
      button: true,
      selected: focused,
      label: marks == null || marks.isEmpty ? date : '$date, ${marks.label}',
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        // The strip is docked at a fixed height. At a large text scale the
        // letter and the disc shrink back into it instead of being cut off;
        // at the usual scale they fit and nothing is scaled.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                letter,
                style: TextStyle(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkFaint,
                ),
              ),
              const SizedBox(height: 3),
              DecoratedBox(
                decoration: BoxDecoration(color: disc, shape: BoxShape.circle),
                // At least 26 across, and more when the number grows.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                  child: Align(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: AppType.body,
                        fontWeight: focused || today
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  ),
                ),
              ),
              if (withDots) ...[
                const SizedBox(height: 3),
                SizedBox(
                  height: kTimeDayDot + 2,
                  child: marks == null || marks.isEmpty
                      ? null
                      : TimeDayDotsRow(dots: marks),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ink on the amber disc: white, which reads on the honey in both themes. Fixed
/// rather than a theme token, because the disc does not change with the theme.
const Color _stripOnAccent = Colors.white;
