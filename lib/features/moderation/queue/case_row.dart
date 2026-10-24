import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_case_models.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../report/report_reasons.dart' show reportCategoryTitle;
import '../widgets/case_look.dart';

/// One case in a list of the moderation page (HIN-174): the cell, the
/// category and how long it waited; below, what was reported or that it is
/// covered; below that, where and how it came. No red flag, no coloured edge.
class CaseRow extends StatelessWidget {
  const CaseRow({
    super.key,
    required this.summary,
    required this.now,
    required this.onTap,
    this.selected = false,
    this.meId,
  });

  final CaseSummary summary;
  final DateTime now;
  final VoidCallback onTap;
  final bool selected;

  /// The reader, so a case they hold says "Bei dir" instead of a name.
  final String? meId;

  @override
  Widget build(BuildContext context) {
    final c = summary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final category = reportCategoryTitle(context, c.category);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? AppColors.accentSoft.withValues(alpha: dark ? .35 : .6)
            : AppColors.surface.withValues(alpha: dark ? .55 : .78),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CaseHex(summary: c, size: 26, words: false),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            category,
                            style: TextStyle(
                              fontSize: AppType.label,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          if (c.state.undecided)
                            CaseAgeChip(summary: c, now: now),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _Excerpt(summary: c),
                const SizedBox(height: 8),
                Text(
                  _meta(context),
                  style: TextStyle(
                    fontSize: AppType.caption,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Kind, place, how it came, and whose it is.
  String _meta(BuildContext context) {
    final c = summary;
    final location = c.location;
    return [
      contentKindWord(context, c.kind),
      ?location,
      if (c.sources.contains(ReportSource.automated) && c.reportCount == 0)
        context.t('moderation.queue.automated')
      else
        context.t('moderation.queue.reports', count: c.reportCount),
      if (c.sources.contains(ReportSource.ownInitiative))
        context.t('moderation.queue.ownInitiative'),
      if (c.assignee case final assignee? when c.state == CaseState.inReview)
        assignee.id == meId
            ? context.t('moderation.queue.withYou')
            : assignee.displayName,
      if (c.reportedByMe) context.t('moderation.queue.reportedByMe'),
    ].join(' · ');
  }
}

/// What was reported, two lines of it; covered for sexual content and the
/// safety of children, and for a report without an account.
class _Excerpt extends StatelessWidget {
  const _Excerpt({required this.summary});

  final CaseSummary summary;

  @override
  Widget build(BuildContext context) {
    final excerpt = summary.listExcerpt;
    if (excerpt != null && !summary.sensitive) {
      return Text(
        excerpt,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: AppType.label,
          height: 1.4,
          color: AppColors.ink,
        ),
      );
    }
    if (!summary.state.undecided) return const SizedBox.shrink();
    final file =
        summary.kind == ContentKind.attachment ||
        summary.kind == ContentKind.person;
    return Row(
      children: [
        Icon(LucideIcons.eyeOff, size: 15, color: AppColors.inkSoft),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.t(
              file
                  ? 'moderation.queue.imageCovered'
                  : 'moderation.queue.textCovered',
            ),
            style: TextStyle(
              fontSize: AppType.label,
              fontStyle: FontStyle.italic,
              color: AppColors.inkSoft,
            ),
          ),
        ),
      ],
    );
  }
}
