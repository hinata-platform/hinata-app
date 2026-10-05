import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/time_privacy_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_widgets.dart' show fmtDuration;
import '../../core/theme/app_type.dart';

/// "3 events from today not taken over yet" at the top of the list (HIN-94).
///
/// The list's own grey, like the hints: a suggestion, not a debt. Tapping it
/// goes to the calendar, where the events are; the cross puts it away for the
/// session.
class OpenCalendarEventsChip extends StatelessWidget {
  const OpenCalendarEventsChip({
    super.key,
    required this.count,
    required this.onOpen,
    required this.onDismiss,
  });

  final int count;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final label = context.t(
      'time.calendarEvents.openToday',
      count: count,
      variables: {'count': '$count'},
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.hairline2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Semantics(
                  button: true,
                  child: InkWell(
                    onTap: onOpen,
                    borderRadius: BorderRadius.circular(999),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 14,
                          end: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.calendarSync,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: AppType.caption,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: context.t('time.calendarEvents.dismissChip'),
                onPressed: onDismiss,
                icon: Icon(
                  LucideIcons.x,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
                  fontSize: AppType.caption,
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
