import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/core_models.dart' show PlatformFlags;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../sprint/modals/glass_modal.dart' show showGlassErrorToast;
import '../admin_form_helpers.dart';

/// App/client settings served to the apps via /api/v1/meta: the minimum
/// required app version, the privacy policy URL and optional feature flags.
class AdminAppSection extends StatefulWidget {
  const AdminAppSection({
    super.key,
    required this.settings,
    this.onOpenTimeTracking,
  });

  final Map<String, dynamic> settings;

  /// Opens Adminbereich → Zeiterfassung. The extended time-tracking flag is
  /// derived from that module's own settings, so this section can only point at
  /// it — a switch here would write somewhere the server does not read.
  final VoidCallback? onOpenTimeTracking;

  @override
  State<AdminAppSection> createState() => _AdminAppSectionState();
}

class _AdminAppSectionState extends State<AdminAppSection> {
  Map<String, dynamic> get _app =>
      (widget.settings['app'] ??= <String, dynamic>{}) as Map<String, dynamic>;

  Map<String, dynamic> get _flags =>
      (_app['featureFlags'] ??= <String, dynamic>{}) as Map<String, dynamic>;

  /// Read-only here — the section that owns these values is Zeiterfassung.
  Map<String, dynamic> get _timeTracking =>
      widget.settings['timeTracking'] is Map<String, dynamic>
      ? widget.settings['timeTracking'] as Map<String, dynamic>
      : const {};

  /// Flags that have a dedicated, described toggle above — hidden from the raw
  /// name→enabled editor so they aren't shown twice, and blocked from being
  /// re-created there by name. `advanced_time_tracking` is in the list for the
  /// second reason above all: the server derives it from the time-tracking
  /// module's own settings, so a hand-typed flag of that name would sit in the
  /// document looking authoritative and change nothing.
  static const _dedicatedFlags = {
    PlatformFlags.multiAssignee,
    PlatformFlags.emailReply,
    PlatformFlags.advancedTimeTracking,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionCard(
          icon: LucideIcons.smartphone,
          title: context.t('admin.appReleases'),
          subtitle: context.t('admin.appReleasesHint'),
          children: [
            AdminField(
              label: context.t('admin.minVersion'),
              initialValue: (_app['minVersion'] as String?) ?? '',
              onChanged: (v) => _app['minVersion'] = v,
              hint: '1.0.0',
            ),
            AdminField(
              label: context.t('admin.privacyPolicyUrl'),
              initialValue: (_app['privacyPolicyUrl'] as String?) ?? '',
              onChanged: (v) => _app['privacyPolicyUrl'] = v,
              hint: 'https://example.com/privacy',
              keyboardType: TextInputType.url,
            ),
            AdminField(
              label: context.t('admin.iosStoreUrl'),
              initialValue: (_app['iosStoreUrl'] as String?) ?? '',
              onChanged: (v) => _app['iosStoreUrl'] = v,
              hint: 'https://apps.apple.com/app/id000000000',
              keyboardType: TextInputType.url,
            ),
            AdminField(
              label: context.t('admin.androidStoreUrl'),
              initialValue: (_app['androidStoreUrl'] as String?) ?? '',
              onChanged: (v) => _app['androidStoreUrl'] = v,
              hint:
                  'https://play.google.com/store/apps/details?id=hn.asta.hinata',
              keyboardType: TextInputType.url,
            ),
            AdminField(
              label: context.t('admin.macosStoreUrl'),
              initialValue: (_app['macosStoreUrl'] as String?) ?? '',
              onChanged: (v) => _app['macosStoreUrl'] = v,
              hint: 'https://apps.apple.com/app/id000000000',
              keyboardType: TextInputType.url,
            ),
            AdminField(
              label: context.t('admin.windowsStoreUrl'),
              initialValue: (_app['windowsStoreUrl'] as String?) ?? '',
              onChanged: (v) => _app['windowsStoreUrl'] = v,
              hint: 'https://apps.microsoft.com/detail/XXXXXXXXXXXX',
              keyboardType: TextInputType.url,
            ),
            AdminField(
              label: context.t('admin.linuxStoreUrl'),
              initialValue: (_app['linuxStoreUrl'] as String?) ?? '',
              onChanged: (v) => _app['linuxStoreUrl'] = v,
              hint: 'https://flathub.org/apps/com.example.app',
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdminSectionCard(
          icon: LucideIcons.lockKeyhole,
          title: context.t('admin.authTitle'),
          subtitle: context.t('admin.authHint'),
          children: [
            _PlatformToggle(
              title: context.t('admin.localAuthTitle'),
              description: context.t('admin.localAuthHint'),
              value: _app['localAuthEnabled'] != false,
              onChanged: (v) => setState(() => _app['localAuthEnabled'] = v),
            ),
            const SizedBox(height: 14),
            _PlatformToggle(
              title: context.t('admin.registrationTitle'),
              description: context.t('admin.registrationHint'),
              value: _app['registrationEnabled'] != false,
              onChanged: (v) => setState(() => _app['registrationEnabled'] = v),
            ),
            const SizedBox(height: 14),
            _PlatformToggle(
              title: context.t('admin.approvalTitle'),
              description: context.t('admin.approvalHint'),
              value: _app['requireAdminApproval'] == true,
              onChanged: (v) =>
                  setState(() => _app['requireAdminApproval'] = v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdminSectionCard(
          icon: LucideIcons.slidersHorizontal,
          title: context.t('admin.platformTitle'),
          subtitle: context.t('admin.platformHint'),
          children: [
            _PlatformToggle(
              title: context.t('admin.multiAssigneeTitle'),
              description: context.t('admin.multiAssigneeHint'),
              value: _flags[PlatformFlags.multiAssignee] == true,
              onChanged: (v) =>
                  setState(() => _flags[PlatformFlags.multiAssignee] = v),
            ),
            const SizedBox(height: 14),
            _PlatformToggle(
              title: context.t('admin.emailReplyTitle'),
              description: context.t('admin.emailReplyHint'),
              value: _flags[PlatformFlags.emailReply] == true,
              onChanged: (v) =>
                  setState(() => _flags[PlatformFlags.emailReply] = v),
            ),
            const SizedBox(height: 14),
            // Listed here because this is where an admin looks for platform
            // behaviour, but it is not switched here: the flag reported by
            // /meta is derived from the time-tracking module's own policies,
            // and it shares a screen with the co-determination notes that
            // belong beside it.
            _PlatformToggle(
              title: context.t('admin.timeTracking.advancedTitle'),
              description: context.t('admin.timeTracking.advancedFromSection'),
              value: _timeTracking['advancedEnabled'] == true,
              onChanged: (_) {},
              onOpen: widget.onOpenTimeTracking,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdminSectionCard(
          icon: LucideIcons.flag,
          title: context.t('admin.featureFlags'),
          subtitle: context.t('admin.featureFlagsHint'),
          children: [
            _FeatureFlagEditor(
              flags: _flags,
              // The well-known flags have dedicated toggles above (with proper
              // titles + descriptions), so keep them out of the raw editor to
              // avoid showing the same switch twice.
              hidden: _dedicatedFlags,
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ],
    );
  }
}

/// A labeled platform-behaviour switch (title + explanatory description).
class _PlatformToggle extends StatelessWidget {
  const _PlatformToggle({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.onOpen,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// When set, this row *points at* the setting instead of being it: the state
  /// is shown, and the row opens the section that owns it. [onChanged] is then
  /// never called.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final open = onOpen;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (open == null)
          HiveSwitch(value: value, onChanged: onChanged)
        else
          // Bounded so a long translation of "on"/"off" ellipsizes instead of
          // pushing the chevron off a narrow phone.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: _StateChip(on: value)),
                const SizedBox(width: 6),
                Icon(
                  forwardChevron(context),
                  size: 18,
                  color: AppColors.inkFaint,
                ),
              ],
            ),
          ),
      ],
    );
    if (open == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: open,
        borderRadius: BorderRadius.circular(10),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: row),
      ),
    );
  }
}

/// The current state of a setting that is configured elsewhere.
class _StateChip extends StatelessWidget {
  const _StateChip({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: on ? AppColors.accentSoft : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: on ? AppColors.accentLine : AppColors.hairline2,
        ),
      ),
      child: Text(
        context.t(
          on ? 'admin.timeTracking.stateOn' : 'admin.timeTracking.stateOff',
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: on ? AppColors.accentStrong : AppColors.inkSoft,
        ),
      ),
    );
  }
}

/// Add / toggle / remove arbitrary `name → enabled` feature flags.
class _FeatureFlagEditor extends StatefulWidget {
  const _FeatureFlagEditor({
    required this.flags,
    required this.onChanged,
    this.hidden = const {},
  });

  final Map<String, dynamic> flags;
  final VoidCallback onChanged;

  /// Flag keys surfaced by a dedicated toggle elsewhere — excluded from the list
  /// (and blocked from being re-added by name) so they never appear twice.
  final Set<String> hidden;

  @override
  State<_FeatureFlagEditor> createState() => _FeatureFlagEditorState();
}

class _FeatureFlagEditorState extends State<_FeatureFlagEditor> {
  final _newFlag = TextEditingController();

  @override
  void dispose() {
    _newFlag.dispose();
    super.dispose();
  }

  void _add() {
    final name = _newFlag.text.trim();
    if (name.isEmpty) return;
    // Explain why an add did nothing instead of a dead button.
    if (widget.flags.containsKey(name)) {
      showGlassErrorToast(
        context,
        context.t('admin.featureFlagExists', variables: {'name': name}),
      );
      return;
    }
    if (widget.hidden.contains(name)) {
      showGlassErrorToast(
        context,
        context.t('admin.featureFlagReserved', variables: {'name': name}),
      );
      return;
    }
    setState(() {
      widget.flags[name] = true;
      _newFlag.clear();
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.flags.entries
        .where((e) => !widget.hidden.contains(e.key))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              context.t('admin.featureFlagsEmpty'),
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
          ),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                HiveSwitch(
                  value: entry.value == true,
                  onChanged: (v) {
                    setState(() => widget.flags[entry.key] = v);
                    widget.onChanged();
                  },
                ),
                IconButton(
                  icon: Icon(
                    LucideIcons.trash2,
                    size: 16,
                    color: AppColors.inkFaint,
                  ),
                  tooltip: context.t('common.delete'),
                  onPressed: () {
                    setState(() => widget.flags.remove(entry.key));
                    widget.onChanged();
                  },
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newFlag,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: context.t('admin.featureFlagName'),
                  isDense: true,
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _add,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: Text(context.t('common.add')),
            ),
          ],
        ),
      ],
    );
  }
}
