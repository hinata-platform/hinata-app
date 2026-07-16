import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/admin_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart'
    show showGlassToast, showGlassErrorToast, GlassToastKind;
import 'admin_sso_section.dart';
import 'sections/admin_app_section.dart';
import 'sections/admin_audit_section.dart';
import 'sections/admin_connect_section.dart';
import 'sections/admin_email_section.dart';
import 'sections/admin_general_section.dart';
import 'sections/admin_git_section.dart';
import 'sections/admin_mcp_section.dart';
import 'sections/admin_security_section.dart';

// ─────────────────────────── Section enum ────────────────────────────────

enum _AdminSection {
  general,
  app,
  authentication,
  connect,
  email,
  git,
  mcp,
  security,
  auditLog,
  users,
}

// Metadata for a nav entry.
typedef _SectionMeta = ({
  _AdminSection section,
  IconData icon,
  String labelKey,
  String group,
});

const _navItems = <_SectionMeta>[
  (
    section: _AdminSection.general,
    icon: LucideIcons.building2,
    labelKey: 'admin.general',
    group: 'navGeneral',
  ),
  (
    section: _AdminSection.app,
    icon: LucideIcons.smartphone,
    labelKey: 'admin.app',
    group: 'navGeneral',
  ),
  (
    section: _AdminSection.security,
    icon: LucideIcons.shield,
    labelKey: 'admin.security',
    group: 'navGeneral',
  ),
  (
    section: _AdminSection.authentication,
    icon: LucideIcons.lock,
    labelKey: 'admin.authentication',
    group: 'navIntegrations',
  ),
  (
    section: _AdminSection.connect,
    icon: LucideIcons.radioTower,
    labelKey: 'admin.connect',
    group: 'navIntegrations',
  ),
  (
    section: _AdminSection.email,
    icon: LucideIcons.mail,
    labelKey: 'admin.email',
    group: 'navIntegrations',
  ),
  (
    section: _AdminSection.git,
    icon: LucideIcons.gitBranch,
    labelKey: 'admin.gitIntegration',
    group: 'navIntegrations',
  ),
  (
    section: _AdminSection.mcp,
    icon: LucideIcons.plug,
    labelKey: 'admin.mcp',
    group: 'navIntegrations',
  ),
  (
    section: _AdminSection.auditLog,
    icon: LucideIcons.history,
    labelKey: 'admin.auditLog',
    group: 'navSystem',
  ),
  (
    section: _AdminSection.users,
    icon: LucideIcons.users,
    labelKey: 'admin.users',
    group: 'navSystem',
  ),
];

// ─────────────────────────── Root screen ─────────────────────────────────

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _settings;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Desktop: which section is shown in the right pane.
  _AdminSection _desktopSection = _AdminSection.general;

  // Mobile: when non-null, the detail view is shown instead of the list.
  _AdminSection? _mobileSection;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _settings = await context.read<AdminRepository>().adminSettings();
      setState(() => _loading = false);
    } on ApiFailure catch (failure) {
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _save() async {
    if (_settings == null) return;
    setState(() => _saving = true);
    try {
      _settings = await context.read<AdminRepository>().updateAdminSettings(
        _settings!,
      );
      if (mounted) {
        showGlassToast(
          context,
          context.t('admin.saved'),
          kind: GlassToastKind.success,
        );
      }
    } on ApiFailure catch (failure) {
      if (mounted) {
        showGlassErrorToast(context, context.t(failure.message));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _selectSection(_AdminSection sec, {required bool mobile}) {
    if (sec == _AdminSection.users) {
      context.push('/admin/users');
      return;
    }
    if (mobile) {
      setState(() => _mobileSection = sec);
    } else {
      setState(() => _desktopSection = sec);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: HiveLoader());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.cloudOff, size: 48, color: AppColors.inkFaint),
            const SizedBox(height: 12),
            Text(
              context.t(_error!),
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              child: Text(context.t('common.retry')),
            ),
          ],
        ),
      );
    }

    final settings = _settings!;

    return ResponsiveBuilder(
      builder: (context, size) {
        if (size == LayoutSize.compact) {
          // Mobile: list ↔ detail in-app navigation. Both steps live on the
          // same /admin route, so the shell's back button is wired through
          // PageChrome: in the detail it returns to the list, in the list it
          // pops back to where admin was opened from.
          final current = _mobileSection;
          if (current != null) {
            return PageChrome(
              title: context.t(_sectionTitleKey(current)),
              onBack: () => setState(() => _mobileSection = null),
              child: _MobileDetailView(
                section: current,
                settings: settings,
                saving: _saving,
                onSave: _save,
              ),
            );
          }
          return PageChrome(
            title: context.t('admin.title'),
            child: _MobileListView(
              onSelect: (sec) => _selectSection(sec, mobile: true),
            ),
          );
        }

        // Desktop / tablet: split panel
        return PageChrome(
          title: context.t('admin.title'),
          child: _WideAdminShell(
            section: _desktopSection,
            settings: settings,
            saving: _saving,
            onSectionChanged: (s) => _selectSection(s, mobile: false),
            onSave: _save,
          ),
        );
      },
    );
  }
}

/// i18n key for an admin section's title (shared by the shell app bar and the
/// in-pane section header).
String _sectionTitleKey(_AdminSection section) => switch (section) {
  _AdminSection.general => 'admin.general',
  _AdminSection.app => 'admin.app',
  _AdminSection.authentication => 'admin.authentication',
  _AdminSection.connect => 'admin.connect',
  _AdminSection.email => 'admin.email',
  _AdminSection.git => 'admin.gitIntegration',
  _AdminSection.mcp => 'admin.mcp',
  _AdminSection.security => 'admin.security',
  _AdminSection.auditLog => 'admin.auditLog',
  _AdminSection.users => 'admin.users',
};

// ─────────────────────────── Mobile: list view ───────────────────────────

class _MobileListView extends StatelessWidget {
  const _MobileListView({required this.onSelect});

  final ValueChanged<_AdminSection> onSelect;

  @override
  Widget build(BuildContext context) {
    // Group nav items
    final groups = <String, List<_SectionMeta>>{};
    for (final item in _navItems) {
      groups.putIfAbsent(item.group, () => []).add(item);
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 20 + context.topGutter, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t('admin.title'),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.t('admin.subtitle'),
                  style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
        ),
        for (final entry in groups.entries) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
              child: Text(
                context.t('admin.${entry.key}').toUpperCase(),
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkFaint,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < entry.value.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, indent: 56, color: AppColors.hairline),
                    _MobileNavTile(
                      meta: entry.value[i],
                      onTap: () => onSelect(entry.value[i].section),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: 32 + context.bottomGutter)),
      ],
    );
  }
}

class _MobileNavTile extends StatelessWidget {
  const _MobileNavTile({required this.meta, required this.onTap});

  final _SectionMeta meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isUsers = meta.section == _AdminSection.users;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(meta.icon, size: 17, color: AppColors.accentStrong),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  context.t(meta.labelKey),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Icon(
                isUsers ? LucideIcons.externalLink : LucideIcons.chevronRight,
                size: 18,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Mobile: detail view ─────────────────────────

class _MobileDetailView extends StatelessWidget {
  const _MobileDetailView({
    required this.section,
    required this.settings,
    required this.saving,
    required this.onSave,
  });

  final _AdminSection section;
  final Map<String, dynamic> settings;
  final bool saving;
  final VoidCallback onSave;

  // Connect + audit log manage themselves (no shared settings draft to save).
  bool get _hasSave =>
      section != _AdminSection.auditLog && section != _AdminSection.connect;

  @override
  Widget build(BuildContext context) {
    // Back + title come from the shell app bar (via PageChrome); this slim bar
    // — cleared of the glass bar by topGutter — carries only the Save action.
    return Column(
      children: [
        if (_hasSave)
          Container(
            height: 52,
            margin: EdgeInsets.only(top: context.topGutter),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerRight,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.hairline)),
            ),
            child: saving
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: HiveLoader(
                        strokeWidth: 2,
                        color: AppColors.brandInk,
                      ),
                    ),
                  )
                : TextButton.icon(
                    onPressed: onSave,
                    icon: const Icon(LucideIcons.save, size: 16),
                    label: Text(context.t('common.save')),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brandInk,
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
          ),
        // ── Content ──────────────────────────────────────────────
        // The audit log owns its own scroll + pagination, so it renders
        // directly; every other section uses the shared scroll wrapper.
        Expanded(
          child: section == _AdminSection.auditLog
              ? const AdminAuditSection()
              : SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    _hasSave ? 16 : 16 + context.topGutter,
                    16,
                    16 + context.bottomGutter,
                  ),
                  child: _sectionBody(section),
                ),
        ),
      ],
    );
  }

  Widget _sectionBody(_AdminSection sec) => switch (sec) {
    _AdminSection.general => AdminGeneralSection(settings: settings),
    _AdminSection.app => AdminAppSection(settings: settings),
    _AdminSection.authentication => AdminSsoSection(settings: settings),
    _AdminSection.connect => const AdminConnectSection(),
    _AdminSection.email => AdminEmailSection(settings: settings),
    _AdminSection.git => AdminGitSection(settings: settings),
    _AdminSection.mcp => AdminMcpSection(settings: settings),
    _AdminSection.security => AdminSecuritySection(settings: settings),
    // Rendered directly by the shell (self-scrolling); never reached here.
    _AdminSection.auditLog => const SizedBox.shrink(),
    _AdminSection.users => const SizedBox.shrink(),
  };
}

// ─────────────────────────── Wide layout (≥ medium) ──────────────────────

class _WideAdminShell extends StatelessWidget {
  const _WideAdminShell({
    required this.section,
    required this.settings,
    required this.saving,
    required this.onSectionChanged,
    required this.onSave,
  });

  final _AdminSection section;
  final Map<String, dynamic> settings;
  final bool saving;
  final ValueChanged<_AdminSection> onSectionChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Left nav rail ─────────────────────────────────────────
        Container(
          width: 220,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(right: BorderSide(color: AppColors.hairline)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('admin.title'),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.t('admin.subtitle'),
                      style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.hairline),
              const SizedBox(height: 8),
              Expanded(child: _buildNavList(context)),
            ],
          ),
        ),
        // ── Right content pane ────────────────────────────────────
        Expanded(
          child: _DesktopSectionContent(
            section: section,
            settings: settings,
            saving: saving,
            onSave: onSave,
          ),
        ),
      ],
    );
  }

  Widget _buildNavList(BuildContext context) {
    final groups = <String, List<_SectionMeta>>{};
    for (final item in _navItems) {
      groups.putIfAbsent(item.group, () => []).add(item);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      children: [
        for (final entry in groups.entries) ...[
          _NavGroup(label: context.t('admin.${entry.key}')),
          for (final meta in entry.value)
            _NavItem(meta: meta, current: section, onTap: onSectionChanged),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}

// ─────────────────────────── Desktop section content ─────────────────────

class _DesktopSectionContent extends StatelessWidget {
  const _DesktopSectionContent({
    required this.section,
    required this.settings,
    required this.saving,
    required this.onSave,
  });

  final _AdminSection section;
  final Map<String, dynamic> settings;
  final bool saving;
  final VoidCallback onSave;

  String _title(BuildContext context) => switch (section) {
    _AdminSection.general => context.t('admin.general'),
    _AdminSection.app => context.t('admin.app'),
    _AdminSection.authentication => context.t('admin.authentication'),
    _AdminSection.connect => context.t('admin.connect'),
    _AdminSection.email => context.t('admin.email'),
    _AdminSection.git => context.t('admin.gitIntegration'),
    _AdminSection.mcp => context.t('admin.mcp'),
    _AdminSection.security => context.t('admin.security'),
    _AdminSection.auditLog => context.t('admin.auditLog'),
    _AdminSection.users => context.t('admin.users'),
  };

  // Connect + audit log manage themselves (no shared settings draft to save).
  bool get _hasSave =>
      section != _AdminSection.auditLog && section != _AdminSection.connect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Section header bar
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            border: Border(bottom: BorderSide(color: AppColors.hairline)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _title(context),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (_hasSave)
                saving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: HiveLoader(
                          strokeWidth: 2,
                          color: AppColors.brandInk,
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: onSave,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        icon: const Icon(LucideIcons.save, size: 16),
                        label: Text(context.t('common.save')),
                      ),
            ],
          ),
        ),
        // Body — the audit log scrolls & paginates itself; the rest use the
        // shared scroll wrapper.
        Expanded(
          child: section == _AdminSection.auditLog
              ? const AdminAuditSection()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _body(),
                ),
        ),
      ],
    );
  }

  Widget _body() => switch (section) {
    _AdminSection.general => AdminGeneralSection(settings: settings),
    _AdminSection.app => AdminAppSection(settings: settings),
    _AdminSection.authentication => AdminSsoSection(settings: settings),
    _AdminSection.connect => const AdminConnectSection(),
    _AdminSection.email => AdminEmailSection(settings: settings),
    _AdminSection.git => AdminGitSection(settings: settings),
    _AdminSection.mcp => AdminMcpSection(settings: settings),
    _AdminSection.security => AdminSecuritySection(settings: settings),
    // Rendered directly by the shell (self-scrolling); never reached here.
    _AdminSection.auditLog => const SizedBox.shrink(),
    _AdminSection.users => const SizedBox.shrink(),
  };
}

// ─────────────────────────── Nav widgets ─────────────────────────────────

class _NavGroup extends StatelessWidget {
  const _NavGroup({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.inkFaint,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.meta,
    required this.current,
    required this.onTap,
  });

  final _SectionMeta meta;
  final _AdminSection current;
  final ValueChanged<_AdminSection> onTap;

  @override
  Widget build(BuildContext context) {
    final active = meta.section == current;
    final isUsers = meta.section == _AdminSection.users;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => onTap(meta.section),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: active
                ? BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            child: Row(
              children: [
                Icon(
                  meta.icon,
                  size: 17,
                  color: active ? AppColors.accentStrong : AppColors.inkSoft,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.t(meta.labelKey),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active ? AppColors.accentStrong : AppColors.ink,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isUsers)
                  Icon(
                    LucideIcons.externalLink,
                    size: 12,
                    color: AppColors.inkFaint,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
