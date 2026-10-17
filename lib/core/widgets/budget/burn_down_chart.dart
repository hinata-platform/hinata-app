import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../i18n/i18n.dart';
import '../../models/time_usage_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_type.dart';
import 'budget_style.dart';
import 'honey_glass.dart';

/// How a project's budget filled up over time (HIN-156, "Honigstand"): the
/// running total as a honey area, the budget as a line across, the sum of
/// estimates as a dashed one. Past the budget the line turns to ember and the
/// band above the budget is tinted, so an overrun reads at a glance.
///
/// Colour never carries it alone: the legend names every line, and a screen
/// reader hears one sentence with the figures instead of a drawing.
class BurnDownChart extends StatelessWidget {
  const BurnDownChart({
    super.key,
    required this.history,
    this.limitMinutes,
    this.estimatedMinutes,
    this.height = 200,
  });

  final BudgetHistory history;

  /// The time budget, drawn as a line across; null for none.
  final int? limitMinutes;
  final int? estimatedMinutes;
  final double height;

  @override
  Widget build(BuildContext context) {
    final points = history.cumulative;
    if (points.isEmpty) return const SizedBox.shrink();
    double hours(int minutes) => minutes / 60;
    final last = points.last.total;
    final budget = limitMinutes;
    final over = budget != null && last > budget;
    final level = budget == null
        ? BudgetLevel.within
        : BudgetGauge(used: last, limit: budget).level;
    final colors = HoneyGlass.liquid(level);
    final top = [last, ?budget, ?estimatedMinutes].reduce(math.max);
    final maxY = math.max(1.0, hours(top) * 1.12);
    final lastX = (points.length - 1).toDouble();
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dates = DateFormat.MMMd(locale);
    final label = TextStyle(
      fontSize: AppType.caption,
      color: AppColors.inkFaint,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final summary = budget == null
        ? context.t(
            'budget.history.summaryNoBudget',
            variables: {'used': budgetMinutes(context, last)},
          )
        : context.t(
            'budget.history.summary',
            variables: {
              'sums': BudgetStyle.usedOfLimit(
                context,
                BudgetGauge(used: last, limit: budget),
                budgetMinutes,
              ),
              'percent': BudgetStyle.percent(
                context,
                BudgetGauge(used: last, limit: budget),
              ),
              'from': dates.format(history.from),
              'to': dates.format(history.to),
            },
          );

    final chart = SizedBox(
      height: height,
      child: LineChart(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 400),
        LineChartData(
          minX: 0,
          maxX: lastX <= 0 ? 1 : lastX,
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: math.max(1, (maxY / 4).ceilToDouble()),
            getDrawingHorizontalLine: (_) =>
                FlLine(color: AppColors.hairline2, strokeWidth: 1),
          ),
          rangeAnnotations: RangeAnnotations(
            horizontalRangeAnnotations: [
              if (budget != null)
                HorizontalRangeAnnotation(
                  y1: hours(budget),
                  y2: maxY,
                  color: AppColors.danger.withValues(alpha: 0.06),
                ),
            ],
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              if (budget != null)
                HorizontalLine(
                  y: hours(budget),
                  color: AppColors.ink.withValues(alpha: 0.75),
                  strokeWidth: 1.4,
                ),
              if (estimatedMinutes != null && estimatedMinutes! > 0)
                HorizontalLine(
                  y: hours(estimatedMinutes!),
                  color: AppColors.inkSoft,
                  strokeWidth: 1.2,
                  dashArray: const [6, 5],
                ),
            ],
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                interval: math.max(1, (maxY / 4).ceilToDouble()),
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text('${value.round()} h', style: label),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: lastX <= 0 ? 1 : lastX,
                getTitlesWidget: (value, meta) {
                  final index = value.round().clamp(0, points.length - 1);
                  if (value > 0 && value < lastX) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(dates.format(points[index].date), style: label),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < points.length; i++)
                  FlSpot(i.toDouble(), hours(points[i].total)),
              ],
              isCurved: false,
              color: over ? colors[2] : colors[1],
              barWidth: 2.6,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors[0].withValues(alpha: 0.55),
                    colors[1].withValues(alpha: 0.08),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Widget key(Color color, String text, {bool dashed = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: dashed ? 2 : 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(fontSize: AppType.caption, color: AppColors.inkSoft),
        ),
      ],
    );

    return Semantics(
      container: true,
      label: summary,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          chart,
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              key(colors[1], context.t('budget.history.recorded')),
              if (budget != null)
                key(AppColors.ink, context.t('budget.timeBudget')),
              if (estimatedMinutes != null && estimatedMinutes! > 0)
                key(
                  AppColors.inkSoft,
                  context.t('budget.estimates'),
                  dashed: true,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            summary,
            style: TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: AppType.caption,
              height: 1.4,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}
