import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/branding/org_logo.dart';
import '../../core/widgets/hex_mark.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/time_policy_cubit.dart';
import '../../core/repositories/admin_repository.dart';
import '../../core/repositories/meta_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/responsive/golden_columns.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart'
    show showGlassToast, showGlassErrorToast, GlassToastKind;
import 'admin_settings_cubit.dart';
import 'admin_sso_section.dart';
import 'sections/admin_app_section.dart';
import 'sections/admin_audit_section.dart';
import 'sections/audit_log_cubit.dart';
import 'sections/admin_connect_section.dart';
import 'sections/admin_email_section.dart';
import 'sections/admin_general_section.dart';
import 'sections/admin_git_section.dart';
import 'sections/admin_mcp_section.dart';
import 'sections/admin_security_section.dart';
import 'users/user_management_screen.dart';
import '../../core/widgets/hive_widgets.dart' show forwardChevron;
import '../../core/theme/app_type.dart';
import '../../core/widgets/settings_split.dart';

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

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key, this.initialSection, this.focusUserId});

  /// Optional section to open on entry (e.g. a deep link `/admin?section=connect`).
  /// Matched against the [_AdminSection] enum names.
  final String? initialSection;

  /// With the `users` section: the user whose detail drawer opens once the
  /// directory has loaded (an approval deep link's `?user=<id>`).
  final String? focusUserId;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (context) => AdminSettingsCubit(
          admin: context.read<AdminRepository>(),
          meta: context.read<MetaRepository>(),
        )..load(),
      ),
      BlocProvider(
        create: (context) =>
            AuditLogCubit.admin(context.read<AdminRepository>()),
      ),
    ],
    child: _AdminView(initialSection: initialSection, focusUserId: focusUserId),
  );
}

class _AdminView extends StatefulWidget {
  const _AdminView({this.initialSection, this.focusUserId});

  final String? initialSection;
  final String? focusUserId;

  @override
  State<_AdminView> createState() => _AdminViewState();
}

class _AdminViewState extends State<_AdminView> {
  // Desktop: which section is shown in the right pane.
  _AdminSection _desktopSection = _AdminSection.general;

  // Mobile: when non-null, the detail view is shown instead of the list.
  _AdminSection? _mobileSection;

  /// Reaches the Invite dialog of the user directory in the wide pane from the
  /// app bar's action.
  final UserInviteController _invite = UserInviteController();

  @override
  void initState() {
    super.initState();
    _applyInitialSection();
  }

  @override
  void didUpdateWidget(covariant _AdminView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A deep link into the admin area while it is already open lands on the
    // same page: follow it to the section it names.
    if (oldWidget.initialSection != widget.initialSection ||
        oldWidget.focusUserId != widget.focusUserId) {
      _applyInitialSection();
    }
  }

  /// Preselects the section named by [AdminScreen.initialSection] (deep link).
  /// Sets both the desktop and mobile targets so the right one is honoured once
  /// the layout resolves at build time.
  void _applyInitialSection() {
    final name = widget.initialSection;
    if (name == null || name.isEmpty) return;
    for (final s in _AdminSection.values) {
      if (s.name == name) {
        _desktopSection = s;
        _mobileSection = s;
        return;
      }
    }
  }

  Future<void> _save() async {
    final cubit = context.read<AdminSettingsCubit>();
    if (cubit.state.settings == null) return;
    try {
      await cubit.save();
      if (mounted) {
        // These settings decide what /meta reports — feature flags above all.
        // Re-read it so the admin sees the nav entry they just switched on
        // appear behind them, instead of after the next restart.
        context.read<AppConfigBloc>().add(
          const MetaRefreshRequested(force: true),
        );
        // And the time-tracking rules, for the same reason one level down: a
        // lock date that just moved has to reach the screens that grey out a
        // frozen day, not wait for the next sign-in.
        unawaited(context.read<TimePolicyCubit>().refresh());
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
    }
  }

  void _selectSection(_AdminSection sec, {required bool mobile}) {
    if (mobile) {
      setState(() => _mobileSection = sec);
    } else {
      setState(() => _desktopSection = sec);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminSettingsCubit>().state;
    if (state.status == AdminSettingsStatus.loading) {
      return const Center(child: HiveLoader());
    }
    if (state.status == AdminSettingsStatus.failure) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.cloudOff, size: 48, color: AppColors.inkFaint),
            const SizedBox(height: 12),
            Text(
              context.t(state.errorKey!),
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: context.read<AdminSettingsCubit>().load,
              child: Text(context.t('common.retry')),
            ),
          ],
        ),
      );
    }

    final settings = state.settings!;

    return ResponsiveBuilder(
      builder: (context, size) {
        if (size == LayoutSize.compact) {
          // Mobile: list ↔ detail in-app navigation. Both steps live on the
          // same /admin route, so the shell's back button is wired through
          // PageChrome: in the detail it returns to the list, in the list it
          // pops back to where admin was opened from.
          final current = _mobileSection;
          if (current != null) {
            // The audit log docks its filter bar into the app bar, so it owns
            // its own PageChrome (title + back); everything else uses the shared
            // wrapper here.
            if (current == _AdminSection.auditLog) {
              return AdminAuditSection(
                onBack: () => setState(() => _mobileSection = null),
              );
            }
            // So does the user directory, for its search and filter row.
            if (current == _AdminSection.users) {
              return UserManagementScreen(
                focusUserId: widget.focusUserId,
                onBack: () => setState(() => _mobileSection = null),
              );
            }
            return PageChrome(
              title: context.t(_sectionTitleKey(current)),
              onBack: () => setState(() => _mobileSection = null),
              actions: _saveActions(context, current),
              child: _MobileDetailView(
                section: current,
                settings: settings,
                onOpenTimeTracking: _openTimeTracking(context),
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

        // Desktop / tablet: split panel. The section title + Save action ride
        // in the shell's glass app bar (via PageChrome) — the pane draws no
        // header chrome of its own.
        return PageChrome(
          title: context.t(_sectionTitleKey(_desktopSection)),
          actions: _desktopSection == _AdminSection.users
              ? _inviteActions(context)
              : _saveActions(context, _desktopSection),
          // The rail plus a pane of cards: wider than the reading width, and
          // capped by the shell so the section title and Save in the bar line
          // up with the rail and the pane below them.
          contentMax: goldenContentMax,
          child: _WideAdminShell(
            section: _desktopSection,
            settings: settings,
            onSectionChanged: (s) => _selectSection(s, mobile: false),
            onOpenTimeTracking: _openTimeTracking(context),
            focusUserId: widget.focusUserId,
            inviteController: _invite,
          ),
        );
      },
    );
  }

  /// The way to the time-tracking settings, which moved to the Organisation
  /// page (HIN-129). Only for an admin who also holds the organisation role;
  /// for anyone else the App section reports the state and leads nowhere.
  VoidCallback? _openTimeTracking(BuildContext context) =>
      (context.read<AuthBloc>().state.user?.isOrgAdmin ?? false)
      ? () => context.go('/organization')
      : null;

  /// The user directory's Invite, in the app bar where the other sections put
  /// Save; the directory in the pane opens the dialog.
  List<PageAction> _inviteActions(BuildContext context) => [
    PageAction(
      icon: LucideIcons.userPlus,
      label: context.t('admin.um.inviteUsers'),
      onTap: (_) => _invite.invite(),
      primary: true,
    ),
  ];

  /// The Save action published into the glass app bar — omitted for sections
  /// that manage their own persistence (audit log, connect).
  List<PageAction> _saveActions(BuildContext context, _AdminSection section) {
    if (!_sectionHasSave(section)) return const [];
    return [
      PageAction(
        icon: LucideIcons.save,
        label: context.t('common.save'),
        onTap: (_) => _save(),
        primary: true,
        busy: context.read<AdminSettingsCubit>().state.saving,
      ),
    ];
  }
}

/// Connect, the audit log and the user directory manage themselves (no shared
/// settings draft to save), so they surface no Save action.
bool _sectionHasSave(_AdminSection section) =>
    section != _AdminSection.auditLog &&
    section != _AdminSection.connect &&
    section != _AdminSection.users;

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
        // The app bar already names "Adminbereich"; open with a short intro line
        // instead of a duplicate title, cleared of the glass bar by topGutter.
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16 + context.topGutter, 20, 0),
            child: Text(
              context.t('admin.subtitle'),
              style: TextStyle(
                fontSize: AppType.label,
                color: AppColors.inkSoft,
              ),
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
                  fontSize: AppType.caption,
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
    return Material(
      color: Colors.transparent,
      child: Semantics(
        button: true,
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
                  child: Icon(meta.icon, size: 17, color: AppColors.accentInk),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    context.t(meta.labelKey),
                    style: TextStyle(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                Icon(
                  forwardChevron(context),
                  size: 18,
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

// ─────────────────────────── Mobile: detail view ─────────────────────────

class _MobileDetailView extends StatelessWidget {
  const _MobileDetailView({
    required this.section,
    required this.settings,
    required this.onOpenTimeTracking,
  });

  final _AdminSection section;
  final Map<String, dynamic> settings;

  /// Opens Organisation, where the time-tracking module is switched — the App
  /// section points at it rather than duplicating the master switch. Null for
  /// an admin without the organisation role.
  final VoidCallback? onOpenTimeTracking;

  @override
  Widget build(BuildContext context) {
    // Back + title + Save all ride in the shell's glass app bar (via
    // PageChrome). This view is just the scrolling body, cleared of the glass
    // bar by topGutter. The audit log owns its own scroll + pagination, so it
    // renders directly; every other section uses the shared scroll wrapper.
    if (section == _AdminSection.auditLog) return const AdminAuditSection();
    // The iOS numeric keypad has no Done key, so give the admin forms two ways
    // out of it: tap anywhere outside a field, or drag-scroll the body.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          16,
          16 + context.topGutter,
          16,
          16 + context.bottomGutter,
        ),
        child: _sectionBody(section),
      ),
    );
  }

  Widget _sectionBody(_AdminSection sec) => switch (sec) {
    _AdminSection.general => AdminGeneralSection(settings: settings),
    _AdminSection.app => AdminAppSection(
      settings: settings,
      onOpenTimeTracking: onOpenTimeTracking,
    ),
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

/// The nav rail beside the section that is open. A section spreads its cards
/// over the pane it has ([AdminCards]); the audit log takes the pane whole, for
/// its timeline.
class _WideAdminShell extends StatelessWidget {
  const _WideAdminShell({
    required this.section,
    required this.settings,
    required this.onSectionChanged,
    required this.inviteController,
    this.onOpenTimeTracking,
    this.focusUserId,
  });

  final _AdminSection section;
  final Map<String, dynamic> settings;
  final ValueChanged<_AdminSection> onSectionChanged;

  /// Same jump as on the compact layout: the App section's row for the extended
  /// time-tracking flag opens the Organisation page that owns it.
  final VoidCallback? onOpenTimeTracking;

  /// The user whose drawer the directory opens on entry (deep link).
  final String? focusUserId;

  /// Connects the app bar's Invite to the directory in the pane.
  final UserInviteController inviteController;

  @override
  Widget build(BuildContext context) {
    // The audit log and the user directory own their scroll + pagination and
    // want the full pane.
    final selfScrolling =
        section == _AdminSection.auditLog || section == _AdminSection.users;
    return SettingsSplitLayout<_AdminSection>(
      header: SettingsRailHeader(
        // The admin console is where the logo is configured, two clicks
        // away; showing it here closes that loop. The rail is 250 points, so
        // the mark is capped well short of the width the title needs.
        leading: const OrgLogo(
          height: 26,
          maxWidth: 68,
          fallback: HexMark(size: 26),
        ),
        title: context.t('admin.title'),
        subtitle: context.t('admin.subtitle'),
      ),
      entries: [
        for (final item in _navItems)
          SettingsNavEntry(
            id: item.section,
            icon: item.icon,
            label: context.t(item.labelKey),
            group: context.t('admin.${item.group}'),
          ),
      ],
      selected: section,
      onSelect: onSectionChanged,
      bodyScrolls: !selfScrolling,
      // No cap: an admin section spreads its cards over the pane it has.
      bodyMaxWidth: double.infinity,
      body: switch (section) {
        _AdminSection.auditLog => const AdminAuditSection(),
        _AdminSection.users => UserManagementScreen(
          focusUserId: focusUserId,
          inviteController: inviteController,
        ),
        _ => _body(),
      },
    );
  }

  Widget _body() => switch (section) {
    _AdminSection.general => AdminGeneralSection(settings: settings),
    _AdminSection.app => AdminAppSection(
      settings: settings,
      onOpenTimeTracking: onOpenTimeTracking,
    ),
    _AdminSection.authentication => AdminSsoSection(settings: settings),
    _AdminSection.connect => const AdminConnectSection(),
    _AdminSection.email => AdminEmailSection(settings: settings),
    _AdminSection.git => AdminGitSection(settings: settings),
    _AdminSection.mcp => AdminMcpSection(settings: settings),
    _AdminSection.security => AdminSecuritySection(settings: settings),
    // Rendered directly (self-scrolling); never reached here.
    _AdminSection.auditLog => const SizedBox.shrink(),
    _AdminSection.users => const SizedBox.shrink(),
  };
}
