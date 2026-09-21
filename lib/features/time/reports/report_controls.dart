import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_report_models.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_filter_bar.dart';
import '../../sprint/modals/glass_modal.dart';
import 'report_format.dart';

/// The row of glass pills over a report (HIN-93): the window, the filters,
/// the grouping, and a way to clear the filters.
///
/// On a phone they are one line that scrolls sideways, so the head of the page
/// never grows past two rows of pills (the tabs docked in the app bar, and
/// this); on a wide window they wrap. Every pill is [kGlassControlHeight], the
/// height every docked control in the app keeps.
class ReportControlsRow extends StatelessWidget {
  const ReportControlsRow({
    super.key,
    required this.query,
    required this.from,
    required this.to,
    required this.onRange,
    required this.onFilters,
    required this.onClear,
    this.groupings,
    this.onGroupBy,
    this.scope,
  });

  final ReportQuery query;

  /// The window the query covers today.
  final DateTime from;
  final DateTime to;
  final ValueChanged<Rect?> onRange;
  final ValueChanged<Rect?> onFilters;
  final VoidCallback onClear;

  /// The groupings on offer, or null where the tab has no grouping.
  final List<ReportGroupBy>? groupings;
  final ValueChanged<ReportGroupBy>? onGroupBy;

  /// A tab's own narrowing, such as the workload's project; it joins the
  /// line rather than opening one of its own.
  final Widget? scope;

  @override
  Widget build(BuildContext context) {
    final count = query.filterCount;
    final pills = <Widget>[
      GlassFilterPill(
        icon: LucideIcons.calendarRange,
        label: query.range == ReportRange.custom
            ? windowLabel(context, from, to)
            : context.t(query.range.labelKey),
        active: query.range != ReportRange.thisMonth,
        onTap: onRange,
      ),
      GlassFilterPill(
        icon: LucideIcons.listFilter,
        label: count == 0
            ? context.t('time.reports.filter')
            : context.t(
                'time.reports.filterCount',
                variables: {'count': count},
              ),
        active: count > 0,
        onTap: onFilters,
      ),
      if (groupings != null && onGroupBy != null)
        GlassFilterPill(
          icon: LucideIcons.layers,
          label: context.t(
            'time.reports.by',
            variables: {'group': context.t(query.groupBy.labelKey)},
          ),
          active: query.groupBy != ReportGroupBy.project,
          onTap: (anchor) => unawaited(_pickGroup(context, anchor)),
        ),
      ?scope,
      if (count > 0)
        Tooltip(
          message: context.t('time.reports.clear'),
          child: Semantics(
            button: true,
            label: context.t('time.reports.clear'),
            child: GlassClearFiltersPill(onTap: onClear),
          ),
        ),
    ];
    if (context.isCompact) {
      return SizedBox(
        height: kGlassControlHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
          itemCount: pills.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, index) => pills[index],
        ),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: pills);
  }

  Future<void> _pickGroup(BuildContext context, Rect? anchor) async {
    final picked = await showGlassOptions<ReportGroupBy>(
      context,
      title: context.t('time.reports.groupBy'),
      anchorRect: anchor,
      options: [
        for (final group in groupings!)
          (
            value: group,
            child: _OptionLabel(
              label: context.t(group.labelKey),
              selected: group == query.groupBy,
            ),
          ),
      ],
    );
    if (picked != null) onGroupBy!(picked);
  }
}

/// Asks for a window: one of the relative ranges, or two days of the reader's
/// choosing. Resolves to the query with its new window, or null.
Future<ReportQuery?> pickReportRange(
  BuildContext context, {
  required ReportQuery query,
  required DateTime from,
  required DateTime to,
  Rect? anchor,
}) async {
  final picked = await showGlassOptions<ReportRange>(
    context,
    title: context.t('time.reports.pickRange'),
    anchorRect: anchor,
    options: [
      for (final range in ReportRange.values)
        (
          value: range,
          child: _OptionLabel(
            label: context.t(range.labelKey),
            selected: range == query.range,
          ),
        ),
    ],
  );
  if (picked == null || !context.mounted) return null;
  if (picked != ReportRange.custom) {
    return query.copyWith(range: picked, from: null, to: null);
  }
  final today = DateUtils.dateOnly(DateTime.now());
  final span = await showGlassDateRangePicker(
    context,
    firstDate: DateTime(today.year - 10),
    lastDate: DateTime(today.year + 1, 12, 31),
    initialRange: DateTimeRange(start: from, end: to),
    title: context.t('time.reports.pickRange'),
  );
  if (span == null) return null;
  // A year and a day at most, as the server allows.
  final end = span.end.difference(span.start).inDays > 365
      ? span.start.add(const Duration(days: 365))
      : span.end;
  return query.copyWith(range: ReportRange.custom, from: span.start, to: end);
}

class _OptionLabel extends StatelessWidget {
  const _OptionLabel({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: AppColors.ink,
            ),
          ),
        ),
        if (selected)
          Icon(LucideIcons.check, size: 16, color: AppColors.accentInk),
      ],
    );
  }
}
