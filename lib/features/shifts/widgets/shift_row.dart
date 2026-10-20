import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/models/shift_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/hive_widgets.dart' show HiveAvatarStack;
import '../../../core/widgets/soft_card.dart';
import '../shift_texts.dart';
import 'coverage_hex.dart';

/// One shift as a row (HIN-44): the time on the left in Sora, what and where,
/// the coverage cell with its figure and glyph, the people, and on the right
/// (or below on a phone) the one thing to do.
///
/// No coloured edge: the state is in the cell, the glyph and the number. The
/// whole card opens the sheet ([onTap]); [trailing] is the action, which keeps
/// its own tap target.
class ShiftRow extends StatelessWidget {
  const ShiftRow({
    super.key,
    required this.shift,
    this.eventTitle,
    this.location,
    this.people = const [],
    this.avatars = const [],
    this.trailing,
    this.onTap,
    this.stacked = false,
    this.note,
    this.extra,
    this.day,
  });

  final Shift shift;

  /// The event's name; left out on the event's own page.
  final String? eventTitle;
  final String? location;

  /// Names of the people on it, where the reader may see them.
  final List<String> people;
  final List<String?> avatars;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// The action below the row rather than beside it (a phone).
  final bool stacked;

  /// A deadline the reader has to meet, in words, with a clock glyph
  /// ("Nachgerückt, bitte bis 18:00 bestätigen").
  final String? note;

  /// Drawn under the people: a planner's waiting list (HIN-162).
  final Widget? extra;

  /// The shift's day in words, for lists that are not grouped by day (the
  /// open shifts on "Meine"); without it two shifts of the same name on
  /// different days read as the same row twice.
  final String? day;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (day != null && day!.isNotEmpty) day!,
      if (eventTitle != null && eventTitle!.isNotEmpty) eventTitle!,
      if (location != null && location!.isNotEmpty) location!,
    ].join(' · ');
    final action = trailing;
    final timeStyle = TextStyle(
      fontFamily: AppTheme.fontBrand,
      fontSize: AppType.title,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final untilStyle = TextStyle(
      fontSize: AppType.caption,
      color: AppColors.inkFaint,
    );
    // From one and a half times the text size the time column would squeeze
    // the title to a sliver; it moves above the title instead.
    final large = MediaQuery.textScalerOf(context).scale(10) >= 15;
    final time = large
        ? Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(clockLabel(context, shift.startsLocal), style: timeStyle),
              Text(untilLabel(context, shift.endsLocal), style: untilStyle),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(clockLabel(context, shift.startsLocal), style: timeStyle),
              Text(untilLabel(context, shift.endsLocal), style: untilStyle),
            ],
          );
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!large) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72),
            child: time,
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (large) ...[time, const SizedBox(height: 4)],
              Text(
                shift.title,
                style: TextStyle(
                  fontSize: AppType.body,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              if (subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: AppType.label,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: ExcludeSemantics(
                          child: Icon(
                            LucideIcons.clockAlert,
                            size: 15,
                            color: AppColors.warningInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          note!,
                          style: TextStyle(
                            fontSize: AppType.label,
                            fontWeight: FontWeight.w600,
                            color: AppColors.warningInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  CoverageHex(coverage: shift.coverage),
                  if (people.isNotEmpty)
                    HiveAvatarStack(
                      names: people,
                      imageUrls: avatars,
                      size: 24,
                    ),
                ],
              ),
              ?extra,
            ],
          ),
        ),
        if (action != null && !stacked) ...[
          const SizedBox(width: 12),
          Flexible(child: action),
        ],
      ],
    );
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          if (action != null && stacked) ...[
            const SizedBox(height: 10),
            Align(alignment: AlignmentDirectional.centerEnd, child: action),
          ],
        ],
      ),
    );
  }
}

/// A day's header above its rows: `SA., 24. OKT.`
class ShiftSectionLabel extends StatelessWidget {
  const ShiftSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Semantics(
        header: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                text.toUpperCase(),
                style: TextStyle(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: AppColors.inkFaint,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  trailing!,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: AppType.caption,
                    color: AppColors.inkFaint,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
