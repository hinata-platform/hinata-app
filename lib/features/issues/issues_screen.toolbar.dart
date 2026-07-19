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
    // Compact (mobile): the four view controls collapse into a single
    // connected glass housing (iOS-style segmented bar) so they read as one
    // cluster instead of four detached boxes. Wide: separate labelled pills.
    final Widget controls = context.isCompact
        ? _SegmentedControls(
            grouping: grouping,
            onGrouping: onGrouping,
            sort: sort,
            onSort: onSort,
            filterCount: filterCount,
            filterKey: filterKey,
            onFilter: onFilter,
            timeRange: timeRange,
            onTimeRange: onTimeRange,
          )
        : Row(
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
          );
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: controls,
          ),
        ),
        const SizedBox(width: 10),
        if (onExport != null)
          _ExportButton(
            onSelected: onExport!,
            exporting: exporting,
            glass: context.isCompact,
          ),
      ],
    );
  }
}

/// Corner radius of the segmented glass housing (and the export button, so both
/// docked glass controls share one roundness). The active-segment indicator is
/// rounded *concentrically* — [_kSegmentedRadius] minus the [_kSegmentInset] —
/// so it echoes this shape: a pill housing yields pill indicators, a gentler
/// radius yields gentler indicators. Change this one value and all three follow.
const double _kSegmentedRadius = 30;

/// Inset of each segment's active indicator inside the glass housing.
const double _kSegmentInset = 5;

/// The compact (mobile) view-controls cluster: one glass housing holding the
/// Group-by / Sort / Filter / Time segments, separated by hairline dividers.
/// Each segment opens its own popover and tints its cell amber when active, so
/// multiple segments can read as "on" simultaneously (unlike a single-selection
/// segmented control). Export stays a separate button outside this housing.
class _SegmentedControls extends StatelessWidget {
  const _SegmentedControls({
    required this.grouping,
    required this.onGrouping,
    required this.sort,
    required this.onSort,
    required this.filterCount,
    required this.filterKey,
    required this.onFilter,
    required this.timeRange,
    required this.onTimeRange,
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

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Hairline-thin translucent divider that reads on the glass rather than an
    // opaque line (which would look painted-on over the refraction).
    Widget divider() => Container(
      width: 1,
      height: 22,
      color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.10),
    );
    return _GlassControlSurface(
      radius: _kSegmentedRadius,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GroupByButton(
            value: grouping,
            onChanged: onGrouping,
            segmented: true,
          ),
          divider(),
          _SortButton(value: sort, onChanged: onSort, segmented: true),
          divider(),
          _FilterButton(
            key: filterKey,
            count: filterCount,
            onTap: onFilter,
            segmented: true,
          ),
          divider(),
          _TimeRangeButton(
            value: timeRange,
            onChanged: onTimeRange,
            segmented: true,
          ),
        ],
      ),
    );
  }
}

/// A control surface for the docked toolbar: real refractive liquid glass on
/// native (own-layer [GlassContainer], matching the app-bar bell), a
/// [FrostedSurface] on web. The distinction matters because the toolbar sits on
/// the app bar's single blur — a second own-layer backdrop is fine on native
/// (Impeller), but on web/Skia it would nest [BackdropFilter]s and pixelate.
class _GlassControlSurface extends StatelessWidget {
  const _GlassControlSurface({required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (isNativeApp) {
      return GlassContainer(
        useOwnLayer: true,
        settings: dark ? kNavGlassDark : kNavGlassLight,
        shape: LiquidRoundedSuperellipse(borderRadius: radius),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }
    return FrostedSurface(
      borderRadius: BorderRadius.circular(radius),
      dark: dark,
      child: child,
    );
  }
}

/// One cell inside the compact [_SegmentedControls] glass housing: just the
/// [icon], with a translucent honey-amber fill when [active] (matching the
/// app-bar bell's active tint so it reads as glass, not a painted chip).
/// [badge] optionally trails the icon (the filter count).
class _SegmentCell extends StatelessWidget {
  const _SegmentCell({required this.icon, required this.active, this.badge});

  final IconData icon;
  final bool active;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      // Inset so the active fill floats inside the housing, clear of the glass
      // rim and the neighbouring dividers.
      padding: const EdgeInsets.all(_kSegmentInset),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: badge == null ? 13 : 11,
          vertical: 7,
        ),
        decoration: active
            ? BoxDecoration(
                color: AppColors.accent.withValues(alpha: dark ? 0.30 : 0.20),
                // Concentric with the housing (radius − inset), so a pill
                // housing gives a pill indicator; clamps to a stadium when the
                // fill is shorter than twice the radius.
                borderRadius: BorderRadius.circular(
                  _kSegmentedRadius - _kSegmentInset,
                ),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: active
                  ? (dark ? AppColors.accent : AppColors.accentStrong)
                  : AppColors.inkSoft,
            ),
            if (badge != null) ...[const SizedBox(width: 6), badge!],
          ],
        ),
      ),
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
  const _GroupByButton({
    required this.value,
    required this.onChanged,
    this.segmented = false,
  });

  final IssueGrouping value;
  final ValueChanged<IssueGrouping> onChanged;

  /// When true the button renders as a bare cell for the compact segmented
  /// housing (no individual border); otherwise as a standalone labelled pill.
  final bool segmented;

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
      child: segmented
          ? _SegmentCell(icon: _groupingIcon(value), active: active)
          : Container(
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
  IssueSort.createdDesc ||
  IssueSort.updatedDesc => LucideIcons.arrowDownWideNarrow,
  IssueSort.createdAsc || IssueSort.updatedAsc => LucideIcons.arrowUpNarrowWide,
};

/// Sort selector — mirrors [_GroupByButton]: an always-visible sort glyph, with
/// the label + chevron hidden on compact (icon-only) layouts. Tints amber when
/// a non-default order is active. The two created/updated pairs are separated by
/// a divider so the "by creation" vs "by last change" grouping reads clearly.
class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.value,
    required this.onChanged,
    this.segmented = false,
  });

  final IssueSort value;
  final ValueChanged<IssueSort> onChanged;

  /// Renders as a bare cell for the compact segmented housing when true.
  final bool segmented;

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
      child: segmented
          ? _SegmentCell(icon: LucideIcons.arrowUpDown, active: active)
          : Container(
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

/// White pill that opens the glass filter popup; shows an amber badge with the
/// active-criteria count. Its [key] anchors the popup's position.
class _FilterButton extends StatelessWidget {
  const _FilterButton({
    super.key,
    required this.count,
    required this.onTap,
    this.segmented = false,
  });

  final int count;
  final VoidCallback? onTap;

  /// Renders as a bare cell for the compact segmented housing when true. Unlike
  /// the popup-menu segments this control just fires [onTap]; the [key] on the
  /// widget still anchors the filter popover in either mode.
  final bool segmented;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    if (segmented) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: _SegmentCell(
          icon: LucideIcons.slidersHorizontal,
          active: active,
          badge: active ? _CountBadge(count: count) : null,
        ),
      );
    }
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
              color: active ? AppColors.accentLine : AppColors.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.slidersHorizontal,
                size: 16,
                color: active ? AppColors.accentStrong : AppColors.inkSoft,
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
              if (active) ...[
                const SizedBox(width: 7),
                _CountBadge(count: count),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The amber circular count badge shared by the filter pill and its compact
/// segment.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

// ─────────────────────────── time range ─────────────────────────────────

String _timeLabel(BuildContext context, IssueTimeRange r) {
  if (r.preset == IssueTimePreset.custom && r.custom != null) {
    // Locale-aware short (month/day) date — the day-month order flips per locale
    // instead of being hardcoded to the German 'dd.MM.' pattern.
    final fmt = DateFormat.Md(Localizations.localeOf(context).languageCode);
    return '${fmt.format(r.custom!.start)} – ${fmt.format(r.custom!.end)}';
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
  const _TimeRangeButton({
    required this.value,
    required this.onChanged,
    this.segmented = false,
  });

  final IssueTimeRange value;
  final ValueChanged<IssueTimeRange> onChanged;

  /// Renders as a bare cell for the compact segmented housing when true.
  final bool segmented;

  Future<void> _onSelected(BuildContext context, IssueTimePreset preset) async {
    if (preset == IssueTimePreset.custom) {
      final now = DateTime.now();
      final picked = await showGlassDateRangePicker(
        context,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 5),
        initialRange: value.custom,
        title: context.t('issues.time.selectRange'),
      );
      if (picked != null && context.mounted) {
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
      child: segmented
          ? _SegmentCell(icon: LucideIcons.calendar, active: active)
          : Container(
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
  const _ExportButton({
    required this.onSelected,
    this.exporting = false,
    this.glass = false,
  });
  final ValueChanged<String> onSelected;
  final bool exporting;

  /// When true the button renders on the same liquid glass as the docked
  /// toolbar (compact app bar); otherwise the plain in-scroll pill (wide).
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final content = Row(
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
    );
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
      child: glass
          ? _GlassControlSurface(
              radius: _kSegmentedRadius,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: content,
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                border: Border.all(color: AppColors.hairline),
              ),
              child: content,
            ),
    );
  }
}

// ─────────────────────────── group header / dot ─────────────────────────
