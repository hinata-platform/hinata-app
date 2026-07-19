import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_popup_menu.dart';
import '../admin_form_helpers.dart';

/// General organization settings: name, logo, timezone, default language.
class AdminGeneralSection extends StatefulWidget {
  const AdminGeneralSection({super.key, required this.settings});

  final Map<String, dynamic> settings;

  @override
  State<AdminGeneralSection> createState() => _AdminGeneralSectionState();
}

class _AdminGeneralSectionState extends State<AdminGeneralSection> {
  Map<String, dynamic> get _general =>
      (widget.settings['general'] ??= <String, dynamic>{})
          as Map<String, dynamic>;

  static const _timezones = [
    'Europe/Berlin',
    'Europe/London',
    'Europe/Paris',
    'Europe/Madrid',
    'Europe/Amsterdam',
    'UTC',
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'Asia/Tokyo',
    'Asia/Shanghai',
    'Asia/Kolkata',
    'Australia/Sydney',
  ];

  static const _locales = [
    ('de', 'Deutsch (Deutschland)'),
    ('en', 'English (United Kingdom)'),
  ];

  /// A liquid-glass select styled like the rest of the admin inputs (shared
  /// [adminInputDecoration] + a chevron), replacing the stock Material dropdown
  /// so this section matches the fully-glass admin area.
  Widget _glassSelect(
    BuildContext context, {
    required String label,
    required String value,
    required List<({String value, String label})> options,
    required ValueChanged<String> onChanged,
  }) {
    final current = options.firstWhere(
      (o) => o.value == value,
      orElse: () => options.first,
    );
    return GlassPopupMenu<String>(
      value: value,
      onSelected: onChanged,
      items: [
        for (final o in options) GlassMenuItem(value: o.value, label: o.label),
      ],
      child: InputDecorator(
        decoration: adminInputDecoration(context, label: label),
        child: Row(
          children: [
            Expanded(
              child: Text(
                current.label,
                style: TextStyle(fontSize: 14, color: AppColors.ink),
              ),
            ),
            Icon(LucideIcons.chevronDown, size: 18, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionCard(
          icon: LucideIcons.building2,
          title: context.t('admin.general'),
          subtitle: context.t('admin.generalHint'),
          children: [
            AdminField(
              label: context.t('admin.orgName'),
              initialValue:
                  (widget.settings['organizationName'] as String?) ?? '',
              onChanged: (v) => widget.settings['organizationName'] = v,
            ),
            AdminField(
              label: context.t('admin.logoUrl'),
              initialValue: (_general['logoUrl'] as String?) ?? '',
              onChanged: (v) => _general['logoUrl'] = v,
              hint: 'https://example.com/logo.png',
            ),
          ],
        ),
        const SizedBox(height: 16),
        AdminSectionCard(
          icon: LucideIcons.globe,
          title: context.t('admin.localization'),
          subtitle: context.t('admin.localizationHint'),
          children: [
            _glassSelect(
              context,
              label: context.t('admin.timezone'),
              value: (_general['timezone'] as String?) ?? 'Europe/Berlin',
              options: [for (final tz in _timezones) (value: tz, label: tz)],
              onChanged: (v) => setState(() => _general['timezone'] = v),
            ),
            const SizedBox(height: 12),
            _glassSelect(
              context,
              label: context.t('admin.defaultLanguage'),
              value: (_general['defaultLocale'] as String?) ?? 'de',
              options: [for (final l in _locales) (value: l.$1, label: l.$2)],
              onChanged: (v) => setState(() => _general['defaultLocale'] = v),
            ),
          ],
        ),
      ],
    );
  }
}
