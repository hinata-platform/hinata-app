import 'package:flutter/material.dart';

import '../../models/time_usage_models.dart';
import '../../theme/app_type.dart';
import 'budget_meter.dart' show HoneyTubePainter;
import 'budget_style.dart';

/// The running timer's issue or project as a tiny honey tube and a percent,
/// for the timer bar where every pixel of width is spoken for (HIN-151). The
/// figure is always there; the tube only repeats it.
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
          SizedBox(
            width: 30,
            height: 10,
            child: Transform.flip(
              flipX: Directionality.of(context) == TextDirection.rtl,
              child: CustomPaint(
                painter: HoneyTubePainter(
                  fill: gauge.fraction.clamp(0.0, 1.0),
                  level: level,
                  nearAt: gauge.nearPercent / 100,
                  dark: Theme.of(context).brightness == Brightness.dark,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            BudgetStyle.percent(context, gauge),
            style: TextStyle(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w700,
              color: BudgetStyle.ink(level),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
