import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Up to two marks under a day's number: a filled dot and a ring.
///
/// What a month or a week strip says about a day when it has no room to say
/// what is on it (HIN-160). The grid does not know what the two mean; the
/// caller does, and names them in [label] for a screen reader. Shift planning
/// uses the dot for "you have a shift" and the ring for "a shift still needs
/// people", which is the reading the legend under the calendar gives.
@immutable
class TimeDayDots {
  const TimeDayDots({this.dot = false, this.ring = false, required this.label});

  /// The filled mark.
  final bool dot;

  /// The outlined mark.
  final bool ring;

  /// What the marks say, in words, for whoever cannot see them.
  final String label;

  bool get isEmpty => !dot && !ring;

  @override
  bool operator ==(Object other) =>
      other is TimeDayDots &&
      other.dot == dot &&
      other.ring == ring &&
      other.label == label;

  @override
  int get hashCode => Object.hash(dot, ring, label);
}

/// Diameter of one mark.
const double kTimeDayDot = 6;

/// The marks of [dots] side by side, decorative: the label belongs to the day
/// they sit under.
class TimeDayDotsRow extends StatelessWidget {
  const TimeDayDotsRow({super.key, required this.dots});

  final TimeDayDots dots;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: kTimeDayDot + 2,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dots.dot)
            Container(
              width: kTimeDayDot,
              height: kTimeDayDot,
              decoration: BoxDecoration(
                color: AppColors.accentStrong,
                shape: BoxShape.circle,
              ),
            ),
          if (dots.dot && dots.ring) const SizedBox(width: 3),
          if (dots.ring)
            Container(
              width: kTimeDayDot,
              height: kTimeDayDot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.warningBar, width: 1.5),
              ),
            ),
        ],
      ),
    ),
  );
}
