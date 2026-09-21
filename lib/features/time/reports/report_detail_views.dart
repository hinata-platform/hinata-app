import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_report_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hive_widgets.dart' show fmtDuration;
import 'report_format.dart';

/// The rows of the detailed, workload and saved tabs (HIN-93). Dumb views.

/// A day's heading over its entries in the detailed list.
class ReportDayHead extends StatelessWidget {
  const ReportDayHead({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(
          DateFormat.yMMMMEEEEd(locale).format(day),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

/// One entry of the detailed report: what was done, where, when and how long —
/// and by whom, when the reader may see other people's entries.
class ReportEntryRow extends StatelessWidget {
  const ReportEntryRow({
    super.key,
    required this.entry,
    required this.showPerson,
    required this.compact,
  });

  final ReportEntry entry;
  final bool showPerson;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final time = DateFormat.Hm(locale);
    final span = entry.startedAt != null && entry.endedAt != null
        ? '${time.format(entry.startedAt!)}–${time.format(entry.endedAt!)}'
        : null;
    final description = (entry.description ?? '').trim();
    final where = [
      if (entry.projectKey != null) entry.projectKey!,
      if (entry.issueKey != null)
        entry.issueTitle == null
            ? entry.issueKey!
            : '${entry.issueKey} ${entry.issueTitle}',
    ].join(' · ');
    final rounded = entry.roundedMinutes != entry.minutes;
    final factor = textFactor(context);
    final duration = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fmtDuration(context, entry.roundedMinutes),
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        if (rounded)
          Text(
            context.t(
              'time.reports.recordedAs',
              variables: {'duration': fmtDuration(context, entry.minutes)},
            ),
            style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
          ),
      ],
    );
    final meta = TextStyle(fontSize: 12, color: AppColors.inkSoft);
    final title = Text(
      description.isEmpty
          ? context.t('time.reports.noDescription')
          : description,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        fontStyle: description.isEmpty ? FontStyle.italic : FontStyle.normal,
        color: description.isEmpty ? AppColors.inkSoft : AppColors.ink,
      ),
    );
    final details = Wrap(
      spacing: 10,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (compact && span != null)
          Text(span, style: meta.copyWith(fontFamily: AppTheme.fontMono)),
        if (where.isNotEmpty) Text(where, style: meta),
        if (entry.activity != null) Text(entry.activity!, style: meta),
        for (final tag in entry.tags) Text('#$tag', style: meta),
        if (entry.billable)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.badgeEuro, size: 13, color: AppColors.inkSoft),
              const SizedBox(width: 3),
              Text(context.t('time.reports.billable'), style: meta),
            ],
          ),
        if (compact && showPerson && entry.userName != null)
          Text(
            entry.userName!,
            style: meta.copyWith(fontWeight: FontWeight.w600),
          ),
      ],
    );
    final body = compact
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 4), details],
                ),
              ),
              const SizedBox(width: 12),
              duration,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 104 * factor,
                child: Text(
                  span ?? '—',
                  style: meta.copyWith(fontFamily: AppTheme.fontMono),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 4), details],
                ),
              ),
              if (showPerson) ...[
                const SizedBox(width: 16),
                SizedBox(
                  width: 170 * factor,
                  child: Text(
                    entry.userName ?? context.t('time.otherMember'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: AppColors.ink),
                  ),
                ),
              ],
              const SizedBox(width: 16),
              SizedBox(width: 110 * factor, child: duration),
            ],
          );
    // A card of its own per entry, with one uniform edge: a list of hundreds
    // stays lazy, and no row has to know whether it opens or closes a day.
    return MergeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.hairline),
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 18,
            vertical: 12,
          ),
          child: body,
        ),
      ),
    );
  }
}

/// One person of the workload report: capacity, booked time and the
/// difference, as numbers and as one neutral bar. No colour says "too little"
/// or "too much", and the list is in order of name, never of hours.
class WorkloadRowView extends StatelessWidget {
  const WorkloadRowView({super.key, required this.row, required this.compact});

  final WorkloadRow row;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final capacity = row.capacityMinutes;
    final share = capacity <= 0
        ? 0.0
        : (row.bookedMinutes / capacity).clamp(0.0, 1.0);
    final figure = TextStyle(
      fontFamily: AppTheme.fontMono,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
    );
    final label = TextStyle(fontSize: 11.5, color: AppColors.inkSoft);
    // On a phone the three figures spread across the row: the first keeps to
    // the start, the middle to the centre, the last to the end.
    Widget cell(
      String caption,
      String value, [
      CrossAxisAlignment align = CrossAxisAlignment.end,
    ]) => Column(
      crossAxisAlignment: compact ? align : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: figure),
        Text(caption, style: label),
      ],
    );
    final numbers = [
      cell(
        context.t('time.reports.workload.capacity'),
        fmtDuration(context, row.capacityMinutes),
        CrossAxisAlignment.start,
      ),
      cell(
        context.t('time.reports.workload.booked'),
        fmtDuration(context, row.bookedMinutes),
        CrossAxisAlignment.center,
      ),
      cell(
        context.t('time.reports.workload.difference'),
        signedDuration(
          context,
          row.differenceMinutes,
          (minutes) => fmtDuration(context, minutes),
        ),
      ),
    ];
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: AppColors.hairline),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: share,
              child: ColoredBox(color: AppColors.brandInk),
            ),
          ],
        ),
      ),
    );
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          row.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        if (row.absenceMinutes > 0 || row.holidayMinutes > 0)
          Text(
            context.t(
              'time.reports.workload.away',
              variables: {
                'duration': fmtDuration(
                  context,
                  row.absenceMinutes + row.holidayMinutes,
                ),
              },
            ),
            style: label,
          ),
      ],
    );
    return MergeSemantics(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 20,
          vertical: 12,
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  name,
                  const SizedBox(height: 8),
                  bar,
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: numbers,
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 4, child: name),
                  const SizedBox(width: 16),
                  Expanded(flex: 4, child: bar),
                  for (final number in numbers)
                    SizedBox(
                      width: 120 * textFactor(context),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: number,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// One saved report: its name, what it covers, whether it is shared and when
/// it is mailed. [onOpen] shows it; [onMenu] offers what can be done with it.
class SavedReportTile extends StatelessWidget {
  const SavedReportTile({
    super.key,
    required this.report,
    required this.onOpen,
    required this.onMenu,
  });

  final SavedReport report;
  final VoidCallback onOpen;
  final ValueChanged<Rect?> onMenu;

  @override
  Widget build(BuildContext context) {
    final query = report.query;
    final parts = [
      context.t(query.range.labelKey),
      if (report.from != null && report.to != null)
        windowLabel(context, report.from!, report.to!),
      context.t(
        'time.reports.by',
        variables: {'group': context.t(query.groupBy.labelKey)},
      ),
      if (query.filterCount > 0)
        context.t('time.reports.filters', count: query.filterCount),
    ];
    final schedule = report.schedule;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.hairline),
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Icon(
                LucideIcons.fileChartColumn,
                size: 20,
                color: AppColors.accentInk,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      parts.join(' · '),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                    if (report.shared || schedule != null) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (report.shared)
                            _Badge(
                              icon: LucideIcons.link,
                              label: context.t('time.reports.saved.shared'),
                            ),
                          if (schedule != null)
                            _Badge(
                              icon: LucideIcons.mail,
                              label: schedule.cadence == ReportCadence.weekly
                                  ? context.t(
                                      'time.reports.saved.weeklyOn',
                                      variables: {
                                        'day': DateFormat.EEEE(locale).format(
                                          DateTime(2024, 1, schedule.weekday),
                                        ),
                                        'hour': '${schedule.hour}'.padLeft(
                                          2,
                                          '0',
                                        ),
                                        'count': schedule.recipients.length,
                                      },
                                    )
                                  : context.t(
                                      'time.reports.saved.monthlyOn',
                                      variables: {
                                        'hour': '${schedule.hour}'.padLeft(
                                          2,
                                          '0',
                                        ),
                                        'count': schedule.recipients.length,
                                      },
                                    ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Builder(
                builder: (anchor) => IconButton(
                  tooltip: context.t('time.reports.saved.actions'),
                  onPressed: () {
                    final box = anchor.findRenderObject() as RenderBox?;
                    onMenu(
                      box == null || !box.hasSize
                          ? null
                          : box.localToGlobal(Offset.zero) & box.size,
                    );
                  },
                  icon: Icon(LucideIcons.ellipsis, color: AppColors.inkSoft),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    // Amber text on the amber wash: the deeper honey in the light theme, where
    // the brand's own is too light on its tint; the bright one on dark.
    final ink = Theme.of(context).brightness == Brightness.dark
        ? AppColors.accent
        : AppColors.accentText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: ink),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}
