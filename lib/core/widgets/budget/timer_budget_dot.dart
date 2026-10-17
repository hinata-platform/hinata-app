import 'package:flutter/material.dart';

import '../../models/time_usage_models.dart';
import '../../theme/app_type.dart';
import 'budget_style.dart';

/// The running timer's issue or project as a dot and a percent, for the timer
/// bar where every pixel of width is spoken for (HIN-151). The figure is always
/// there: the dot's colour only repeats it.
class TimerBudgetDot extends StatelessWidget {
  const TimerBudgetDot({
    super.key,
    required this.label,
    required this.gauge,
    this.format = budgetMinutes,
  });

  final String label;
  final BudgetGauge gauge;
  final BudgetAmountFormat format;

  @override
  Widget build(BuildContext context) {
    final level = gauge.level;
    return Semantics(
      label: BudgetStyle.semantics(context, label, gauge, format),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (level == BudgetLevel.over)
            Icon(
              BudgetStyle.icon(level),
              size: 12,
              color: BudgetStyle.ink(level),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: BudgetStyle.fill(level),
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 5),
          Text(
            BudgetStyle.percent(context, gauge),
            style: TextStyle(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w600,
              color: BudgetStyle.ink(level),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
