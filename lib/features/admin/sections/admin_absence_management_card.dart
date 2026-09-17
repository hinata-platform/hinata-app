import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/core_models.dart';
import '../../../core/repositories/user_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hive_widgets.dart' show HiveAvatar;
import '../../../core/widgets/person_picker.dart';
import '../admin_form_helpers.dart';
import '../policy_controls.dart';

/// Admin → Zeiterfassung → Abwesenheitsmanagement 2.0.
///
/// Two things, and they belong together. The switch that brings the module into
/// existence — absence types with their own rules, yearly entitlements,
/// balances, and from A2 requests and approvals — and the people who keep it
/// for everybody.
///
/// **Why its own switch.** The module has its own routes, its own screens and
/// its own notifications, and an instance that only records project time has no
/// use for them. Holiday principles and the holiday plan are subject to
/// co-determination under § 87 Abs. 1 Nr. 5 BetrVG — a paragraph of its own
/// beside the Nr. 6 that covers the time tracking around it — so it is not a
/// detail of the switch above and does not hide inside it.
///
/// **Why it needs the module above it.** Every day it counts comes from a
/// working pattern, a holiday calendar and the capacity built on them, and all
/// three belong to the extended time-tracking module. With that off this stays
/// stored but cannot take effect, and the note says so rather than letting
/// somebody wonder why nothing appeared.
class AdminAbsenceManagementCard extends StatefulWidget {
  const AdminAbsenceManagementCard({
    super.key,
    required this.enabled,
    required this.effective,
    required this.advancedOn,
    required this.managers,
    required this.onEnabledChanged,
    required this.onManagersChanged,
  });

  /// What an administrator stored; null means the environment decides.
  final bool? enabled;

  /// What the switch currently resolves to, as the server reports it.
  final bool? effective;

  /// Whether the extended time-tracking module is on. While it is not, this
  /// module cannot take effect whatever this switch says.
  final bool advancedOn;

  /// The user ids an operator named as keepers. Empty means administrators.
  final List<String> managers;

  final ValueChanged<bool?> onEnabledChanged;
  final ValueChanged<List<String>> onManagersChanged;

  @override
  State<AdminAbsenceManagementCard> createState() =>
      _AdminAbsenceManagementCardState();
}

class _AdminAbsenceManagementCardState
    extends State<AdminAbsenceManagementCard> {
  /// Names for the ids we hold, so a chip reads as a person rather than as an
  /// object id. Filled from the directory once and topped up by the picker.
  final Map<String, DirectoryUser> _people = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadNames();
  }

  @override
  void didUpdateWidget(AdminAbsenceManagementCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.managers != widget.managers) _loadNames();
  }

  Future<void> _loadNames() async {
    final missing = widget.managers
        .where((id) => !_people.containsKey(id))
        .toList(growable: false);
    if (missing.isEmpty || _loading) return;
    setState(() => _loading = true);
    try {
      final found = await context.read<UserRepository>().usersByIds(missing);
      if (!mounted) return;
      setState(() {
        for (final person in found) {
          _people[person.id] = person;
        }
      });
    } catch (_) {
      // A name that cannot be read is not worth an error on a settings screen:
      // the chip falls back to the id, which is still removable.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add(BuildContext context, Rect anchor) async {
    final picked = await showPersonPicker(context, anchorRect: anchor);
    if (picked == null || widget.managers.contains(picked.id)) return;
    _people[picked.id] = picked;
    widget.onManagersChanged([...widget.managers, picked.id]);
  }

  void _remove(String id) => widget.onManagersChanged(
    widget.managers.where((each) => each != id).toList(growable: false),
  );

  @override
  Widget build(BuildContext context) {
    return AdminSectionCard(
      icon: LucideIcons.calendarOff,
      title: context.t('admin.absence.title'),
      subtitle: context.t('admin.absence.hint'),
      children: [
        PolicySwitch(
          title: context.t('admin.absence.enabledTitle'),
          description: context.t('admin.absence.enabledHint'),
          value: widget.enabled,
          effective: widget.effective,
          onChanged: widget.onEnabledChanged,
          // § 87 Abs. 1 Nr. 5 BetrVG rather than Nr. 6: holiday principles and
          // the holiday plan are co-determined in their own right.
          monitoring: true,
        ),
        if (!widget.advancedOn)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: AdminNote(
              icon: LucideIcons.triangleAlert,
              tone: AdminNoteTone.warning,
              text: context.t('admin.absence.needsAdvanced'),
            ),
          ),
        const SizedBox(height: 8),
        _keepers(context),
      ],
    );
  }

  Widget _keepers(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.t('admin.absence.keepersTitle'),
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(color: AppColors.ink),
      ),
      const SizedBox(height: 4),
      Text(
        context.t('admin.absence.keepersHint'),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final id in widget.managers) _chip(context, id),
          _addButton(context),
        ],
      ),
      if (widget.managers.isEmpty) ...[
        const SizedBox(height: 10),
        AdminNote(
          icon: LucideIcons.shieldCheck,
          tone: AdminNoteTone.info,
          text: context.t('admin.absence.keepersEmpty'),
        ),
      ],
    ],
  );

  Widget _chip(BuildContext context, String id) {
    final person = _people[id];
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HiveAvatar(
            name: person?.displayName ?? id,
            imageUrl: person?.avatarUrl,
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(
            person?.displayName ?? id,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.ink),
          ),
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 14),
            color: AppColors.inkSoft,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            tooltip: context.t('common.remove'),
            onPressed: () => _remove(id),
          ),
        ],
      ),
    );
  }

  Widget _addButton(BuildContext context) => Builder(
    builder: (anchorContext) => OutlinedButton.icon(
      icon: const Icon(LucideIcons.userPlus, size: 16),
      label: Text(context.t('admin.absence.keepersAdd')),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: BorderSide(color: AppColors.hairline2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        ),
      ),
      onPressed: () {
        final box = anchorContext.findRenderObject() as RenderBox?;
        if (box == null) return;
        final origin = box.localToGlobal(Offset.zero);
        _add(anchorContext, origin & box.size);
      },
    ),
  );
}
