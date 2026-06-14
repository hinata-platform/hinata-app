import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/locale_cubit.dart';
import '../../core/blocs/theme_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/soft_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    final config = context.watch<AppConfigBloc>().state;
    final locale = context.watch<LocaleCubit>().state;
    final themeMode = context.watch<ThemeCubit>().state;
    return ListView(
      padding: context.pagePadding,
      children: [
        SectionHeader(title: context.t('settings.title')),
        const SizedBox(height: 12),
        if (user != null)
          SoftCard(
            child: Row(
              children: [
                AppAvatar(
                    name: user.displayName, imageUrl: user.avatarUrl, radius: 26),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.displayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(user.email,
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      context.read<AuthBloc>().add(const LogoutRequested()),
                  child: Text(context.t('settings.logout'),
                      style: const TextStyle(color: AppColors.danger)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.language_rounded, color: AppColors.navy),
                title: Text(context.t('settings.language')),
                trailing: DropdownButton<String>(
                  value: locale.languageCode,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(16),
                  items: [
                    for (final entry in I18n.localeNames.entries)
                      DropdownMenuItem(
                          value: entry.key, child: Text(entry.value)),
                  ],
                  onChanged: (code) {
                    if (code != null) {
                      context.read<LocaleCubit>().setLocale(code);
                    }
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.brightness_6_rounded,
                    color: AppColors.navy),
                title: Text(context.t('settings.theme')),
                trailing: _ThemeModeSelector(mode: themeMode),
              ),
              if ((config.meta?.privacyPolicyUrl ?? '').isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.privacy_tip_rounded,
                      color: AppColors.navy),
                  title: Text(context.t('settings.privacyPolicy')),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => launchUrl(
                    Uri.parse(config.meta!.privacyPolicyUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              if (user?.isAdmin ?? false)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_rounded,
                      color: AppColors.navy),
                  title: Text(context.t('settings.adminArea')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.go('/admin'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.t('settings.about'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _VersionRow(
                  label: context.t('settings.appVersion'),
                  value: config.appVersion),
              _VersionRow(
                  label: context.t('settings.serverVersion'),
                  value: config.meta?.serverVersion ?? '–'),
              _VersionRow(
                  label: context.t('settings.organization'),
                  value: config.meta?.organizationName ?? '–'),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact System / Light / Dark segmented control bound to [ThemeCubit].
class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector({required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final options = <(ThemeMode, IconData, String)>[
      (ThemeMode.system, Icons.brightness_auto_rounded, 'settings.themeSystem'),
      (ThemeMode.light, Icons.light_mode_rounded, 'settings.themeLight'),
      (ThemeMode.dark, Icons.dark_mode_rounded, 'settings.themeDark'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.hairline),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (m, icon, labelKey) in options)
            Tooltip(
              message: context.t(labelKey),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.read<ThemeCubit>().setMode(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: m == mode ? AppColors.accentSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: m == mode ? AppColors.accentStrong : AppColors.inkSoft,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
