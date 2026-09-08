part of 'admin_audit_section.dart';

// ─────────────────────────── Filter bar ──────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchCtrl,
    required this.onSearch,
    required this.category,
    required this.severity,
    required this.outcome,
    required this.total,
    required this.hasFilters,
    required this.loading,
    required this.onCategory,
    required this.onSeverity,
    required this.onOutcome,
    required this.onClear,
    required this.compact,
    required this.searching,
    required this.onOpenSearch,
    required this.onCloseSearch,
  });

  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearch;
  final AuditCategory category;
  final AuditSeverity severity;
  final AuditOutcome outcome;
  final int total;
  final bool hasFilters;
  final bool loading;
  final ValueChanged<AuditCategory> onCategory;
  final ValueChanged<AuditSeverity> onSeverity;
  final ValueChanged<AuditOutcome> onOutcome;
  final VoidCallback onClear;
  final bool compact;

  /// Whether the phone's one docked row is showing the search field instead of
  /// the chips. See [GlassSearchDock].
  final bool searching;
  final VoidCallback onOpenSearch;
  final VoidCallback onCloseSearch;

  @override
  Widget build(BuildContext context) {
    final gutter = context.pageGutter;
    final search = GlassSearchField(
      hint: context.t('audit.searchHint'),
      controller: searchCtrl,
      onChanged: onSearch,
    );
    final chipRow = Row(
      children: [
        if (compact) ...[
          GlassSearchButton(
            tooltip: context.t('audit.searchHint'),
            active: searchCtrl.text.isNotEmpty,
            onTap: onOpenSearch,
          ),
          const SizedBox(width: 8),
        ],
        GlassCountPill(
          label: loading
              ? '…'
              : context.t('audit.count', variables: {'count': total}),
        ),
        const SizedBox(width: 8),
        _CategoryFilterChip(value: category, onSelected: onCategory),
        const SizedBox(width: 8),
        _SeverityFilterChip(value: severity, onSelected: onSeverity),
        const SizedBox(width: 8),
        _OutcomeFilterChip(value: outcome, onSelected: onOutcome),
        if (hasFilters) ...[
          const SizedBox(width: 8),
          _ClearButton(onTap: onClear),
        ],
      ],
    );

    if (compact) {
      // One line, because that is all a page gets: the app bar's own title row
      // plus one docked row. The search used to take a row of its own above the
      // chips, which made three lines of chrome before the first event — so it
      // is a pill in the row now, and takes the row over only while somebody is
      // typing in it.
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        child: Align(
          child: GlassSearchDock(
            searching: searching,
            controller: searchCtrl,
            hint: context.t('audit.searchHint'),
            onChanged: onSearch,
            onClose: onCloseSearch,
            controls: SizedBox(
              height: kGlassControlHeight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // The gutter is spent above; inside the scroller it would clip
                // the last chip instead of letting it come into view.
                clipBehavior: Clip.none,
                child: chipRow,
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: Row(
        children: [
          SizedBox(width: 320, child: search),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: chipRow,
            ),
          ),
        ],
      ),
    );
  }
}

/// A glass "clear filters" pill (icon-only), matched to the chip height.
class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPill(
      onTap: onTap,
      child: SizedBox(
        width: kGlassPillHeight,
        child: Icon(LucideIcons.filterX, size: 17, color: AppColors.inkSoft),
      ),
    );
  }
}

/// Shared visual for an inactive/active filter chip that anchors a glass menu —
/// a real [GlassPill] (glass on native / frosted on web).
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accentStrong : AppColors.inkSoft;
    return GlassPill(
      active: active,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? AppColors.accentStrong : AppColors.ink,
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 13, color: color),
          ],
        ),
      ),
    );
  }
}

class _CategoryFilterChip extends StatelessWidget {
  const _CategoryFilterChip({required this.value, required this.onSelected});
  final AuditCategory value;
  final ValueChanged<AuditCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final active = value != AuditCategory.unknown;
    return GlassPopupMenu<AuditCategory>(
      value: value,
      onSelected: onSelected,
      items: [
        GlassMenuItem(
          value: AuditCategory.unknown,
          label: context.t('audit.filter.allCategories'),
          leading: Icon(LucideIcons.layers, size: 16, color: AppColors.inkSoft),
        ),
        for (final c in const [
          AuditCategory.authentication,
          AuditCategory.account,
          AuditCategory.administration,
          AuditCategory.configuration,
          AuditCategory.data,
          AuditCategory.integration,
        ])
          GlassMenuItem(
            value: c,
            label: context.t('audit.category.${c.name}'),
            leading: Icon(_categoryIcon(c), size: 16, color: AppColors.inkSoft),
          ),
      ],
      child: _FilterChip(
        icon: LucideIcons.layers,
        label: active
            ? context.t('audit.category.${value.name}')
            : context.t('audit.filter.category'),
        active: active,
      ),
    );
  }
}

class _SeverityFilterChip extends StatelessWidget {
  const _SeverityFilterChip({required this.value, required this.onSelected});
  final AuditSeverity value;
  final ValueChanged<AuditSeverity> onSelected;

  @override
  Widget build(BuildContext context) {
    final active = value != AuditSeverity.unknown;
    return GlassPopupMenu<AuditSeverity>(
      value: value,
      onSelected: onSelected,
      items: [
        GlassMenuItem(
          value: AuditSeverity.unknown,
          label: context.t('audit.filter.allSeverities'),
          leading: Icon(LucideIcons.signal, size: 16, color: AppColors.inkSoft),
        ),
        for (final s in const [
          AuditSeverity.info,
          AuditSeverity.notice,
          AuditSeverity.warning,
        ])
          GlassMenuItem(
            value: s,
            label: context.t('audit.severity.${s.name}'),
            leading: Icon(
              LucideIcons.circle,
              size: 12,
              color: _severityColor(s),
            ),
          ),
      ],
      child: _FilterChip(
        icon: LucideIcons.signal,
        label: active
            ? context.t('audit.severity.${value.name}')
            : context.t('audit.filter.severity'),
        active: active,
      ),
    );
  }
}

class _OutcomeFilterChip extends StatelessWidget {
  const _OutcomeFilterChip({required this.value, required this.onSelected});
  final AuditOutcome value;
  final ValueChanged<AuditOutcome> onSelected;

  @override
  Widget build(BuildContext context) {
    final active = value != AuditOutcome.unknown;
    return GlassPopupMenu<AuditOutcome>(
      value: value,
      onSelected: onSelected,
      items: [
        GlassMenuItem(
          value: AuditOutcome.unknown,
          label: context.t('audit.filter.allOutcomes'),
          leading: Icon(LucideIcons.equal, size: 16, color: AppColors.inkSoft),
        ),
        GlassMenuItem(
          value: AuditOutcome.success,
          label: context.t('audit.outcome.success'),
          leading: const Icon(
            LucideIcons.circleCheck,
            size: 16,
            color: AppColors.success,
          ),
        ),
        GlassMenuItem(
          value: AuditOutcome.failure,
          label: context.t('audit.outcome.failure'),
          leading: const Icon(
            LucideIcons.circleX,
            size: 16,
            color: AppColors.danger,
          ),
        ),
      ],
      child: _FilterChip(
        icon: LucideIcons.circleDot,
        label: active
            ? context.t('audit.outcome.${value.name}')
            : context.t('audit.filter.outcome'),
        active: active,
      ),
    );
  }
}
