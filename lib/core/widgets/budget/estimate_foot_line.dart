import 'package:flutter/widgets.dart';

import '../../models/time_usage_models.dart';
import 'budget_style.dart';
import 'honey_glass.dart';

/// Spent against the estimate along the foot of a timeline bar (HIN-152): a
/// honey line, amber from the warning share, ember past the estimate. The
/// Gantt chart and the board's timeline draw the same one. A direct child of
/// the bar's [Stack].
class EstimateFootLine extends StatelessWidget {
  const EstimateFootLine({super.key, required this.gauge});

  final BudgetGauge gauge;

  /// The line's tooltip sentence: "Estimate: 40 % · 2 h left".
  static String tooltip(
    BuildContext context,
    BudgetGauge gauge,
    String label,
  ) =>
      '$label: ${BudgetStyle.percent(context, gauge)} · '
      '${BudgetStyle.remainder(context, gauge, budgetMinutes)}';

  @override
  Widget build(BuildContext context) => Positioned(
    left: 0,
    right: 0,
    bottom: 0,
    height: 4,
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor: gauge.fraction.clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: HoneyGlass.liquid(gauge.level),
            ),
          ),
        ),
      ),
    ),
  );
}
