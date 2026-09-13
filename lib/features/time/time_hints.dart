import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/time_privacy_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_widgets.dart' show fmtDuration;

/// One self-hint as a small chip, with the whole sentence on its tooltip.
///
/// Drawn in the list's own grey, the way the lock chip is, and never in a
/// warning colour. A long day, a short rest or a late entry is something the
/// person may want to know, not a mistake: recording late is allowed and better
/// than not recording at all (§ 16 Abs. 2 ArbZG), and nobody but the person ever
/// sees the chip.
class TimeHintChip extends StatelessWidget {
  const TimeHintChip({super.key, required this.hint});

  final TimeHint hint;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: timeHintSentence(context, hint),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hint.isLateEntry ? LucideIcons.clockAlert : LucideIcons.info,
              size: 11,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            // Flexible, so a label longer than the room left in a narrow row
            // ends in an ellipsis instead of a striped band; the tooltip still
            // carries the whole sentence.
            Flexible(
              child: Text(
                timeHintLabel(context, hint),
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
    );
  }
}

/// The chip's word or two. [TimeHint.kind] is one the repository already checked
/// against the kinds this build knows, so the key it builds always exists.
String timeHintLabel(BuildContext context, TimeHint hint) => hint.isLateEntry
    ? context.t('time.hint.chip.LATE_ENTRY', count: hint.daysLate ?? 0)
    : context.t('time.hint.chip.${hint.kind}');

/// The whole sentence, with the figure the hint carries.
String timeHintSentence(BuildContext context, TimeHint hint) =>
    switch (hint.kind) {
      'DAILY_MAXIMUM' => context.t(
        'time.hint.sentence.DAILY_MAXIMUM',
        variables: {'duration': fmtDuration(context, hint.minutes)},
      ),
      'SHORT_REST' => context.t(
        'time.hint.sentence.SHORT_REST',
        variables: {'duration': fmtDuration(context, hint.restMinutes)},
      ),
      'LATE_ENTRY' => context.t(
        'time.hint.sentence.LATE_ENTRY',
        count: hint.daysLate ?? 0,
      ),
      _ => context.t('time.hint.sentence.${hint.kind}'),
    };
