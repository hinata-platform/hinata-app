import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/absence_report_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/soft_card.dart';
import '../time/reports/report_format.dart';
import 'absence_labels.dart';

/// The report "absences and balances" (HIN-119) as widgets that only draw what
/// they are given: the year at a glance, a row per person or type, and the chip
/// that says what lapses when.
///
/// Three colours carry the whole report, the same in the ring and in every
/// row's bar: taken is the brand ink, planned the honey, what is left the green.
/// Each is named in words beside it as well — a colour never says a thing alone.

/// Taken, planned, left: the three parts of a year, in the report's colours.
Color absenceTakenColor() => AppColors.brandInk;
// The deeper honey on light surfaces: the brand's own reaches 2.3:1 on white,
// short of the 3:1 a bar needs (measured, HIN-119).
Color absencePlannedColor() => AppColors.brightness == Brightness.dark
    ? AppColors.accent
    : AppColors.accentDeep;
Color absenceLeftColor() => AppColors.stDone;

/// The year at a glance: a ring of taken, planned and left around what is left,
/// and the head figures beside it — the whole group's, as the server summed them.
class AbsenceReportOverview extends StatelessWidget {
  const AbsenceReportOverview({
    super.key,
    required this.head,
    required this.compact,
  });

  final AbsenceReportHead head;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final totals = head.totals;
    final figures = [
      _Figure(
        label: context.t('absence.report.remaining'),
        value: daysLabel(context, totals.remainingMilliDays),
        rail: absenceLeftColor(),
      ),
      _Figure(
        label: context.t('absence.report.taken'),
        value: daysLabel(context, totals.takenMilliDays),
        rail: absenceTakenColor(),
      ),
      _Figure(
        label: context.t('absence.report.planned'),
        value: daysLabel(context, totals.plannedMilliDays),
        rail: absencePlannedColor(),
      ),
      _Figure(
        label: context.t('absence.report.carriedIn'),
        value: daysLabel(context, totals.carriedInMilliDays),
        rail: AppColors.stTodo,
      ),
      if (head.rateVisible && totals.ratePermille != null)
        _Figure(
          label: context.t('absence.report.rate'),
          value: rateLabel(context, totals.ratePermille!),
          rail: AppColors.stReview,
        ),
    ];
    final ring = _YearRing(totals: totals);
    return SoftCard(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 20,
        vertical: compact ? 14 : 18,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final grid = Wrap(
            runSpacing: 14,
            children: [
              for (final figure in figures)
                FractionallySizedBox(
                  widthFactor: compact && textFactor(context) > 1.3
                      ? 1
                      : !compact && constraints.maxWidth >= 900
                      ? 1 / 3
                      : 0.5,
                  child: figure,
                ),
            ],
          );
          // A medium window keeps the ring beside two columns of figures; below
          // it on its own row it left half the card empty.
          final wide =
              !compact &&
              (constraints.maxWidth >= 640 ||
                  (constraints.maxWidth >= 520 && textFactor(context) <= 1.3));
          final people = Text(
            context.t(
              'absence.report.people',
              count: head.people,
              variables: {'count': head.people},
            ),
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
          );
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                grid,
                const SizedBox(height: 16),
                Center(child: ring),
                const SizedBox(height: 10),
                Center(child: people),
                if (totals.expiringMilliDays > 0) ...[
                  const SizedBox(height: 12),
                  Center(child: AbsenceExpiryChip(figures: totals)),
                ],
              ],
            );
          }
          return Row(
            children: [
              ring,
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    grid,
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        people,
                        if (totals.expiringMilliDays > 0)
                          AbsenceExpiryChip(figures: totals),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "12,5 %" from thousandths.
String rateLabel(BuildContext context, int permille) {
  final whole = permille ~/ 10;
  final tenth = permille % 10;
  final separator = days(context, 1500).contains(',') ? ',' : '.';
  return tenth == 0 ? '$whole %' : '$whole$separator$tenth %';
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.rail});

  final String label;
  final String value;
  final Color rail;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
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
                        fontSize: 18,
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
      ),
    );
  }
}

/// Taken, planned and left as one ring, what is left in its middle.
///
/// A picture of fixed size: the figures beside it say the same in words and
/// grow with the text, so the ring does not have to.
class _YearRing extends StatelessWidget {
  const _YearRing({required this.totals});

  final AbsenceFigures totals;

  @override
  Widget build(BuildContext context) {
    final left = math.max(0, totals.remainingMilliDays);
    final parts = [
      (value: totals.takenMilliDays, color: absenceTakenColor()),
      (value: totals.plannedMilliDays, color: absencePlannedColor()),
      (value: left, color: absenceLeftColor()),
    ].where((part) => part.value > 0).toList();
    final whole = parts.fold<int>(0, (sum, part) => sum + part.value);
    return ExcludeSemantics(
      child: SizedBox(
        width: 168,
        height: 168,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                sectionsSpace: parts.length > 1 ? 2 : 0,
                centerSpaceRadius: 56,
                startDegreeOffset: -90,
                pieTouchData: PieTouchData(enabled: false),
                sections: whole == 0
                    ? [
                        PieChartSectionData(
                          value: 1,
                          color: AppColors.hairline,
                          radius: 22,
                          showTitle: false,
                        ),
                      ]
                    : [
                        for (final part in parts)
                          PieChartSectionData(
                            value: part.value.toDouble(),
                            color: part.color,
                            radius: 22,
                            showTitle: false,
                          ),
                      ],
              ),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
            ),
            SizedBox(
              width: 84,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      days(context, left),
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      context.t(
                        'absence.report.leftOf',
                        variables: {
                          'days': days(
                            context,
                            totals.entitledMilliDays +
                                totals.carriedInMilliDays,
                          ),
                        },
                      ),
                      style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                    ),
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

/// "20 Tage verfallen am 31. März" — honey while the day is ahead.
class AbsenceExpiryChip extends StatelessWidget {
  const AbsenceExpiryChip({super.key, required this.figures});

  final AbsenceFigures figures;

  @override
  Widget build(BuildContext context) {
    final on = figures.expiringOn;
    final ink = Theme.of(context).brightness == Brightness.dark
        ? AppColors.accent
        : AppColors.accentText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.hourglass, size: 13, color: ink),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              on == null
                  ? daysLabel(context, figures.expiringMilliDays)
                  : context.t(
                      'absence.report.expiringOn',
                      variables: {
                        'days': daysLabel(context, figures.expiringMilliDays),
                        'date': dayMonthLabel(context, on),
                      },
                    ),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A person's or a type's share of the year as one bar: taken, planned, left.
class AbsenceYearBar extends StatelessWidget {
  const AbsenceYearBar({super.key, required this.figures});

  final AbsenceFigures figures;

  @override
  Widget build(BuildContext context) {
    final left = math.max(0, figures.remainingMilliDays);
    final parts = [
      (value: figures.takenMilliDays, color: absenceTakenColor()),
      (value: figures.plannedMilliDays, color: absencePlannedColor()),
      (value: left, color: absenceLeftColor()),
    ];
    final whole = parts.fold<int>(0, (sum, part) => sum + part.value);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 8,
          child: whole == 0
              ? ColoredBox(color: AppColors.hairline)
              : Row(
                  // Stretched: a colour box without a child is as small as it may
                  // be, and in a row that is no height at all.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final part in parts)
                      if (part.value > 0)
                        Expanded(
                          flex: math.max(1, (part.value * 1000 ~/ whole)),
                          child: ColoredBox(color: part.color),
                        ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The column heads over the rows, on a wide window only.
class AbsenceReportColumns extends StatelessWidget {
  const AbsenceReportColumns({
    super.key,
    required this.groupBy,
    required this.rateVisible,
  });

  final AbsenceReportGroupBy groupBy;
  final bool rateVisible;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.inkSoft,
    );
    final factor = textFactor(context);
    Widget column(String key) => SizedBox(
      width: _columnWidth * factor,
      child: Text(context.t(key), textAlign: TextAlign.end, style: style),
    );
    return LayoutBuilder(
      builder: (context, constraints) =>
          absenceColumnsFit(context, constraints.maxWidth, rateVisible)
          ? _head(context, style, column)
          : const SizedBox(height: 4),
    );
  }

  Widget _head(
    BuildContext context,
    TextStyle style,
    Widget Function(String) column,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.t(
                groupBy == AbsenceReportGroupBy.person
                    ? 'absence.report.person'
                    : 'absence.report.type',
              ),
              style: style,
            ),
          ),
          column('absence.report.entitled'),
          column('absence.report.carriedIn'),
          column('absence.report.taken'),
          column('absence.report.planned'),
          column('absence.report.remaining'),
          if (rateVisible)
            Tooltip(
              message: context.t('absence.report.rateHint'),
              child: column('absence.report.rateShort'),
            ),
        ],
      ),
    );
  }
}

const double _columnWidth = 92;

/// Whether the figure columns leave a name at least [_nameMin] wide at [width].
/// At a large text size they do not, and the row takes its phone form instead.
bool absenceColumnsFit(BuildContext context, double width, bool rateVisible) {
  final columns = rateVisible ? 6 : 5;
  return width - 40 - 16 - columns * _columnWidth * textFactor(context) >=
      _nameMin;
}

const double _nameMin = 200;

/// One person or one type: its name, its bar, its figures, and what lapses.
class AbsenceReportRowView extends StatelessWidget {
  const AbsenceReportRowView({
    super.key,
    required this.row,
    required this.label,
    required this.compact,
    required this.rateVisible,
  });

  final AbsenceReportRow row;

  /// The person's name or the type's, already resolved.
  final String label;
  final bool compact;
  final bool rateVisible;

  @override
  Widget build(BuildContext context) {
    if (compact) return _build(context, compact: true);
    return LayoutBuilder(
      builder: (context, constraints) => _build(
        context,
        compact: !absenceColumnsFit(context, constraints.maxWidth, rateVisible),
      ),
    );
  }

  Widget _build(BuildContext context, {required bool compact}) {
    final figures = row.figures;
    final factor = textFactor(context);
    final figure = TextStyle(
      fontFamily: AppTheme.fontMono,
      fontSize: 13,
      color: AppColors.ink,
    );
    final strong = figure.copyWith(fontWeight: FontWeight.w700);
    final name = Text(
      label,
      maxLines: compact ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
    );
    final expiring = figures.expiringMilliDays > 0
        ? AbsenceExpiryChip(figures: figures)
        : null;
    if (compact) {
      final small = TextStyle(fontSize: 12, color: AppColors.inkSoft);
      return MergeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: name),
                  const SizedBox(width: 10),
                  Text(
                    days(context, figures.remainingMilliDays),
                    style: strong,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AbsenceYearBar(figures: figures),
              const SizedBox(height: 8),
              Text(
                [
                  '${context.t('absence.report.taken')} ${days(context, figures.takenMilliDays)}',
                  '${context.t('absence.report.planned')} ${days(context, figures.plannedMilliDays)}',
                  '${context.t('absence.report.carriedIn')} ${days(context, figures.carriedInMilliDays)}',
                  if (rateVisible && figures.ratePermille != null)
                    '${context.t('absence.report.rate')} ${rateLabel(context, figures.ratePermille!)}',
                ].join(' · '),
                style: small,
              ),
              if (expiring != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: expiring,
                ),
              ],
            ],
          ),
        ),
      );
    }
    Widget cell(String value, {bool bold = false}) => SizedBox(
      width: _columnWidth * factor,
      child: Text(
        value,
        textAlign: TextAlign.end,
        style: bold ? strong : figure,
      ),
    );
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      name,
                      const SizedBox(height: 8),
                      AbsenceYearBar(figures: figures),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                cell(days(context, figures.entitledMilliDays)),
                cell(days(context, figures.carriedInMilliDays)),
                cell(days(context, figures.takenMilliDays)),
                cell(days(context, figures.plannedMilliDays)),
                cell(days(context, figures.remainingMilliDays), bold: true),
                if (rateVisible)
                  cell(
                    figures.ratePermille == null
                        ? '—'
                        : rateLabel(context, figures.ratePermille!),
                  ),
              ],
            ),
            if (expiring != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: expiring,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The legend under the rows: the three colours, named.
class AbsenceReportLegend extends StatelessWidget {
  const AbsenceReportLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(Color color, String key) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          context.t(key),
          style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
        ),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        item(absenceTakenColor(), 'absence.report.taken'),
        item(absencePlannedColor(), 'absence.report.planned'),
        item(absenceLeftColor(), 'absence.report.remaining'),
      ],
    );
  }
}
