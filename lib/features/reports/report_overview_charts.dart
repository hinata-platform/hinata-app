part of 'report_overview.dart';

/// The four figures over the cards: open, new and done in the span, and the
/// time recorded in it.
class _Figures extends StatelessWidget {
  const _Figures({required this.overview, required this.open});

  final ReportOverview overview;
  final int open;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      (LucideIcons.inbox, context.t('reports.overview.open'), '$open'),
      (
        LucideIcons.circlePlus,
        context.t(
          'reports.overview.created',
          variables: {'days': '${overview.days}'},
        ),
        '${overview.createdInSpan}',
      ),
      (
        LucideIcons.circleCheck,
        context.t(
          'reports.overview.resolved',
          variables: {'days': '${overview.days}'},
        ),
        '${overview.resolvedInSpan}',
      ),
      (
        LucideIcons.timer,
        context.t(
          'reports.overview.recorded',
          variables: {'days': '${overview.days}'},
        ),
        fmtDuration(context, overview.minutesInSpan),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 860
            ? 4
            : constraints.maxWidth >= 420
            ? 2
            : 1;
        const gap = 14.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (icon, label, value) in tiles)
              SizedBox(
                width: width,
                child: Semantics(
                  label: '$label: $value',
                  excludeSemantics: true,
                  child: FrostedCard(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: AppColors.accentSoft,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(
                                icon,
                                size: 16,
                                color: AppColors.accentInk,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: AppType.label,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          value,
                          style: TextStyle(
                            fontFamily: AppTheme.fontBrand,
                            fontSize: AppType.hero,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.6,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Open issues over the span as a honey area, with the straight line it would
/// follow to zero dashed beside it.
class _Trend extends StatelessWidget {
  const _Trend({required this.points, required this.days});

  final List<OverviewDay> points;

  /// The span, for the axis' first label.
  final int days;

  @override
  Widget build(BuildContext context) {
    final colors = HoneyGlass.liquid(BudgetLevel.within);
    final top = points
        .map((p) => math.max(p.remaining, p.ideal))
        .fold<double>(1, math.max);
    final last = (points.length - 1).toDouble();
    final label = TextStyle(
      fontSize: AppType.caption,
      color: AppColors.inkFaint,
    );
    return SizedBox(
      height: 190,
      child: LineChart(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 400),
        LineChartData(
          minX: 0,
          maxX: last,
          minY: 0,
          maxY: top * 1.12,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: math.max(1, (top / 4).ceilToDouble()),
            getDrawingHorizontalLine: (_) =>
                FlLine(color: AppColors.hairline2, strokeWidth: 1),
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
                reservedSize: 30,
                interval: math.max(1, (top / 4).ceilToDouble()),
                // The chart's own top is headroom, not a step of the scale:
                // labelled, it would sit on the last step's label.
                getTitlesWidget: (value, meta) => value >= meta.max
                    ? const SizedBox.shrink()
                    : SideTitleWidget(
                        meta: meta,
                        child: Text('${value.round()}', style: label),
                      ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: last <= 0 ? 1 : last,
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(
                    value <= 0
                        ? context.t(
                            'reports.windowStart',
                            variables: {'days': '$days'},
                          )
                        : context.t('reports.windowEnd'),
                    style: label,
                  ),
                ),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (final p in points) FlSpot(p.day.toDouble(), p.ideal),
              ],
              color: AppColors.inkFaint,
              barWidth: 1.4,
              dashArray: const [5, 5],
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: [
                for (final p in points) FlSpot(p.day.toDouble(), p.remaining),
              ],
              color: colors[2],
              barWidth: 2.6,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors[0].withValues(alpha: 0.55),
                    colors[1].withValues(alpha: 0.06),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
