import 'package:flutter/material.dart';

import '../../models/time_usage_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import 'budget_style.dart';

/// A budget as one short figure: a gauge glyph and "80 %", for rows and heads
/// where a bar would not fit (HIN-151) — the project head on the board, the
/// project list, a Gantt row.
///
/// When [onTap] is set it is a button that leads to the full picture; the hit
/// area is 48 dp tall whatever the capsule's own height. The tooltip and the
/// semantics carry the sums the capsule leaves out.
class BudgetCapsule extends StatelessWidget {
  const BudgetCapsule({
    super.key,
    required this.label,
    required this.gauge,
    this.format = budgetMinutes,
    this.onTap,
  });

  final String label;
  final BudgetGauge gauge;
  final BudgetAmountFormat format;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final level = gauge.level;
    final ink = BudgetStyle.ink(level);
    final capsule = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: level == BudgetLevel.within
            ? AppColors.surfaceMuted
            : Color.alphaBlend(
                BudgetStyle.fill(level).withValues(alpha: 0.12),
                AppColors.surface,
              ),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: level == BudgetLevel.within
              ? AppColors.hairline
              : BudgetStyle.fill(level),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(BudgetStyle.icon(level), size: 13, color: ink),
          const SizedBox(width: 5),
          Text(
            BudgetStyle.percent(context, gauge),
            style: TextStyle(
              fontSize: AppType.caption,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    final tooltip =
        '${BudgetStyle.usedOfLimit(context, gauge, format)}, '
        '${BudgetStyle.remainder(context, gauge, format)}';
    return Semantics(
      button: onTap != null,
      label: BudgetStyle.semantics(context, label, gauge, format),
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: onTap == null
            ? capsule
            : InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(99),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Center(widthFactor: 1, child: capsule),
                ),
              ),
      ),
    );
  }
}
