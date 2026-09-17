import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/absence_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart' show HiveSwitch;
import '../../core/widgets/soft_card.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart';
import 'absence_labels.dart';
import 'absence_type_sheet.dart';

/// Admin → Absence types (HIN-116): the catalogue an operator keeps.
///
/// A page of its own rather than a card, because a type carries two dozen rules
/// and a list of them does not fit a form that saves as a whole. Each row saves
/// on its own, the way a holiday does.
///
/// Three built-ins — vacation, sickness, other — arrive with the module and
/// cannot be deleted. They ship *without* a name: the label comes from the
/// reader's language, so a German instance does not read "Vacation" until
/// somebody renames three rows.
class AbsenceTypesScreen extends StatefulWidget {
  const AbsenceTypesScreen({super.key});

  @override
  State<AbsenceTypesScreen> createState() => _AbsenceTypesScreenState();
}

class _AbsenceTypesScreenState extends State<AbsenceTypesScreen> {
  List<AbsenceType> _types = const [];
  bool _loading = true;
  bool _showInactive = false;
  String? _errorKey;

  AbsenceRepository get _repository => context.read<AbsenceRepository>();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      // Always asked for everything: the switch below filters what is drawn, so
      // flipping it is instant rather than a round trip, and a keeper is the
      // only one the server answers it for anyway.
      final types = await _repository.types(includeInactive: true);
      if (!mounted) return;
      setState(() {
        _types = types;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = failure.message;
      });
    }
  }

  List<AbsenceType> get _visible => _showInactive
      ? _types
      : _types.where((type) => type.active).toList(growable: false);

  Future<void> _edit(AbsenceType? existing) async {
    final saved = await showAbsenceTypeSheet(context, existing: existing);
    if (saved == true && mounted) unawaited(_load());
  }

  Future<void> _delete(AbsenceType type) async {
    final name = absenceTypeName(context, type);
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('absence.types.delete'),
      message: context.t(
        'absence.types.deleteConfirm',
        variables: {'name': name},
      ),
      confirmLabel: context.t('common.delete'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repository.deleteType(type.id);
      if (!mounted) return;
      showGlassToast(context, context.t('absence.types.deleted'));
      unawaited(_load());
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      // A type somebody has already booked against is switched off, not
      // deleted, and the server's sentence says exactly that.
      showGlassErrorToast(context, context.t(failure.message));
    }
  }

  @override
  Widget build(BuildContext context) => PageChrome(
    // One φ² column. Published here rather than bounded in the body, so the
    // sub-page bar is laid out in the same width and the plus button sits on
    // the cards' own edge instead of the window's.
    contentMax: Breakpoints.mediumMax,
    title: context.t('absence.types.pageTitle'),
    actions: [
      PageAction(
        icon: LucideIcons.plus,
        label: context.t('absence.types.new'),
        primary: true,
        onTap: (_) => unawaited(_edit(null)),
      ),
      // The other half of the module, so the two pages reach each other rather
      // than only being reachable from the admin card.
      PageAction(
        icon: LucideIcons.usersRound,
        label: context.t('absence.entitlements.open'),
        onTap: (_) => context.go('/absences/entitlements'),
      ),
    ],
    child: _body(context),
  );

  Widget _body(BuildContext context) {
    if (_loading && _types.isEmpty) {
      return const Center(child: HiveLoader());
    }
    if (_errorKey != null && _types.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: HiveEmptyState(
            title: context.t('absence.types.pageTitle'),
            message: context.t(_errorKey!),
            action: OutlinedButton(
              onPressed: () => unawaited(_load()),
              child: Text(context.t('common.retry')),
            ),
          ),
        ),
      );
    }
    final visible = _visible;
    return RefreshIndicator(
      onRefresh: _load,
      edgeOffset: context.topGutter,
      child: ListView(
        padding: context.pagePadding,
        children: [
          Text(
            context.t('absence.types.intro'),
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          _retiredSwitch(context),
          const SizedBox(height: 10),
          if (visible.isEmpty)
            HiveEmptyState(
              title: context.t('absence.types.empty'),
              message: context.t('absence.types.emptyMessage'),
              action: FilledButton.icon(
                onPressed: () => unawaited(_edit(null)),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: Text(context.t('absence.types.new')),
              ),
            )
          else
            // A concrete list, not a builder: the server caps the catalogue at
            // fifty types, so this never becomes the long list that needs one.
            for (final type in visible) ...[
              _TypeCard(
                type: type,
                onEdit: () => unawaited(_edit(type)),
                onDelete: type.isSystem ? null : () => unawaited(_delete(type)),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _retiredSwitch(BuildContext context) {
    final retired = _types.where((type) => !type.active).length;
    // Only offered when there is something behind it: a switch that reveals
    // nothing is a switch somebody tries twice.
    if (retired == 0) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: Text(
            context.t('absence.types.showInactive'),
            style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
          ),
        ),
        HiveSwitch(
          value: _showInactive,
          onChanged: (value) => setState(() => _showInactive = value),
        ),
      ],
    );
  }
}

/// One type in the list: what it is called, what it costs a balance, and the
/// two or three rules somebody scanning the page is actually looking for.
class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.type, required this.onEdit, this.onDelete});

  final AbsenceType type;
  final VoidCallback onEdit;

  /// Null for a built-in: the three the module ships cannot be deleted, and an
  /// icon that only ever explains why it refused is worse than no icon.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colour = absenceColor(context, type.hue);
    return SoftCard(
      onTap: onEdit,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(absenceIcon(type.icon), size: 17, color: colour),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      absenceTypeName(context, type),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    if (type.isSystem)
                      _Badge(context.t('absence.types.system')),
                    if (!type.active)
                      _Badge(
                        context.t('absence.types.inactive'),
                        tone: AppColors.inkFaint,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _summary(context),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.t('absence.types.edit'),
            onPressed: onEdit,
            icon: Icon(LucideIcons.pencil, size: 17, color: AppColors.inkSoft),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: context.t('absence.types.delete'),
              onPressed: onDelete,
              icon: Icon(
                LucideIcons.trash2,
                size: 17,
                color: AppColors.inkSoft,
              ),
            ),
        ],
      ),
    );
  }

  /// The line under the name: category, then what it does to a balance, then
  /// approval — in that order, because that is the order somebody asks.
  String _summary(BuildContext context) {
    final parts = <String>[
      context.t(type.kind.labelKey),
      if (type.unlimited)
        context.t('absence.types.unlimited')
      else if (type.countsAgainstBalance)
        daysLabel(context, type.allowanceMilliDays),
      if (type.requiresApproval) context.t('absence.types.approval'),
    ];
    // A middle dot, not a comma: these are three facts, not a sentence.
    return parts.join('  ·  ');
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.tone});

  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: (tone ?? AppColors.accentStrong).withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: tone ?? AppColors.accentStrong,
      ),
    ),
  );
}
