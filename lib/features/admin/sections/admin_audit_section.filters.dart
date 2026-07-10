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

  @override
  Widget build(BuildContext context) {
    final gutter = context.pageGutter;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      padding: EdgeInsets.only(top: context.topGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 0),
            child: Row(
              children: [
                Expanded(child: _searchField(context)),
                if (hasFilters) ...[
                  const SizedBox(width: 8),
                  _ClearButton(onTap: onClear),
                ],
              ],
            ),
          ),
          // Horizontally scrollable filter chips — never overflows on narrow
          // screens.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(gutter, 10, gutter, 12),
            child: Row(
              children: [
                _CountPill(total: total, loading: loading),
                const SizedBox(width: 8),
                _CategoryFilterChip(value: category, onSelected: onCategory),
                const SizedBox(width: 8),
                _SeverityFilterChip(value: severity, onSelected: onSeverity),
                const SizedBox(width: 8),
                _OutcomeFilterChip(value: outcome, onSelected: onOutcome),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: searchCtrl,
        onChanged: onSearch,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: 14, color: AppColors.ink),
        decoration: InputDecoration(
          isDense: true,
          hintText: context.t('audit.searchHint'),
          hintStyle: TextStyle(fontSize: 14, color: AppColors.inkFaint),
          prefixIcon: Icon(LucideIcons.search, size: 17, color: AppColors.inkFaint),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 38, minHeight: 38),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            borderSide: BorderSide(color: AppColors.hairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            borderSide: BorderSide(color: AppColors.accent, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        side: BorderSide(color: AppColors.hairline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(LucideIcons.filterX, size: 17, color: AppColors.inkSoft),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.total, required this.loading});
  final int total;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.history, size: 13, color: AppColors.accentStrong),
          const SizedBox(width: 6),
          Text(
            loading
                ? '…'
                : context.t('audit.count', variables: {'count': total}),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.accentStrong,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared visual for an inactive/active filter chip that anchors a glass menu.
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
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: active ? AppColors.accentSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(
            color: active ? AppColors.accentLine : AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              color: active ? AppColors.accentStrong : AppColors.ink,
            ),
          ),
          const SizedBox(width: 3),
          Icon(LucideIcons.chevronDown, size: 13, color: color),
        ],
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
            leading: Icon(LucideIcons.circle,
                size: 12, color: _severityColor(s)),
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
          leading: Icon(LucideIcons.circleCheck, size: 16, color: AppColors.success),
        ),
        GlassMenuItem(
          value: AuditOutcome.failure,
          label: context.t('audit.outcome.failure'),
          leading: Icon(LucideIcons.circleX, size: 16, color: AppColors.danger),
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

