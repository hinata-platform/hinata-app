import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../../models/time_usage_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_type.dart';
import 'budget_meter.dart' show HoneyTubePainter, OverflowCapsule;
import 'budget_style.dart';
import 'honey_glass.dart';

/// What a budget or an estimate does with the entry being typed, said in the
/// form before it is saved (HIN-151, "Honigstand").
///
/// A frosted strip with a small honey tube: what is recorded already in solid
/// honey, this entry as translucent hatched honey after it, and the level it
/// will leave in one line. It appears from the warning share on, counting the
/// entry, and stays quiet below.
///
/// It asks nothing and has no button: recording time is never refused over a
/// budget (§ 16 Abs. 2 ArbZG), so the save button stays the one action. It is
/// a live region, so a screen reader hears it when it appears.
///
/// Frosted rather than refractive: it lives inside a sheet that is glass
/// already.
class BudgetNotice extends StatelessWidget {
  const BudgetNotice({
    super.key,
    required this.kind,
    required this.subject,
    required this.gauge,
    this.pending = 0,
    this.format = budgetMinutes,
    this.compact = false,
  });

  final BudgetNoticeKind kind;

  /// What the limit belongs to: a project's name or an issue's key.
  final String subject;

  /// What is recorded already, without the entry in the form.
  final BudgetGauge gauge;

  /// The entry in the form, in the gauge's unit; zero when there is none yet.
  final int pending;
  final BudgetAmountFormat format;

  /// Drops the explaining line, for a timesheet cell.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final after = BudgetGauge(
      used: gauge.used + pending,
      limit: gauge.limit,
      nearPercent: gauge.nearPercent,
    );
    final level = after.level;
    if (level == BudgetLevel.within) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = BudgetStyle.ink(level);
    final title = after.reached
        ? context.t('budget.notice.${kind.key}.reachedTitle')
        : level == BudgetLevel.over
        ? context.t('budget.notice.${kind.key}.overTitle')
        : context.t(
            'budget.notice.${kind.key}.nearTitle',
            variables: {'amount': format(context, after.left)},
          );
    final body = context.t(
      level == BudgetLevel.over
          ? 'budget.notice.overBody'
          : 'budget.notice.nearBody',
      variables: {
        'subject': subject,
        'sums': BudgetStyle.usedOfLimit(context, after, format),
      },
    );
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final percent = Text(
      BudgetStyle.percent(context, after),
      style: TextStyle(
        fontFamily: AppTheme.fontBrand,
        fontSize: AppType.body,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    );
    final heading = Text(
      title,
      style: TextStyle(
        fontSize: AppType.label,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
    );
    return Semantics(
      container: true,
      liveRegion: true,
      label: compact ? title : '$title. $body',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          12,
          compact ? 9 : 11,
          12,
          compact ? 9 : 12,
        ),
        decoration: BoxDecoration(
          color: HoneyGlass.frost(dark),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: HoneyGlass.rim(dark)),
          boxShadow: [
            BoxShadow(
              color: HoneyGlass.liquid(
                level,
              )[1].withValues(alpha: dark ? 0.22 : 0.18),
              blurRadius: 18,
              spreadRadius: -6,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(BudgetStyle.icon(level), size: 16, color: ink),
                ),
                const SizedBox(width: 8),
                Expanded(
                  // At a large text size the figure moves under the sentence
                  // instead of squeezing it until a word breaks.
                  child: stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [heading, percent],
                        )
                      : heading,
                ),
                if (!stacked) ...[const SizedBox(width: 8), percent],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 14,
                    child: Transform.flip(
                      flipX: Directionality.of(context) == TextDirection.rtl,
                      child: CustomPaint(
                        painter: HoneyTubePainter(
                          fill: gauge.fraction.clamp(0.0, 1.0),
                          pendingTo: after.fraction.clamp(0.0, 1.0),
                          level: level,
                          nearAt: gauge.nearPercent / 100,
                          dark: dark,
                        ),
                      ),
                    ),
                  ),
                ),
                if (after.overBy > 0) ...[
                  const SizedBox(width: 6),
                  OverflowCapsule(text: '+${format(context, after.overBy)}'),
                ],
              ],
            ),
            if (!compact) ...[
              const SizedBox(height: 7),
              Text(
                body,
                style: TextStyle(
                  fontSize: AppType.caption,
                  height: 1.45,
                  color: AppColors.inkSoft,
                ),
              ),
              if (pending > 0) ...[
                const SizedBox(height: 2),
                Text(
                  context.t(
                    'budget.pending',
                    variables: {'amount': format(context, pending)},
                  ),
                  style: TextStyle(
                    fontSize: AppType.caption,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
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
