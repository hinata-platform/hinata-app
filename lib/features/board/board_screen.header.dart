part of 'board_screen.dart';

// ─────────────────────────── Filter button ────────────────────────────────

/// White pill that opens the glass filter popup; shows an amber badge with the
/// active-criteria count. Its [key] anchors the popup's position.
class _BoardFilterButton extends StatelessWidget {
  const _BoardFilterButton({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

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
                color: AppColors.inkSoft,
              ),
              const SizedBox(width: 7),
              Text(
                context.t('board.filterButton'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
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

// ─────────────────────────── Compact view switcher ────────────────────────

/// Mobile Board/Backlog/Timeline switcher: right-aligned, manually
/// collapsible (a chevron handle, expanded initially), with labels that
/// animate in/out as horizontal space allows, and an animated selection fill.
class _CompactViewSwitcher extends StatefulWidget {
  const _CompactViewSwitcher({
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<SegmentItem> items;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  State<_CompactViewSwitcher> createState() => _CompactViewSwitcherState();
}

class _CompactViewSwitcherState extends State<_CompactViewSwitcher> {
  static const _labelStyle = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
  );
  static const _dur = Duration(milliseconds: 240);

  bool _expanded = true;

  /// Whether the handle + all three labelled segments fit within [maxWidth].
  bool _labelsFit(double maxWidth) {
    final scaler = MediaQuery.textScalerOf(context);
    var total = 6.0 + 30.0; // outer pill padding + handle (12 pad + 18 icon)
    for (final item in widget.items) {
      final tp = TextPainter(
        text: TextSpan(text: item.label, style: _labelStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      total += 24 + 15 + 6 + tp.width; // segment: h-padding + icon + gap + text
    }
    // Comfortable slack so labels never appear right at the overflow boundary.
    return total + 8 <= maxWidth;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final showLabels = _expanded && _labelsFit(maxW);
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _handle(),
                for (var i = 0; i < widget.items.length; i++)
                  _segment(i, showLabels),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _handle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: AnimatedRotation(
          duration: _dur,
          curve: hiveEase,
          turns: _expanded ? 0 : 0.5,
          child: Icon(
            LucideIcons.chevronRight,
            size: 18,
            color: AppColors.inkFaint,
          ),
        ),
      ),
    );
  }

  Widget _segment(int i, bool showLabels) {
    final selected = i == widget.selected;
    final fg = selected ? Colors.white : AppColors.inkSoft;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onChanged(i),
      child: AnimatedContainer(
        duration: _dur,
        curve: hiveEase,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<Color?>(
              duration: _dur,
              curve: hiveEase,
              tween: ColorTween(end: fg),
              builder: (_, color, _) =>
                  Icon(widget.items[i].icon, size: 15, color: color),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: hiveEase,
              switchOutCurve: hiveEase,
              transitionBuilder: (child, anim) => SizeTransition(
                axis: Axis.horizontal,
                alignment: Alignment.centerLeft,
                sizeFactor: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: showLabels
                  ? Padding(
                      key: const ValueKey('label'),
                      padding: const EdgeInsets.only(left: 6),
                      child: AnimatedDefaultTextStyle(
                        duration: _dur,
                        curve: hiveEase,
                        style: _labelStyle.copyWith(color: fg),
                        child: Text(
                          widget.items[i].label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                        ),
                      ),
                    )
                  : const SizedBox(key: ValueKey('empty')),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Sprint header & selector ─────────────────────

/// Sprint info card: "Active" pill, sprint name + goal, and a linear
/// day-progress ("Day X/Y") when the sprint has start & end dates. Stacks the
/// progress under the name on compact widths so it never overflows.
class _SprintHeader extends StatelessWidget {
  const _SprintHeader({required this.sprint});
  final Sprint sprint;

  @override
  Widget build(BuildContext context) {
    final start = sprint.startDate;
    final end = sprint.endDate;
    Widget? progress;
    if (start != null && end != null && !end.isBefore(start)) {
      final total = end.difference(start).inDays + 1;
      final today = DateTime.now();
      final dayRaw =
          DateTime(
            today.year,
            today.month,
            today.day,
          ).difference(start).inDays +
          1;
      final day = dayRaw.clamp(1, total);
      progress = _SprintProgress(value: day / total, day: day, total: total);
    }

    final compact = context.isCompact;
    final nameBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sprint.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
        if ((sprint.goal ?? '').isNotEmpty)
          Text(
            sprint.goal!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
          ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.hairline),
      ),
      child: compact
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _ActivePill(),
                    const SizedBox(width: 12),
                    Expanded(child: nameBlock),
                  ],
                ),
                if (progress != null) ...[const SizedBox(height: 12), progress],
              ],
            )
          : Row(
              children: [
                const _ActivePill(),
                const SizedBox(width: 12),
                Expanded(child: nameBlock),
                if (progress != null) ...[
                  const SizedBox(width: 16),
                  SizedBox(width: 170, child: progress),
                ],
              ],
            ),
    );
  }
}

class _ActivePill extends StatelessWidget {
  const _ActivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.zap, size: 13, color: AppColors.accentStrong),
          const SizedBox(width: 4),
          Text(
            context.t('board.active'),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.accentStrong,
            ),
          ),
        ],
      ),
    );
  }
}

class _SprintProgress extends StatelessWidget {
  const _SprintProgress({
    required this.value,
    required this.day,
    required this.total,
  });
  final double value;
  final int day;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(child: HiveProgress(value: value, height: 6)),
        const SizedBox(width: 10),
        Text(
          context.t(
            'board.sprintDay',
            variables: {'day': '$day', 'total': '$total'},
          ),
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.inkSoft,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────── Backlog table header ─────────────────────────

/// Column header for the Backlog list, mirroring the Issues page columns.
class _BacklogTableHeader extends StatelessWidget {
  const _BacklogTableHeader();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: AppColors.inkFaint,
    );
    Widget cell(String key, {int? flex, double? width}) {
      final text = Text(
        context.t(key).toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
      if (width != null) return SizedBox(width: width, child: text);
      return Expanded(flex: flex!, child: text);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          cell('issues.colId', width: 76),
          const SizedBox(width: 12),
          cell('issues.colTitle', flex: 5),
          const SizedBox(width: 12),
          cell('issues.colStatus', flex: 3),
          const SizedBox(width: 8),
          cell('issues.colPriority', flex: 3),
          const SizedBox(width: 8),
          cell('issues.colAssignee', flex: 3),
          const SizedBox(width: 8),
          cell('issues.colDue', width: 60),
          const SizedBox(width: 18),
        ],
      ),
    );
  }
}

class _SprintSelector extends StatelessWidget {
  const _SprintSelector({
    required this.sprints,
    required this.selected,
    required this.onChanged,
  });

  final List<Sprint> sprints;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = selected != null
        ? sprints.where((s) => s.id == selected).firstOrNull?.name ??
              context.t('board.allSprints')
        : context.t('board.allSprints');
    return GlassPopupMenu<String?>(
      value: selected,
      onSelected: onChanged,
      items: [
        GlassMenuItem(value: null, label: context.t('board.allSprints')),
        for (final s in sprints) GlassMenuItem(value: s.id, label: s.name),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.zap, size: 15, color: AppColors.inkSoft),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 16, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}
