part of 'issues_screen.dart';

/// One grouped section: a stable [key], a rendered [header] and its issues.
class _Section {
  const _Section({
    required this.key,
    required this.header,
    required this.issues,
  });
  final String key;
  final Widget header;
  final List<Issue> issues;
}

// ─────────────────────────── toolbar ────────────────────────────────────

/// The Issues controls row: Group-by + Filter + Time-range on the left (scrolls
/// horizontally when space is tight so it never overflows), Export pinned right.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.grouping,
    required this.onGrouping,
    required this.sort,
    required this.onSort,
    required this.filterCount,
    required this.filterKey,
    required this.onFilter,
    required this.timeRange,
    required this.onTimeRange,
    required this.onExport,
    required this.exporting,
  });

  final IssueGrouping grouping;
  final ValueChanged<IssueGrouping> onGrouping;
  final IssueSort sort;
  final ValueChanged<IssueSort> onSort;
  final int filterCount;
  final GlobalKey filterKey;
  final VoidCallback? onFilter;
  final IssueTimeRange timeRange;
  final ValueChanged<IssueTimeRange> onTimeRange;
  final ValueChanged<String>? onExport;

  /// While true the export is paging the full result set; the button shows the
  /// loader and ignores taps.
  final bool exporting;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _GroupByButton(value: grouping, onChanged: onGrouping),
                const SizedBox(width: 10),
                _SortButton(value: sort, onChanged: onSort),
                const SizedBox(width: 10),
                _FilterButton(
                  key: filterKey,
                  count: filterCount,
                  onTap: onFilter,
                ),
                const SizedBox(width: 10),
                _TimeRangeButton(value: timeRange, onChanged: onTimeRange),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (onExport != null)
          _ExportButton(onSelected: onExport!, exporting: exporting),
      ],
    );
  }
}

String _groupingLabel(BuildContext context, IssueGrouping g) => switch (g) {
  IssueGrouping.none => context.t('issues.group.none'),
  IssueGrouping.state => context.t('issues.group.state'),
  IssueGrouping.priority => context.t('issues.group.priority'),
  IssueGrouping.assignee => context.t('issues.group.assignee'),
  IssueGrouping.project => context.t('issues.group.project'),
  IssueGrouping.type => context.t('issues.group.type'),
};

/// Icon for a grouping dimension — shown left of each menu row and as the whole
/// button on compact (icon-only) layouts. Mirrors the filter popup's scope
/// icons so the same dimension reads identically across both controls.
IconData _groupingIcon(IssueGrouping g) => switch (g) {
  IssueGrouping.none => LucideIcons.rows3,
  IssueGrouping.state => LucideIcons.circleDot,
  IssueGrouping.priority => LucideIcons.flag,
  IssueGrouping.assignee => LucideIcons.user,
  IssueGrouping.project => LucideIcons.folder,
  IssueGrouping.type => LucideIcons.shapes,
};

class _GroupByButton extends StatelessWidget {
  const _GroupByButton({required this.value, required this.onChanged});

  final IssueGrouping value;
  final ValueChanged<IssueGrouping> onChanged;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final active = value != IssueGrouping.none;
    return GlassPopupMenu<IssueGrouping>(
      value: value,
      width: 230,
      onSelected: onChanged,
      items: [
        for (final g in IssueGrouping.values)
          GlassMenuItem(
            value: g,
            label: _groupingLabel(context, g),
            leading: Icon(_groupingIcon(g), size: 18),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(
            color: active ? AppColors.accentLine : AppColors.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _groupingIcon(value),
              size: 16,
              color: active ? AppColors.accentStrong : AppColors.inkSoft,
            ),
            if (!compact) ...[
              const SizedBox(width: 7),
              Text(
                active
                    ? _groupingLabel(context, value)
                    : context.t('board.groupBy'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                LucideIcons.chevronDown,
                size: 15,
                color: AppColors.inkFaint,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── sort ───────────────────────────────────────

String _sortLabel(BuildContext context, IssueSort s) => switch (s) {
  IssueSort.createdDesc => context.t('issues.sort.createdDesc'),
  IssueSort.createdAsc => context.t('issues.sort.createdAsc'),
  IssueSort.updatedDesc => context.t('issues.sort.updatedDesc'),
  IssueSort.updatedAsc => context.t('issues.sort.updatedAsc'),
};

/// A directional glyph for each sort option — descending (newest/most-recent
/// first) points down, ascending points up — so the menu reads at a glance.
IconData _sortIcon(IssueSort s) => switch (s) {
  IssueSort.createdDesc || IssueSort.updatedDesc =>
    LucideIcons.arrowDownWideNarrow,
  IssueSort.createdAsc || IssueSort.updatedAsc => LucideIcons.arrowUpNarrowWide,
};

/// Sort selector — mirrors [_GroupByButton]: an always-visible sort glyph, with
/// the label + chevron hidden on compact (icon-only) layouts. Tints amber when
/// a non-default order is active. The two created/updated pairs are separated by
/// a divider so the "by creation" vs "by last change" grouping reads clearly.
class _SortButton extends StatelessWidget {
  const _SortButton({required this.value, required this.onChanged});

  final IssueSort value;
  final ValueChanged<IssueSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final active = !value.isDefault;
    return GlassPopupMenu<IssueSort>(
      value: value,
      width: 250,
      onSelected: onChanged,
      items: [
        for (final s in IssueSort.values)
          GlassMenuItem(
            value: s,
            label: _sortLabel(context, s),
            leading: Icon(_sortIcon(s), size: 18),
            dividerAbove: s == IssueSort.updatedDesc,
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(
            color: active ? AppColors.accentLine : AppColors.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.arrowUpDown,
              size: 16,
              color: active ? AppColors.accentStrong : AppColors.inkSoft,
            ),
            if (!compact) ...[
              const SizedBox(width: 7),
              Text(
                context.t('issues.sort.label'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.accentStrong : AppColors.ink,
                ),
              ),
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronDown, size: 15, color: AppColors.inkFaint),
            ],
          ],
        ),
      ),
    );
  }
}

/// White pill that opens the glass filter popup; shows an amber badge with the
/// active-criteria count. Its [key] anchors the popup's position.
class _FilterButton extends StatelessWidget {
  const _FilterButton({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(
              color: count > 0 ? AppColors.accentLine : AppColors.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.slidersHorizontal,
                size: 16,
                color: count > 0 ? AppColors.accentStrong : AppColors.inkSoft,
              ),
              if (!context.isCompact) ...[
                const SizedBox(width: 7),
                Text(
                  context.t('board.filterButton'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (count > 0) ...[
                const SizedBox(width: 7),
                Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2A2410),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── time range ─────────────────────────────────

String _timeLabel(BuildContext context, IssueTimeRange r) {
  if (r.preset == IssueTimePreset.custom && r.custom != null) {
    String d(DateTime x) =>
        '${x.day.toString().padLeft(2, '0')}.${x.month.toString().padLeft(2, '0')}.';
    return '${d(r.custom!.start)} – ${d(r.custom!.end)}';
  }
  return switch (r.preset) {
    IssueTimePreset.all => context.t('issues.timeRange'),
    IssueTimePreset.overdue => context.t('issues.time.overdue'),
    IssueTimePreset.dueByToday => context.t('issues.time.dueByToday'),
    IssueTimePreset.today => context.t('issues.time.today'),
    IssueTimePreset.thisWeek => context.t('issues.time.thisWeek'),
    IssueTimePreset.thisMonth => context.t('issues.time.thisMonth'),
    IssueTimePreset.last7 => context.t('issues.time.last7'),
    IssueTimePreset.last30 => context.t('issues.time.last30'),
    IssueTimePreset.next7 => context.t('issues.time.next7'),
    IssueTimePreset.next30 => context.t('issues.time.next30'),
    IssueTimePreset.custom => context.t('issues.time.custom'),
  };
}

class _TimeRangeButton extends StatelessWidget {
  const _TimeRangeButton({required this.value, required this.onChanged});

  final IssueTimeRange value;
  final ValueChanged<IssueTimeRange> onChanged;

  Future<void> _onSelected(BuildContext context, IssueTimePreset preset) async {
    if (preset == IssueTimePreset.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 5),
        initialDateRange: value.custom,
        builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: AppColors.accentStrong),
          ),
          child: child!,
        ),
      );
      if (picked != null) {
        onChanged(
          IssueTimeRange(preset: IssueTimePreset.custom, custom: picked),
        );
      }
      return;
    }
    onChanged(IssueTimeRange(preset: preset));
  }

  @override
  Widget build(BuildContext context) {
    final active = value.isActive;
    return GlassPopupMenu<IssueTimePreset>(
      value: value.preset,
      width: 230,
      onSelected: (p) => _onSelected(context, p),
      items: [
        GlassMenuItem(
          value: IssueTimePreset.all,
          label: context.t('issues.time.all'),
          leading: const Icon(LucideIcons.infinity, size: 18),
        ),
        GlassMenuItem(
          value: IssueTimePreset.overdue,
          label: context.t('issues.time.overdue'),
          leading: const Icon(LucideIcons.triangleAlert, size: 18),
          dividerAbove: true,
        ),
        GlassMenuItem(
          value: IssueTimePreset.today,
          label: context.t('issues.time.today'),
          leading: const Icon(LucideIcons.calendarClock, size: 18),
        ),
        GlassMenuItem(
          value: IssueTimePreset.thisWeek,
          label: context.t('issues.time.thisWeek'),
          leading: const Icon(LucideIcons.calendarDays, size: 18),
        ),
        GlassMenuItem(
          value: IssueTimePreset.thisMonth,
          label: context.t('issues.time.thisMonth'),
          leading: const Icon(LucideIcons.calendarRange, size: 18),
        ),
        GlassMenuItem(
          value: IssueTimePreset.last7,
          label: context.t('issues.time.last7'),
          leading: const Icon(LucideIcons.history, size: 18),
          dividerAbove: true,
        ),
        GlassMenuItem(
          value: IssueTimePreset.last30,
          label: context.t('issues.time.last30'),
          leading: const Icon(LucideIcons.history, size: 18),
        ),
        GlassMenuItem(
          value: IssueTimePreset.next7,
          label: context.t('issues.time.next7'),
          leading: const Icon(LucideIcons.calendarPlus, size: 18),
        ),
        GlassMenuItem(
          value: IssueTimePreset.next30,
          label: context.t('issues.time.next30'),
          leading: const Icon(LucideIcons.calendarPlus, size: 18),
        ),
        GlassMenuItem(
          value: IssueTimePreset.custom,
          label: context.t('issues.time.custom'),
          leading: const Icon(LucideIcons.calendarSearch, size: 18),
          dividerAbove: true,
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(
            color: active ? AppColors.accentLine : AppColors.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.calendar,
              size: 16,
              color: active ? AppColors.accentStrong : AppColors.inkSoft,
            ),
            if (!context.isCompact) ...[
              const SizedBox(width: 7),
              Text(
                _timeLabel(context, value),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.accentStrong : AppColors.ink,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                LucideIcons.chevronDown,
                size: 15,
                color: AppColors.inkFaint,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.onSelected, this.exporting = false});
  final ValueChanged<String> onSelected;
  final bool exporting;

  @override
  Widget build(BuildContext context) {
    return GlassPopupMenu<String>(
      value: '',
      // The handler self-guards re-entry while a previous export is paging, so
      // a stray tap during export is a no-op.
      onSelected: onSelected,
      items: [
        GlassMenuItem(
          value: 'pdf',
          label: context.t('reports.exportPdf'),
          leading: const Icon(LucideIcons.fileText, size: 18),
        ),
        GlassMenuItem(
          value: 'csv',
          label: context.t('reports.exportCsv'),
          leading: const Icon(LucideIcons.table, size: 18),
        ),
        GlassMenuItem(
          value: 'json',
          label: context.t('reports.exportJson'),
          leading: const Icon(LucideIcons.braces, size: 18),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            exporting
                ? const HiveLoader(size: 16)
                : Icon(LucideIcons.download, size: 16, color: AppColors.ink),
            if (!context.isCompact) ...[
              const SizedBox(width: 8),
              Text(
                context.t('reports.export'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── group header / dot ─────────────────────────

