import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/hinata_repository.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/audit_models.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../search/search_tokens.dart';

/// The admin **Audit log** — a live, filtered, infinite-scrolling timeline of
/// security-relevant events (sign-ins, role changes, settings updates…).
///
/// Self-contained: it owns its scroll, pagination and filter state, so the
/// admin shell renders it directly inside its content [Expanded] rather than
/// wrapping it in the shared `SingleChildScrollView` other sections use.
///
/// Data comes from `GET /api/v1/admin/audit` (newest-first, server-paginated);
/// entries are grouped under day headers and rendered as a vertical timeline
/// with severity-tinted glyphs. Tapping a row opens a liquid-glass detail sheet.
class AdminAuditSection extends StatefulWidget {
  const AdminAuditSection({super.key});

  @override
  State<AdminAuditSection> createState() => _AdminAuditSectionState();
}

class _AdminAuditSectionState extends State<AdminAuditSection> {
  static const int _perPage = 30;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  // Loaded data (accumulated across pages).
  final List<AuditEntry> _items = [];
  // Flattened render rows: either a [_DayHeader] or an [AuditEntry].
  List<Object> _rows = const [];
  int _total = 0;
  int _loadedPage = 0;

  // Filters.
  String _query = '';
  AuditCategory _category = AuditCategory.unknown;
  AuditSeverity _severity = AuditSeverity.unknown;
  AuditOutcome _outcome = AuditOutcome.unknown;

  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _error = false;
  // Monotonic token so a stale in-flight request can't overwrite newer state
  // (e.g. fast filter changes).
  int _requestId = 0;

  bool get _hasFilters =>
      _query.isNotEmpty ||
      _category != AuditCategory.unknown ||
      _severity != AuditSeverity.unknown ||
      _outcome != AuditOutcome.unknown;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 480 &&
        _hasMore &&
        !_loadingMore &&
        !_initialLoading) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    final page = reset ? 1 : _loadedPage + 1;
    final reqId = ++_requestId;

    if (reset) {
      setState(() {
        _initialLoading = true;
        _error = false;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final repo = context.read<HinataRepository>();
      final result = await repo.auditLog(
        query: _query,
        category: _category,
        severity: _severity,
        outcome: _outcome == AuditOutcome.unknown
            ? null
            : _outcome.name.toUpperCase(),
        page: page,
        perPage: _perPage,
      );
      if (!mounted || reqId != _requestId) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(result.items);
        _total = result.total;
        _loadedPage = result.page;
        _rebuildRows();
        _initialLoading = false;
        _loadingMore = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted || reqId != _requestId) return;
      setState(() {
        _initialLoading = false;
        _loadingMore = false;
        if (reset) _error = true;
      });
    }
  }

  /// Collapse the accumulated [_items] into a flat list with day-break headers.
  void _rebuildRows() {
    final rows = <Object>[];
    DateTime? lastDay;
    for (final e in _items) {
      final day = DateUtils.dateOnly(e.timestamp);
      if (lastDay == null || day != lastDay) {
        rows.add(_DayHeader(day));
        lastDay = day;
      }
      rows.add(e);
    }
    _rows = rows;
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      final next = value.trim();
      if (next == _query) return;
      _query = next;
      _load(reset: true);
    });
  }

  void _setCategory(AuditCategory v) {
    if (v == _category) return;
    setState(() => _category = v);
    _load(reset: true);
  }

  void _setSeverity(AuditSeverity v) {
    if (v == _severity) return;
    setState(() => _severity = v);
    _load(reset: true);
  }

  void _setOutcome(AuditOutcome v) {
    if (v == _outcome) return;
    setState(() => _outcome = v);
    _load(reset: true);
  }

  void _clearFilters() {
    _searchCtrl.clear();
    _debounce?.cancel();
    setState(() {
      _query = '';
      _category = AuditCategory.unknown;
      _severity = AuditSeverity.unknown;
      _outcome = AuditOutcome.unknown;
    });
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FilterBar(
          searchCtrl: _searchCtrl,
          onSearch: _onSearchChanged,
          category: _category,
          severity: _severity,
          outcome: _outcome,
          total: _total,
          hasFilters: _hasFilters,
          loading: _initialLoading,
          onCategory: _setCategory,
          onSeverity: _setSeverity,
          onOutcome: _setOutcome,
          onClear: _clearFilters,
        ),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_initialLoading) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(48), child: HiveLoader()),
      );
    }
    if (_error) {
      return _ErrorView(onRetry: () => _load(reset: true));
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(reset: true),
        color: AppColors.accentStrong,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
              context.pageGutter, 24, context.pageGutter, 24 + context.bottomGutter),
          children: [
            HiveEmptyState(
              title: context.t(
                  _hasFilters ? 'audit.empty.filtered' : 'audit.empty.title'),
              message:
                  _hasFilters ? null : context.t('audit.empty.message'),
              action: _hasFilters
                  ? OutlinedButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(LucideIcons.x, size: 15),
                      label: Text(context.t('audit.filter.reset')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: BorderSide(color: AppColors.hairline),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      );
    }

    final gutter = context.pageGutter;
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      color: AppColors.accentStrong,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            gutter, 12, gutter, 16 + context.bottomGutter),
        // +1 footer row (load-more spinner / end marker).
        itemCount: _rows.length + 1,
        itemBuilder: (context, index) {
          if (index == _rows.length) return _buildFooter(context);
          final row = _rows[index];
          if (row is _DayHeader) {
            return _DayHeaderRow(day: row.day);
          }
          final entry = row as AuditEntry;
          // Continuous timeline rail unless the next row starts a new day.
          final isLastInGroup = index + 1 >= _rows.length ||
              _rows[index + 1] is _DayHeader;
          return _AuditTimelineTile(
            entry: entry,
            isLastInGroup: isLastInGroup,
            onTap: () => showAuditDetailSheet(context, entry),
          );
        },
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: HiveLoader(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!_hasMore && _items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.check, size: 13, color: AppColors.inkFaint),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                context.t('audit.endOfList'),
                style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}

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

// ─────────────────────────── Day header ──────────────────────────────────

class _DayHeader {
  const _DayHeader(this.day);
  final DateTime day;
}

class _DayHeaderRow extends StatelessWidget {
  const _DayHeaderRow({required this.day});
  final DateTime day;

  String _label(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final diff = today.difference(day).inDays;
    if (diff == 0) return context.t('audit.today');
    if (diff == 1) return context.t('audit.yesterday');
    final locale = Localizations.localeOf(context).toString();
    return DateFormat('EEEE, d MMM y', locale).format(day);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Row(
        children: [
          Text(
            _label(context).toUpperCase(),
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(height: 1, color: AppColors.hairline),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Timeline tile ───────────────────────────────

class _AuditTimelineTile extends StatelessWidget {
  const _AuditTimelineTile({
    required this.entry,
    required this.isLastInGroup,
    required this.onTap,
  });

  final AuditEntry entry;
  final bool isLastInGroup;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = _severityColor(entry.severity);
    final failed = entry.outcome == AuditOutcome.failure;
    final glyphTint = failed ? AppColors.danger : tint;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Timeline rail: glyph + connecting line ──
          SizedBox(
            width: 44,
            child: Column(
              children: [
                _GlyphBadge(
                  icon: _actionIcon(entry.action),
                  tint: glyphTint,
                ),
                if (!isLastInGroup)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 2,
                        color: AppColors.hairline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // ── Content card ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _card(context, glyphTint, failed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Color tint, bool failed) {
    final locale = Localizations.localeOf(context).toString();
    final time = DateFormat.Hm(locale).format(entry.timestamp);
    final subtitle = _actorTargetLine(context, entry);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppColors.hairline),
          ),
          padding: const EdgeInsets.fromLTRB(13, 11, 11, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      context.t('audit.action.${entry.action}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      time,
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkSoft,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _MiniChip(
                    icon: _categoryIcon(entry.category),
                    label: context.t('audit.category.${entry.category.name}'),
                  ),
                  if (failed)
                    _MiniChip(
                      icon: LucideIcons.circleX,
                      label: context.t('audit.outcome.failure'),
                      color: AppColors.danger,
                    )
                  else if (entry.severity == AuditSeverity.warning)
                    _MiniChip(
                      icon: LucideIcons.triangleAlert,
                      label: context.t('audit.severity.warning'),
                      color: AppColors.warning,
                    ),
                  if (entry.ip != null && entry.ip!.isNotEmpty)
                    _MiniChip(
                      icon: LucideIcons.mapPin,
                      label: entry.ip!,
                      mono: true,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlyphBadge extends StatelessWidget {
  const _GlyphBadge({required this.icon, required this.tint});
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Icon(icon, size: 17, color: tint),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    this.color,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.inkSoft;
    final bg = color == null
        ? AppColors.surfaceMuted
        : color!.withValues(alpha: 0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: color == null
            ? Border.all(color: AppColors.hairline2)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: mono ? AppTheme.fontMono : null,
              fontSize: mono ? 10.5 : 11,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Error view ──────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.cloudOff, size: 40, color: AppColors.inkFaint),
            const SizedBox(height: 14),
            Text(
              context.t('audit.error'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkSoft, fontSize: 14),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw, size: 15),
              label: Text(context.t('audit.retry')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                side: BorderSide(color: AppColors.hairline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Detail sheet ────────────────────────────────

/// Opens a liquid-glass bottom sheet with the full record for [entry].
Future<void> showAuditDetailSheet(BuildContext context, AuditEntry entry) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (_) => _AuditDetailSheet(entry: entry),
  );
}

class _AuditDetailSheet extends StatelessWidget {
  const _AuditDetailSheet({required this.entry});
  final AuditEntry entry;

  static const double _radius = 24;

  @override
  Widget build(BuildContext context) {
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final locale = Localizations.localeOf(context).toString();
    final failed = entry.outcome == AuditOutcome.failure;
    final tint =
        failed ? AppColors.danger : _severityColor(entry.severity);

    final when = DateFormat.yMMMMEEEEd(locale).add_Hms().format(entry.timestamp);

    final rows = <Widget>[
      _DetailRow(
        icon: LucideIcons.user,
        label: context.t('audit.detail.actor'),
        value: entry.actorLabel?.isNotEmpty == true
            ? entry.actorLabel!
            : context.t('audit.actor.system'),
        sub: entry.actorId,
        tokens: tokens,
      ),
      if (entry.targetLabel?.isNotEmpty == true || entry.targetId != null)
        _DetailRow(
          icon: LucideIcons.target,
          label: context.t('audit.detail.target'),
          value: entry.targetLabel?.isNotEmpty == true
              ? entry.targetLabel!
              : (entry.targetId ?? '—'),
          sub: entry.targetLabel?.isNotEmpty == true ? entry.targetId : null,
          tokens: tokens,
        ),
      _DetailRow(
        icon: LucideIcons.clock,
        label: context.t('audit.detail.when'),
        value: when,
        tokens: tokens,
      ),
      _DetailRow(
        icon: LucideIcons.layers,
        label: context.t('audit.detail.category'),
        value: context.t('audit.category.${entry.category.name}'),
        tokens: tokens,
      ),
      _DetailRow(
        icon: LucideIcons.signal,
        label: context.t('audit.detail.severity'),
        value: context.t('audit.severity.${entry.severity.name}'),
        valueColor: _severityColor(entry.severity),
        tokens: tokens,
      ),
      _DetailRow(
        icon: failed ? LucideIcons.circleX : LucideIcons.circleCheck,
        label: context.t('audit.detail.outcome'),
        value: context.t('audit.outcome.${entry.outcome.name}'),
        valueColor: failed ? AppColors.danger : AppColors.success,
        tokens: tokens,
      ),
      if (entry.ip != null && entry.ip!.isNotEmpty)
        _DetailRow(
          icon: LucideIcons.mapPin,
          label: context.t('audit.detail.ip'),
          value: entry.ip!,
          mono: true,
          tokens: tokens,
        ),
      if (entry.userAgent != null && entry.userAgent!.isNotEmpty)
        _DetailRow(
          icon: LucideIcons.monitorSmartphone,
          label: context.t('audit.detail.device'),
          value: entry.userAgent!,
          tokens: tokens,
        ),
    ];

    final panel = GlassPanelShadow(
      radius: BorderRadius.circular(_radius),
      shadows: tokens.panelShadow,
      child: GlassContainer(
        useOwnLayer: true,
        quality: GlassQuality.premium,
        clipBehavior: Clip.antiAlias,
        shape: const LiquidRoundedSuperellipse(borderRadius: _radius),
        settings: liquidGlassPanelSettings(glassFill: tokens.glassFill, dark: dark),
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.82,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                  child: Row(
                    children: [
                      _GlyphBadge(
                        icon: _actionIcon(entry.action),
                        tint: tint,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.t('audit.action.${entry.action}'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: tokens.ink,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.t('audit.detail.title'),
                              style: TextStyle(
                                  fontSize: 12, color: tokens.inkFaint),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(LucideIcons.x, size: 18, color: tokens.inkSoft),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
                    children: [
                      ...rows,
                      if (entry.metadata.isNotEmpty)
                        _MetadataBlock(metadata: entry.metadata, tokens: tokens),
                    ],
                  ),
                ),
                _EventIdFooter(id: entry.id, tokens: tokens),
                // Bottom safe-area inset is added by the wrapping SafeArea.
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: panel,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.tokens,
    this.sub,
    this.valueColor,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;
  final bool mono;
  final SearchTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Icon(icon, size: 16, color: tokens.inkFaint),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: tokens.inkFaint,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: TextStyle(
                    fontFamily: mono ? AppTheme.fontMono : null,
                    fontSize: mono ? 13 : 13.5,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? tokens.ink,
                    height: 1.3,
                  ),
                ),
                if (sub != null && sub!.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    sub!,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11,
                      color: tokens.inkFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataBlock extends StatelessWidget {
  const _MetadataBlock({required this.metadata, required this.tokens});
  final Map<String, String> metadata;
  final SearchTokens tokens;

  String _label(BuildContext context, String key) {
    final translated = context.t('audit.meta.$key');
    if (translated != 'audit.meta.$key') return translated;
    // Humanise an unknown camelCase / snake_case key.
    final spaced = key
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll('_', ' ');
    return spaced.isEmpty
        ? key
        : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final entries = metadata.entries.toList();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('audit.detail.metadata').toUpperCase(),
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: tokens.inkFaint,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: tokens.field,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.hairline),
            ),
            child: Column(
              children: [
                for (int i = 0; i < entries.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, color: tokens.hairline, thickness: 1),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(
                            _label(context, entries[i].key),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: tokens.inkSoft,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 5,
                          child: SelectableText(
                            entries[i].value,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: tokens.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventIdFooter extends StatelessWidget {
  const _EventIdFooter({required this.id, required this.tokens});
  final String id;
  final SearchTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 10, 0),
      child: Row(
        children: [
          Icon(LucideIcons.hash, size: 13, color: tokens.inkFaint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              id,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 11,
                color: tokens.inkFaint,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: id));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.t('audit.detail.copied')),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            icon: Icon(LucideIcons.copy, size: 14, color: tokens.inkSoft),
            label: Text(
              context.t('audit.detail.copyId'),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: tokens.inkSoft),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Visual mappings ─────────────────────────────

Color _severityColor(AuditSeverity s) => switch (s) {
      AuditSeverity.info => AppColors.stTodo,
      AuditSeverity.notice => AppColors.accent,
      AuditSeverity.warning => AppColors.danger,
      AuditSeverity.unknown => AppColors.inkSoft,
    };

IconData _categoryIcon(AuditCategory c) => switch (c) {
      AuditCategory.authentication => LucideIcons.logIn,
      AuditCategory.account => LucideIcons.circleUser,
      AuditCategory.administration => LucideIcons.shieldCheck,
      AuditCategory.configuration => LucideIcons.settings,
      AuditCategory.data => LucideIcons.database,
      AuditCategory.integration => LucideIcons.plug,
      AuditCategory.unknown => LucideIcons.activity,
    };

/// Per-action glyph. Falls back to the action's category glyph for any future
/// action not listed here (keeps the UI forward-compatible with new events).
IconData _actionIcon(String action) => switch (action) {
      'LOGIN_SUCCESS' => LucideIcons.logIn,
      'LOGIN_FAILURE' => LucideIcons.circleX,
      'LOGIN_BLOCKED' => LucideIcons.ban,
      'MFA_FAILURE' => LucideIcons.shieldX,
      'SSO_LOGIN' => LucideIcons.fingerprint,
      'SESSION_REVOKED' => LucideIcons.monitorX,
      'PASSWORD_CHANGED' => LucideIcons.keyRound,
      'PASSWORD_RESET_REQUESTED' => LucideIcons.mailQuestion,
      'PASSWORD_RESET_COMPLETED' => LucideIcons.keyRound,
      'EMAIL_CHANGE_REQUESTED' => LucideIcons.mail,
      'EMAIL_CHANGED' => LucideIcons.mailCheck,
      'TWO_FACTOR_ENABLED' => LucideIcons.shieldCheck,
      'TWO_FACTOR_DISABLED' => LucideIcons.shieldOff,
      'RECOVERY_CODES_REGENERATED' => LucideIcons.refreshCw,
      'ACCOUNT_DELETED' => LucideIcons.userX,
      'USER_INVITED' => LucideIcons.userPlus,
      'USER_CREATED' => LucideIcons.userPlus,
      'USER_ROLE_CHANGED' => LucideIcons.userCog,
      'USER_ACTIVATED' => LucideIcons.userCheck,
      'USER_DEACTIVATED' => LucideIcons.userMinus,
      'USER_DELETED' => LucideIcons.userX,
      'USER_PASSWORD_RESET_SENT' => LucideIcons.keyRound,
      'USER_SESSIONS_REVOKED' => LucideIcons.monitorX,
      'SETTINGS_CHANGED' => LucideIcons.sliders,
      'DATA_EXPORT_REQUESTED' => LucideIcons.download,
      _ => LucideIcons.history,
    };

/// Human "actor → target" line for the card subtitle. Returns null when there
/// is nothing meaningful to show beyond the action title itself.
String? _actorTargetLine(BuildContext context, AuditEntry entry) {
  final actor = entry.actorLabel?.isNotEmpty == true
      ? entry.actorLabel!
      : context.t('audit.actor.system');
  final target = entry.targetLabel?.isNotEmpty == true
      ? entry.targetLabel!
      : null;
  if (target != null && target != actor) return '$actor → $target';
  return actor;
}
