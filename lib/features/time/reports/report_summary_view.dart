import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_report_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hive_widgets.dart' show fmtDuration;
import '../../../core/widgets/soft_card.dart';
import 'report_format.dart';

/// The summary of a time report (HIN-93): the totals, one chart and the groups
/// it is drawn from. Dumb views — they draw what they are handed.
///
/// Three rules from the design research (hin-93-review/design-research) and
/// the priority ladder of flutter-ui-design:
///
/// * A figure leads, its label follows, and a thin rail of the brand's honey
///   ties the figures of one report together (SchadenPro's task overview).
/// * One chart per report, its kind switched in its own head (Neutra's
///   transaction overview), and every chart has a list or a legend beside it
///   that says the same thing in words: colour never carries meaning alone.
/// * People are listed by name. The groups arrive sorted by size for projects
///   and activities, by name for people — never a ranking of colleagues.

/// The totals of a report: hours, billable hours, entries and — when rounding
/// changed anything — the hours as recorded.
class ReportTotalsStrip extends StatelessWidget {
  const ReportTotalsStrip({
    super.key,
    required this.totals,
    required this.compact,
  });

  final ReportTotals totals;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Two figures side by side on a phone, one per line once text is large
    // enough that "152 h 15 min" would break across three lines.
    final perLine = compact && textFactor(context) > 1.3 ? 1.0 : 0.5;
    final figures = [
      _Figure(
        label: context.t('time.reports.total'),
        value: fmtDuration(context, totals.minutes),
        rail: AppColors.accent,
        compact: compact,
      ),
      _Figure(
        label: context.t('time.reports.billable'),
        value: fmtDuration(context, totals.billableMinutes),
        rail: AppColors.stTodo,
        compact: compact,
      ),
      _Figure(
        label: context.t('time.reports.entries'),
        value: '${totals.entries}',
        rail: AppColors.stDone,
        compact: compact,
      ),
      if (totals.rounded)
        _Figure(
          label: context.t('time.reports.filed'),
          value: fmtDuration(context, totals.filedMinutes),
          rail: AppColors.stReview,
          compact: compact,
        ),
    ];
    return SoftCard(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 20,
        vertical: compact ? 14 : 18,
      ),
      child: compact
          ? Wrap(
              runSpacing: 14,
              children: [
                for (final figure in figures)
                  FractionallySizedBox(widthFactor: perLine, child: figure),
              ],
            )
          : Row(
              children: [
                for (final (index, figure) in figures.indexed) ...[
                  if (index > 0) const SizedBox(width: 24),
                  Expanded(child: figure),
                ],
              ],
            ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.rail,
    required this.compact,
  });

  final String label;
  final String value;
  final Color rail;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: rail,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: compact ? 18 : 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The chart kinds that make sense for a grouping: slices for shares of a
/// whole, a line for days in a row, bars for both.
List<ReportChart> chartsFor(ReportGroupBy groupBy) => groupBy.time
    ? const [ReportChart.bar, ReportChart.line]
    : const [ReportChart.bar, ReportChart.pie];

/// One chart of the report's first groups, its kind switched in its head.
class ReportChartCard extends StatelessWidget {
  const ReportChartCard({
    super.key,
    required this.groupBy,
    required this.groups,
    required this.totalMinutes,
    required this.chart,
    required this.onChart,
    required this.compact,
  });

  final ReportGroupBy groupBy;
  final List<ReportGroup> groups;
  final int totalMinutes;
  final ReportChart chart;
  final ValueChanged<ReportChart> onChart;
  final bool compact;

  /// Groups drawn at most; the rest are summed into "others" for slices and
  /// left to the list below for bars.
  static const shown = 8;

  @override
  Widget build(BuildContext context) {
    final kinds = chartsFor(groupBy);
    final kind = kinds.contains(chart) ? chart : kinds.first;
    final title = context.t(
      'time.reports.by',
      variables: {'group': context.t(groupBy.labelKey)},
    );
    return SoftCard(
      padding: EdgeInsets.fromLTRB(compact ? 14 : 20, 10, compact ? 6 : 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              for (final option in kinds)
                _ChartToggle(
                  kind: option,
                  active: option == kind,
                  onTap: () => onChart(option),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (groups.isEmpty || totalMinutes == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                context.t('time.reports.chartEmpty'),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
              ),
            )
          else
            Semantics(
              label: _spoken(context),
              child: ExcludeSemantics(
                child: switch (kind) {
                  ReportChart.pie => _Donut(
                    groupBy: groupBy,
                    groups: groups,
                    totalMinutes: totalMinutes,
                    compact: compact,
                  ),
                  ReportChart.line => _Line(groupBy: groupBy, groups: groups),
                  ReportChart.bar =>
                    groupBy.time
                        ? _Columns(groupBy: groupBy, groups: groups)
                        : _Bars(groupBy: groupBy, groups: groups),
                },
              ),
            ),
        ],
      ),
    );
  }

  /// The chart in one sentence for a screen reader: every drawn group and its
  /// hours, in the order they are drawn.
  String _spoken(BuildContext context) => [
    context.t(
      'time.reports.by',
      variables: {'group': context.t(groupBy.labelKey)},
    ),
    for (final group in groups.take(shown))
      '${groupLabel(context, groupBy, group)}: ${fmtDuration(context, group.minutes)}',
  ].join('. ');
}

class _ChartToggle extends StatelessWidget {
  const _ChartToggle({
    required this.kind,
    required this.active,
    required this.onTap,
  });

  final ReportChart kind;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The deeper honey on the light wash, where the brand's own is too light
    // for an icon (2.75:1, measured); the bright one on dark.
    final activeInk = Theme.of(context).brightness == Brightness.dark
        ? AppColors.accent
        : AppColors.accentText;
    final icon = switch (kind) {
      ReportChart.bar => LucideIcons.chartColumn,
      ReportChart.pie => LucideIcons.chartPie,
      ReportChart.line => LucideIcons.chartLine,
    };
    return Semantics(
      button: true,
      selected: active,
      child: IconButton(
        tooltip: context.t(kind.labelKey),
        onPressed: active ? null : onTap,
        iconSize: 18,
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          backgroundColor: active ? AppColors.accentSoft : Colors.transparent,
          disabledBackgroundColor: AppColors.accentSoft,
          foregroundColor: AppColors.inkSoft,
          disabledForegroundColor: activeInk,
        ),
        icon: Icon(icon),
      ),
    );
  }
}

/// Horizontal bars for groups that are names: every label legible in full
/// width, the hours at the end of the line.
class _Bars extends StatelessWidget {
  const _Bars({required this.groupBy, required this.groups});

  final ReportGroupBy groupBy;
  final List<ReportGroup> groups;

  @override
  Widget build(BuildContext context) {
    final drawn = groups.take(ReportChartCard.shown).toList();
    final most = drawn.fold<int>(
      1,
      (max, group) => math.max(max, group.minutes),
    );
    final labelWidth = 140 * textFactor(context);
    return LayoutBuilder(
      builder: (context, box) => Column(
        children: [
          for (final (index, group) in drawn.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: math.min(labelWidth, box.maxWidth * 0.4),
                    child: Text(
                      groupLabel(context, groupBy, group),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: AppColors.ink),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Container(
                          height: 12,
                          width: math.max(
                            4,
                            constraints.maxWidth * group.minutes / most,
                          ),
                          decoration: BoxDecoration(
                            color: groupColor(group, index),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    fmtDuration(context, group.minutes),
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Columns for days, weeks and months.
class _Columns extends StatelessWidget {
  const _Columns({required this.groupBy, required this.groups});

  final ReportGroupBy groupBy;
  final List<ReportGroup> groups;

  @override
  Widget build(BuildContext context) {
    final most = groups.fold<int>(
      1,
      (max, group) => math.max(max, group.minutes),
    );
    return _AxisText(
      child: SizedBox(
        height: 200,
        child: BarChart(
          BarChartData(
            maxY: most / 60 * 1.15,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: AppColors.hairline2, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: _titles(context, groupBy, groups),
            barTouchData: const BarTouchData(enabled: false),
            barGroups: [
              for (final (index, group) in groups.indexed)
                BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: group.minutes / 60,
                      color: seriesColor(0),
                      width: groups.length > 20 ? 6 : 14,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 250),
        ),
      ),
    );
  }
}

/// A line through days, weeks or months, the area under it washed in honey.
class _Line extends StatelessWidget {
  const _Line({required this.groupBy, required this.groups});

  final ReportGroupBy groupBy;
  final List<ReportGroup> groups;

  @override
  Widget build(BuildContext context) {
    final most = groups.fold<int>(
      1,
      (max, group) => math.max(max, group.minutes),
    );
    return _AxisText(
      child: SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: most / 60 * 1.15,
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: AppColors.hairline2, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: _titles(context, groupBy, groups),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (final (index, group) in groups.indexed)
                    FlSpot(index.toDouble(), group.minutes / 60),
                ],
                color: AppColors.accentStrong,
                barWidth: 2.5,
                isCurved: true,
                preventCurveOverShooting: true,
                dotData: FlDotData(show: groups.length <= 31),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.accent.withValues(alpha: 0.16),
                ),
              ),
            ],
          ),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 250),
        ),
      ),
    );
  }
}

/// The text inside a chart, enlarged with the reader's setting up to 130 %.
///
/// An axis label is a caption to a picture whose every value the list beside
/// it states in full-size text; at 200 % the labels would push the plot out of
/// its own frame. The captions keep growing up to the point the plot still
/// fits, and the words that carry the data scale all the way.
class _AxisText extends StatelessWidget {
  const _AxisText({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child);
}

/// Axis titles for a row of buckets: hours at the start, a few dates below.
FlTitlesData _titles(
  BuildContext context,
  ReportGroupBy groupBy,
  List<ReportGroup> groups,
) {
  final narrow = MediaQuery.sizeOf(context).width < 600;
  final step = math.max(1, (groups.length / (narrow ? 4 : 7)).ceil());
  final style = TextStyle(
    fontFamily: AppTheme.fontMono,
    fontSize: 10,
    color: AppColors.inkSoft,
  );
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 50,
        getTitlesWidget: (value, meta) => SideTitleWidget(
          meta: meta,
          child: Text(
            context.t('time.fmt.hours', variables: {'h': value.round()}),
            style: style,
            maxLines: 1,
            softWrap: false,
          ),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 24,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final index = value.round();
          if (index < 0 || index >= groups.length || index % step != 0) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            meta: meta,
            child: Text(
              axisLabel(context, groupBy, groups[index]),
              style: style,
              maxLines: 1,
            ),
          );
        },
      ),
    ),
  );
}

/// Slices for shares of a whole, the total in the hole and a legend that says
/// the same in words and figures.
class _Donut extends StatelessWidget {
  const _Donut({
    required this.groupBy,
    required this.groups,
    required this.totalMinutes,
    required this.compact,
  });

  final ReportGroupBy groupBy;
  final List<ReportGroup> groups;
  final int totalMinutes;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final drawn = groups.take(ReportChartCard.shown - 1).toList();
    final rest =
        totalMinutes - drawn.fold<int>(0, (sum, group) => sum + group.minutes);
    final slices = [
      for (final (index, group) in drawn.indexed)
        (
          label: groupLabel(context, groupBy, group),
          minutes: group.minutes,
          color: groupColor(group, index),
        ),
      if (rest > 0)
        (
          label: context.t('time.reports.others'),
          minutes: rest,
          color: AppColors.inkSoft,
        ),
    ];
    final donut = SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 58,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(enabled: false),
              sections: [
                for (final slice in slices)
                  PieChartSectionData(
                    value: slice.minutes.toDouble(),
                    color: slice.color,
                    radius: 28,
                    showTitle: false,
                  ),
              ],
            ),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 250),
          ),
          // Inside the hole, whatever the text size: the ring is a picture of
          // fixed size, and the total is repeated in the figures above.
          SizedBox(
            width: 96,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fmtDuration(context, totalMinutes),
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    context.t('time.reports.total'),
                    style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final slice in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: slice.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: slice.label),
                        TextSpan(
                          text:
                              '  ${(100 * slice.minutes / totalMinutes).round()} %',
                          style: TextStyle(
                            fontFamily: AppTheme.fontMono,
                            fontSize: 12,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: AppColors.ink),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  fmtDuration(context, slice.minutes),
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
      ],
    );
    return compact
        ? Column(children: [donut, const SizedBox(height: 14), legend])
        : Row(
            children: [
              donut,
              const SizedBox(width: 28),
              Expanded(child: legend),
            ],
          );
  }
}

/// One group of the list under the chart: its name, its share of the total,
/// its hours, its billable hours and its entries.
class ReportGroupRow extends StatelessWidget {
  const ReportGroupRow({
    super.key,
    required this.groupBy,
    required this.group,
    required this.index,
    required this.totalMinutes,
    required this.compact,
    this.onTap,
  });

  final ReportGroupBy groupBy;
  final ReportGroup group;

  /// The group's place in the report, which picks its colour.
  final int index;
  final int totalMinutes;
  final bool compact;

  /// Opens the entries of this group; null where a group cannot be narrowed to.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final share = totalMinutes == 0 ? 0.0 : group.minutes / totalMinutes;
    final label = groupLabel(context, groupBy, group);
    final detail = groupDetail(groupBy, group);
    final color = groupColor(group, index, series: ReportChartCard.shown);
    final factor = textFactor(context);
    final hours = Text(
      fmtDuration(context, group.minutes),
      style: TextStyle(
        fontFamily: AppTheme.fontMono,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
    );
    final name = Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        if (detail != null) ...[
          Text(
            detail,
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: AppColors.ink),
          ),
        ),
      ],
    );
    final bar = _ShareBar(share: share, color: color);
    final secondary = TextStyle(
      fontFamily: AppTheme.fontMono,
      fontSize: 12,
      color: AppColors.inkSoft,
    );
    final row = compact
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: name),
                    const SizedBox(width: 10),
                    hours,
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(child: bar),
                    const SizedBox(width: 10),
                    Text('${(share * 100).round()} %', style: secondary),
                  ],
                ),
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(flex: 5, child: name),
                const SizedBox(width: 16),
                Expanded(flex: 3, child: bar),
                SizedBox(
                  width: 52 * factor,
                  child: Text(
                    '${(share * 100).round()} %',
                    textAlign: TextAlign.end,
                    style: secondary,
                  ),
                ),
                SizedBox(
                  width: 110 * factor,
                  child: Align(alignment: Alignment.centerRight, child: hours),
                ),
                SizedBox(
                  width: 110 * factor,
                  child: Text(
                    fmtDuration(context, group.billableMinutes),
                    textAlign: TextAlign.end,
                    style: secondary,
                  ),
                ),
                SizedBox(
                  width: 80 * factor,
                  child: Text(
                    '${group.entries}',
                    textAlign: TextAlign.end,
                    style: secondary,
                  ),
                ),
              ],
            ),
          );
    return Semantics(
      button: onTap != null,
      label:
          '$label, ${fmtDuration(context, group.minutes)}, '
          '${(share * 100).round()} %',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: row,
        ),
      ),
    );
  }
}

/// The column heads over the wide list of groups.
class ReportGroupHead extends StatelessWidget {
  const ReportGroupHead({super.key, required this.groupBy});

  final ReportGroupBy groupBy;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
      color: AppColors.inkSoft,
    );
    final factor = textFactor(context);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Text(context.t(groupBy.labelKey), style: style),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: Text(context.t('time.reports.share'), style: style),
            ),
            SizedBox(width: 52 * factor),
            SizedBox(
              width: 110 * factor,
              child: Text(
                context.t('time.reports.total'),
                textAlign: TextAlign.end,
                style: style,
              ),
            ),
            SizedBox(
              width: 110 * factor,
              child: Text(
                context.t('time.reports.billable'),
                textAlign: TextAlign.end,
                style: style,
              ),
            ),
            SizedBox(
              width: 80 * factor,
              child: Text(
                context.t('time.reports.entries'),
                textAlign: TextAlign.end,
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.share, required this.color});

  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: AppColors.hairline),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: share.clamp(0.0, 1.0),
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
