import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/soft_card.dart';
import '../shift_texts.dart';
import 'coverage_hex.dart';

/// One event in the list (HIN-44): the cell with places taken over places
/// needed, the title, when and where, and the staffing in words.
///
/// A cancelled event is dimmed and says so; no coloured edge for any state.
class ShiftEventCard extends StatelessWidget {
  const ShiftEventCard({super.key, required this.event, this.onTap});

  final ShiftEventSummary event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final coverage = event.coverage;
    final understaffed = event.shiftsUnderstaffed > 0;
    final places = context.t(
      'shifts.event.places',
      variables: {'taken': event.placesTaken, 'required': event.placesRequired},
    );
    final staffing = eventStaffingLabel(context, event.shiftsUnderstaffed);
    final when = eventSpanLabel(context, event.startsLocal, event.endsLocal);
    final where = [when, if (event.location != null) event.location!];
    final series = seriesLine(
      context,
      seriesId: event.seriesId,
      recurrenceLabel: event.recurrenceLabel,
      detached: event.detached,
    );
    final large = context.largeText;
    final card = SoftCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Flex(
        // From one and a half times the text size the cell sits above the
        // title, which keeps the whole width for its words.
        direction: large ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HoneyCell(
            fill: coverage.fill,
            label: '${event.placesTaken}/${event.placesRequired}',
            size: 48,
            warning: understaffed && !event.cancelled,
            capped:
                !understaffed &&
                event.placesRequired > 0 &&
                event.placesTaken >= event.placesRequired,
          ),
          if (large) const SizedBox(height: 10) else const SizedBox(width: 14),
          Flexible(
            flex: large ? 0 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: TextStyle(
                    fontSize: AppType.title,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  where.join(' · '),
                  style: TextStyle(
                    fontSize: AppType.label,
                    color: AppColors.inkSoft,
                  ),
                ),
                if (series != null) ...[
                  const SizedBox(height: 3),
                  _Tag(
                    icon: LucideIcons.repeat,
                    text: series,
                    color: AppColors.inkSoft,
                    weight: FontWeight.w400,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (event.cancelled)
                      _Tag(
                        icon: LucideIcons.ban,
                        text: context.t('shifts.event.cancelled'),
                        color: AppColors.inkSoft,
                      )
                    else ...[
                      Text(
                        places,
                        style: TextStyle(
                          fontSize: AppType.label,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      _Tag(
                        icon: understaffed
                            ? LucideIcons.triangleAlert
                            : LucideIcons.check,
                        text: staffing,
                        color: understaffed
                            ? AppColors.warningInk
                            : AppColors.successInk,
                      ),
                    ],
                    if (event.mineCount > 0)
                      Text(
                        context.t('shifts.event.mine', count: event.mineCount),
                        style: TextStyle(
                          fontSize: AppType.label,
                          color: AppColors.inkFaint,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (!large) const SizedBox(width: 8),
          if (!large)
            ExcludeSemantics(
              child: Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: AppColors.inkFaint,
              ),
            ),
        ],
      ),
    );
    // One announcement per card, with the card's own tap on it.
    return MergeSemantics(
      child: Opacity(opacity: event.cancelled ? 0.62 : 1, child: card),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.icon,
    required this.text,
    required this.color,
    this.weight = FontWeight.w600,
  });

  final IconData icon;
  final String text;
  final Color color;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          text,
          style: TextStyle(
            fontSize: AppType.label,
            fontWeight: weight,
            color: color,
          ),
        ),
      ),
    ],
  );
}
