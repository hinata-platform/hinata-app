import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../../models/time_usage_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_type.dart';
import 'budget_style.dart';

/// What a budget or an estimate is, said in the form where time is being
/// recorded (HIN-151).
///
/// Shown only from the warning share on; below it the form stays quiet. It has
/// no button and asks nothing: recording time is never refused over a budget
/// (§ 16 Abs. 2 ArbZG), so the save button stays the one action. It is a live
/// region, so a screen reader hears it appear when a project is picked.
///
/// The same shape as `LockNotice` — glyph, one sentence in bold, one that
/// explains — so a form that shows both does not speak in two vocabularies.
class BudgetNotice extends StatelessWidget {
  const BudgetNotice({
    super.key,
    required this.kind,
    required this.subject,
    required this.gauge,
    this.format = budgetMinutes,
    this.compact = false,
  });

  final BudgetNoticeKind kind;

  /// What the limit belongs to: a project's name or an issue's key.
  final String subject;
  final BudgetGauge gauge;
  final BudgetAmountFormat format;

  /// Drops the explaining sentence, for a timesheet cell.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final level = gauge.level;
    if (level == BudgetLevel.within) return const SizedBox.shrink();
    final over = level == BudgetLevel.over;
    final ink = BudgetStyle.ink(level);
    final title = gauge.reached
        ? context.t('budget.notice.${kind.key}.reachedTitle')
        : over
        ? context.t('budget.notice.${kind.key}.overTitle')
        : context.t(
            'budget.notice.${kind.key}.nearTitle',
            variables: {'amount': format(context, gauge.left)},
          );
    final body = context.t(
      over ? 'budget.notice.overBody' : 'budget.notice.nearBody',
      variables: {
        'subject': subject,
        'sums': BudgetStyle.usedOfLimit(context, gauge, format),
      },
    );
    return Semantics(
      container: true,
      liveRegion: true,
      label: compact ? title : '$title. $body',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.all(compact ? 10 : 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            BudgetStyle.fill(level).withValues(alpha: 0.08),
            AppColors.surfaceMuted,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: BudgetStyle.fill(level)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(BudgetStyle.icon(level), size: 17, color: ink),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: AppType.label,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: AppType.caption,
                        height: 1.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which limit a notice speaks about; picks its title sentences.
enum BudgetNoticeKind {
  projectBudget('project'),
  issueEstimate('estimate'),
  sprintBudget('sprint');

  const BudgetNoticeKind(this.key);
  final String key;
}
