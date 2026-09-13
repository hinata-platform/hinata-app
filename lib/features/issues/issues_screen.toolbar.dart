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

/// The Issues controls: group-by, sort, filter and time range, with the export
/// on the trailing edge.
///
/// On a phone they are one glass housing docked into the app bar, scrolling
/// sideways when the phone is narrow. On a wide window each is a glass pill of
/// its own, the shape the boards' pills wear, and they wrap to the room the
/// window leaves them instead of scrolling out of sight.
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
    if (!context.isCompact) {
      return WideToolbar(
        leading: [
          _GroupByButton(value: grouping, onChanged: onGrouping),
          _SortButton(value: sort, onChanged: onSort),
          _FilterButton(key: filterKey, count: filterCount, onTap: onFilter),
          _TimeRangeButton(value: timeRange, onChanged: onTimeRange),
        ],
        trailing: [
          if (onExport != null)
            _ExportButton(onSelected: onExport!, exporting: exporting),
        ],
      );
    }
    // Compact (mobile): the four view controls collapse into a single
    // connected glass housing (iOS-style segmented bar) so they read as one
    // cluster instead of four detached boxes.
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _SegmentedControls(
              grouping: grouping,
              onGrouping: onGrouping,
              sort: sort,
              onSort: onSort,
              filterCount: filterCount,
              filterKey: filterKey,
              onFilter: onFilter,
              timeRange: timeRange,
              onTimeRange: onTimeRange,
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (onExport != null)
          _ExportButton(
            onSelected: onExport!,
            exporting: exporting,
            docked: true,
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
  /// housing (no individual border); otherwise as a glass pill of the wide
  /// toolbar.
  final bool segmented;

  @override
  Widget build(BuildContext context) {
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
          : _ToolPill(
              icon: _groupingIcon(value),
              label: active
                  ? _groupingLabel(context, value)
                  : context.t('board.groupBy'),
              active: active,
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
          : _ToolPill(
              icon: LucideIcons.arrowUpDown,
              label: context.t('issues.sort.label'),
              active: active,
            ),
    );
  }
}

/// The pill that opens the glass filter popup, with an amber badge counting the
/// criteria in force. Its [key] anchors the popup's position.
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
    return _ToolPill(
      icon: LucideIcons.slidersHorizontal,
      label: context.t('board.filterButton'),
      active: active,
      chevron: false,
      badge: active ? _CountBadge(count: count) : null,
      onTap: onTap,
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
          : _ToolPill(
              icon: LucideIcons.calendar,
              label: _timeLabel(context, value),
              active: active,
            ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.onSelected,
    this.exporting = false,
    this.docked = false,
  });
  final ValueChanged<String> onSelected;
  final bool exporting;

  /// When true the button renders on the same liquid glass as the docked
  /// toolbar (compact app bar); otherwise as a glass pill of the wide toolbar.
  final bool docked;

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
      child: docked
          ? _GlassControlSurface(
              radius: _kSegmentedRadius,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: exporting
                    ? const HiveLoader(size: 16)
                    : Icon(
                        LucideIcons.download,
                        size: 16,
                        color: AppColors.ink,
                      ),
              ),
            )
          : _ToolPill(
              icon: LucideIcons.download,
              label: context.t('reports.export'),
              busy: exporting,
              chevron: false,
            ),
    );
  }
}

/// One glass pill of the wide toolbar: a glyph, a word and, on the pills that
/// pick a value, a chevron. The shape the boards' group-by and filter pills
/// wear, so the Issues page and the boards put the same control in the same
/// material.
class _ToolPill extends StatelessWidget {
  const _ToolPill({
    required this.icon,
    required this.label,
    this.active = false,
    this.chevron = true,
    this.busy = false,
    this.badge,
    this.onTap,
  });

  final IconData icon;
  final String label;

  /// Washes the pill amber while its setting is not the default: a list quietly
  /// narrowed must not look like a list with nothing else in it.
  final bool active;

  /// Whether a chevron trails the word: on the pills that pick a value (a
  /// grouping, an order, a range), not on the ones that act.
  final bool chevron;

  /// Shows the loader in place of the glyph while an export is under way.
  final bool busy;

  /// Trails the word, like the filter's count.
  final Widget? badge;

  /// Null inside a [GlassPopupMenu], which takes the tap itself.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = active ? AppColors.accentStrong : AppColors.inkSoft;
    return GlassPill(
      height: kGlassControlHeight,
      active: active,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const HiveLoader(size: 16)
            else
              Icon(icon, size: 16, color: ink),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            if (badge != null) ...[const SizedBox(width: 6), badge!],
            if (chevron) ...[
              const SizedBox(width: 5),
              Icon(
                LucideIcons.chevronDown,
                size: 14,
                color: AppColors.inkFaint,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── group header / dot ─────────────────────────
