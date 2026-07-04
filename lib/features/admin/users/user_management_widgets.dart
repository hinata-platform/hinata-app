import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/admin_user_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../search/search_tokens.dart';
import '../../sprint/modals/glass_modal.dart' show showGlassBottomSheet;

// ════════════════════════════════════════════════════════════════════════
//  Shared presentation for the admin User-management board: avatars, badges,
//  KPI cards, the row action menu, the bulk bar and the detail drawer. Colour
//  recipes mirror the design's oklch tokens (role hue 70/250, status 155/20/45,
//  origin 200/300/250/155), approximated with HSL.
// ════════════════════════════════════════════════════════════════════════

/// Deterministic saturated avatar colour from a name (stable per user).
Color userColor(String name) {
  var s = 0;
  for (final unit in name.codeUnits) {
    s = (s * 31 + unit) % 360;
  }
  const hues = <double>[248, 70, 250, 300, 155, 200, 20, 320];
  return HSLColor.fromAHSL(1, hues[s % hues.length], 0.45, 0.52).toColor();
}

Color _hue(double h, {double s = 0.5, double l = 0.5}) =>
    HSLColor.fromAHSL(1, h, s, l).toColor();

/// (background, ink) for a role badge.
(Color, Color) roleColors(AdminRole role) => role == AdminRole.admin
    ? (AppColors.accentSoft, AppColors.accentStrong)
    : (_hue(250, s: .4, l: .93), _hue(250, s: .45, l: .45));

/// (background, ink) for a status badge.
(Color, Color) statusColors(UserStatus status) => switch (status) {
  UserStatus.active => (_hue(155, s: .4, l: .92), _hue(155, s: .45, l: .38)),
  UserStatus.disabled => (_hue(20, s: .5, l: .93), _hue(20, s: .5, l: .47)),
  UserStatus.invited => (_hue(45, s: .6, l: .92), _hue(45, s: .55, l: .42)),
  UserStatus.pendingApproval => (_hue(265, s: .5, l: .93), _hue(265, s: .5, l: .5)),
};

Color originColor(UserOrigin origin) => switch (origin) {
  UserOrigin.local => _hue(200, s: .45, l: .5),
  UserOrigin.oidc => _hue(300, s: .45, l: .55),
  UserOrigin.saml => _hue(250, s: .45, l: .55),
  UserOrigin.ldap => _hue(155, s: .45, l: .45),
};

IconData roleIcon(AdminRole role) =>
    role == AdminRole.admin ? LucideIcons.shieldCheck : LucideIcons.user;

IconData statusIcon(UserStatus status) => switch (status) {
  UserStatus.active => LucideIcons.circleCheck,
  UserStatus.disabled => LucideIcons.ban,
  UserStatus.invited => LucideIcons.mail,
  UserStatus.pendingApproval => LucideIcons.clock,
};

String roleLabel(BuildContext c, AdminRole r) =>
    c.t(r == AdminRole.admin ? 'admin.um.roleAdmin' : 'admin.um.roleUser');

String statusLabel(BuildContext c, UserStatus s) => c.t(switch (s) {
  UserStatus.active => 'admin.um.statusActive',
  UserStatus.disabled => 'admin.um.statusDisabled',
  UserStatus.invited => 'admin.um.statusInvited',
  UserStatus.pendingApproval => 'admin.um.statusPending',
});

String originLabel(UserOrigin o) => switch (o) {
  UserOrigin.local => 'Local',
  UserOrigin.oidc => 'OIDC',
  UserOrigin.saml => 'SAML',
  UserOrigin.ldap => 'LDAP',
};

/// Relative "last active" text, localized.
String umRelTime(BuildContext c, DateTime? t) {
  if (t == null) return c.t('admin.um.never');
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return c.t('admin.um.justNow');
  if (d.inMinutes < 60) {
    return c.t('admin.um.minutesAgo', variables: {'n': '${d.inMinutes}'});
  }
  if (d.inHours < 24) {
    return c.t('admin.um.hoursAgo', variables: {'n': '${d.inHours}'});
  }
  if (d.inDays < 30) {
    return c.t('admin.um.daysAgo', variables: {'n': '${d.inDays}'});
  }
  return umPrettyDate(t);
}

String umPrettyDate(DateTime? t) =>
    t == null ? '—' : DateFormat('MMM d, y').format(t);

/// A user is "idle" when last active over two weeks ago — greys the cell.
bool isIdle(DateTime? t) =>
    t != null && DateTime.now().difference(t).inDays > 14;

// ─────────────────────────── Avatar ──────────────────────────────────────

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 36,
  });

  final String name;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Delegate to HiveAvatar so the profile picture (authenticated /avatar URL)
    // loads with a clean initials fallback; keep the admin board's user colour.
    return HiveAvatar(
      name: name,
      imageUrl: imageUrl,
      size: size,
      background: userColor(name),
    );
  }
}

// ─────────────────────────── Badges ──────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
  });

  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class RoleBadge extends StatelessWidget {
  const RoleBadge(this.role, {super.key});
  final AdminRole role;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = roleColors(role);
    return _Badge(
      icon: roleIcon(role),
      label: roleLabel(context, role),
      bg: bg,
      fg: fg,
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.user, {super.key});
  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    if (user.inviteExpired) {
      return _Badge(
        icon: LucideIcons.mailWarning,
        label: context.t('admin.um.statusExpired'),
        bg: AppColors.dangerSoft,
        fg: AppColors.danger,
      );
    }
    final (bg, fg) = statusColors(user.status);
    return _Badge(
      icon: statusIcon(user.status),
      label: statusLabel(context, user.status),
      bg: bg,
      fg: fg,
    );
  }
}

class OriginTag extends StatelessWidget {
  const OriginTag(this.origin, {super.key});
  final UserOrigin origin;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: originColor(origin),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          originLabel(origin),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.inkSoft,
          ),
        ),
        if (origin.isSso) ...[
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.canvas2,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'SSO',
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.inkFaint,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────── KPI card ────────────────────────────────────

class UmKpiCard extends StatelessWidget {
  const UmKpiCard({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.value,
    required this.label,
    required this.active,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String value;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(
            color: active ? AppColors.accentLine : AppColors.hairline,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.25),
                    blurRadius: 0,
                    spreadRadius: 3,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 20, color: iconFg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontFamily: AppTheme.fontBrand,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 1),
                  DefaultTextStyle(
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                    child: trailing == null
                        ? Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : Row(
                            children: [
                              Flexible(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              trailing!,
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Action bundle ───────────────────────────────

/// Callback bundle the board hands to the row menu / drawer. Direct actions
/// mutate immediately; `open*` actions raise a confirmation modal first.
class UserActions {
  const UserActions({
    required this.openDrawer,
    required this.openEdit,
    required this.activate,
    required this.approve,
    required this.openDeactivate,
    required this.setRole,
    required this.openDemote,
    required this.openResend,
    required this.openReset,
    required this.revokeSessions,
    required this.openDelete,
    required this.isLastActiveAdmin,
    required this.nameById,
    required this.currentUserId,
  });

  final void Function(AdminUser u) openDrawer;
  final void Function(AdminUser u) openEdit;
  final void Function(List<String> ids) activate;
  final void Function(List<String> ids) approve;
  final void Function(List<String> ids) openDeactivate;
  final void Function(List<String> ids, AdminRole role) setRole;
  final void Function(List<String> ids) openDemote;
  final void Function(List<String> ids) openResend;
  final void Function(List<String> ids) openReset;
  final void Function(List<String> ids) revokeSessions;
  final void Function(List<String> ids) openDelete;
  final bool Function(AdminUser u) isLastActiveAdmin;
  final String? Function(String? id) nameById;
  final String? currentUserId;
}

// ─────────────────────────── Row action menu ─────────────────────────────

class UserRowMenu extends StatelessWidget {
  const UserRowMenu({
    super.key,
    required this.user,
    required this.actions,
    required this.child,
  });

  final AdminUser user;
  final UserActions actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final lastAdmin = actions.isLastActiveAdmin(u);
    final items = <GlassMenuItem<String>>[
      GlassMenuItem(
        value: 'view',
        label: context.t('admin.um.viewProfile'),
        leading: const Icon(LucideIcons.panelRightOpen, size: 16),
      ),
      GlassMenuItem(
        value: 'edit',
        label: context.t('admin.um.editDetails'),
        leading: const Icon(LucideIcons.pencil, size: 16),
      ),
      if (u.status == UserStatus.invited)
        GlassMenuItem(
          value: 'resend',
          label: context.t('admin.um.resendInvite'),
          color: u.inviteExpired ? AppColors.accentStrong : null,
          dividerAbove: true,
          leading: Icon(
            u.inviteExpired ? LucideIcons.send : LucideIcons.rotateCw,
            size: 16,
          ),
        )
      else if (u.status == UserStatus.active)
        GlassMenuItem(
          value: 'deactivate',
          label: context.t('admin.um.deactivate'),
          dividerAbove: true,
          leading: const Icon(LucideIcons.ban, size: 16),
        )
      else if (u.status == UserStatus.pendingApproval)
        GlassMenuItem(
          value: 'approve',
          label: context.t('admin.um.approve'),
          color: AppColors.success,
          dividerAbove: true,
          leading: const Icon(
            LucideIcons.userCheck,
            size: 16,
            color: AppColors.success,
          ),
        )
      else
        GlassMenuItem(
          value: 'activate',
          label: context.t('admin.um.activate'),
          color: AppColors.success,
          dividerAbove: true,
          leading: const Icon(
            LucideIcons.circleCheck,
            size: 16,
            color: AppColors.success,
          ),
        ),
      if (u.role == AdminRole.admin)
        GlassMenuItem(
          value: 'demote',
          label: context.t('admin.um.revokeAdmin'),
          enabled: !lastAdmin,
          disabledReason: context.t('admin.um.reasonLastAdmin'),
          leading: const Icon(LucideIcons.shieldMinus, size: 16),
        )
      else
        GlassMenuItem(
          value: 'promote',
          label: context.t('admin.um.makeAdmin'),
          enabled: u.status != UserStatus.invited,
          disabledReason: context.t('admin.um.reasonPendingInvite'),
          leading: const Icon(LucideIcons.shieldCheck, size: 16),
        ),
      if (u.status != UserStatus.invited) ...[
        GlassMenuItem(
          value: 'reset',
          label: context.t(
            u.sso ? 'admin.um.resetViaIdp' : 'admin.um.sendPasswordReset',
          ),
          enabled: !u.sso,
          disabledReason: context.t('admin.um.reasonSsoManaged'),
          dividerAbove: true,
          leading: const Icon(LucideIcons.keyRound, size: 16),
        ),
        GlassMenuItem(
          value: 'revoke',
          label: context.t('admin.um.revokeSessions'),
          enabled: u.sessions > 0,
          disabledReason: context.t('admin.um.reasonNoSessions'),
          leading: const Icon(LucideIcons.logOut, size: 16),
        ),
      ],
      GlassMenuItem(
        value: 'delete',
        label: context.t('admin.um.deleteUser'),
        color: AppColors.danger,
        enabled: !lastAdmin,
        disabledReason: context.t('admin.um.reasonLastAdmin'),
        dividerAbove: true,
        leading: const Icon(
          LucideIcons.trash2,
          size: 16,
          color: AppColors.danger,
        ),
      ),
    ];

    return GlassPopupMenu<String>(
      value: '',
      width: 240,
      onSelected: (action) => _dispatch(action),
      items: items,
      child: child,
    );
  }

  void _dispatch(String action) {
    final ids = [user.id];
    switch (action) {
      case 'view':
        actions.openDrawer(user);
      case 'edit':
        actions.openEdit(user);
      case 'resend':
        actions.openResend(ids);
      case 'deactivate':
        actions.openDeactivate(ids);
      case 'activate':
        actions.activate(ids);
      case 'approve':
        actions.approve(ids);
      case 'promote':
        actions.setRole(ids, AdminRole.admin);
      case 'demote':
        actions.setRole(ids, AdminRole.user);
      case 'reset':
        actions.openReset(ids);
      case 'revoke':
        actions.revokeSessions(ids);
      case 'delete':
        actions.openDelete(ids);
    }
  }
}

// ─────────────────────────── Bulk action bar ─────────────────────────────

class BulkActionBar extends StatelessWidget {
  const BulkActionBar({
    super.key,
    required this.selected,
    required this.actions,
    required this.onClear,
  });

  final List<AdminUser> selected;
  final UserActions actions;
  final VoidCallback onClear;

  List<String> _ids(bool Function(AdminUser) test) =>
      selected.where(test).map((u) => u.id).toList();

  @override
  Widget build(BuildContext context) {
    final invited = _ids((u) => u.status == UserStatus.invited);
    final disabled = _ids((u) => u.status == UserStatus.disabled);
    final active = _ids((u) => u.status == UserStatus.active);
    final pending = _ids((u) => u.status == UserStatus.pendingApproval);
    final nonAdmin = _ids(
      (u) => u.role != AdminRole.admin && u.status != UserStatus.invited,
    );
    final admins = _ids((u) => u.role == AdminRole.admin);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              context.t(
                'admin.um.selectedCount',
                variables: {'n': '${selected.length}'},
              ),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Container(
            width: 1,
            height: 22,
            color: Colors.white.withValues(alpha: 0.18),
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          if (invited.isNotEmpty)
            _BulkBtn(
              icon: LucideIcons.send,
              label: context.t('admin.um.resend'),
              onTap: () => actions.openResend(invited),
            ),
          if (pending.isNotEmpty)
            _BulkBtn(
              icon: LucideIcons.userCheck,
              label: context.t('admin.um.approve'),
              onTap: () => actions.approve(pending),
            ),
          if (disabled.isNotEmpty)
            _BulkBtn(
              icon: LucideIcons.circleCheck,
              label: context.t('admin.um.activate'),
              onTap: () => actions.activate(disabled),
            ),
          if (active.isNotEmpty)
            _BulkBtn(
              icon: LucideIcons.ban,
              label: context.t('admin.um.deactivate'),
              onTap: () => actions.openDeactivate(active),
            ),
          if (nonAdmin.isNotEmpty)
            _BulkBtn(
              icon: LucideIcons.shieldCheck,
              label: context.t('admin.um.makeAdmin'),
              onTap: () => actions.setRole(nonAdmin, AdminRole.admin),
            ),
          if (admins.isNotEmpty)
            _BulkBtn(
              icon: LucideIcons.shieldMinus,
              label: context.t('admin.um.revokeAdmin'),
              onTap: () => actions.openDemote(admins),
            ),
          _BulkBtn(
            icon: LucideIcons.trash2,
            label: context.t('admin.um.delete'),
            danger: true,
            onTap: () => actions.openDelete(selected.map((u) => u.id).toList()),
          ),
          IconButton(
            tooltip: context.t('admin.um.clearSelection'),
            onPressed: onClear,
            icon: const Icon(LucideIcons.x, size: 18, color: Colors.white),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _BulkBtn extends StatelessWidget {
  const _BulkBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFFF8A80) : Colors.white;
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
      ),
      icon: Icon(icon, size: 15, color: color),
      label: Text(label),
    );
  }
}

// ─────────────────────────── Detail drawer ───────────────────────────────

/// Presents the per-user detail panel: a right-edge slide on wide layouts,
/// a draggable bottom sheet on phones. Returns when dismissed.
Future<void> showUserDrawer(
  BuildContext context, {
  required AdminUser user,
  required UserActions actions,
  required bool phone,
}) {
  if (phone) {
    // The glass bottom-sheet helper pushes onto the root navigator so the sheet
    // floats *above* the shell's liquid-glass bottom nav. On the nested
    // go_router navigator it would render inside the content layer, beneath the
    // floating nav — which then paints over the sheet's lower actions (the
    // Danger-zone delete button).
    return showGlassBottomSheet<void>(
      context,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.92,
        child: UserDrawerBody(user: user, actions: actions),
      ),
    );
  }
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, _) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      final tokens = SearchTokens.of(Theme.of(ctx).brightness);
      final dark = Theme.of(ctx).brightness == Brightness.dark;
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(onTap: () => Navigator.of(ctx).pop()),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(curved),
              // A floating liquid-glass panel inset from the screen edges.
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SafeArea(
                  left: false,
                  child: SizedBox(
                    width: 440,
                    child: GlassPanelShadow(
                      radius: BorderRadius.circular(26),
                      shadows: tokens.panelShadow,
                      child: GlassContainer(
                        useOwnLayer: true,
                        quality: GlassQuality.premium,
                        clipBehavior: Clip.antiAlias,
                        shape: const LiquidRoundedSuperellipse(
                          borderRadius: 26,
                        ),
                        settings: liquidGlassPanelSettings(
                          glassFill: tokens.glassFill,
                          dark: dark,
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: UserDrawerBody(user: user, actions: actions),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class UserDrawerBody extends StatelessWidget {
  const UserDrawerBody({super.key, required this.user, required this.actions});

  final AdminUser user;
  final UserActions actions;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final lastAdmin = actions.isLastActiveAdmin(u);
    // Clearance so the last action (delete) scrolls clear of the device's home
    // indicator on the phone bottom sheet. On the desktop drawer this is 0 — its
    // SafeArea wrapper has already consumed the inset.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.hairline)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UserAvatar(name: u.name, imageUrl: u.avatarUrl, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          u.name,
                          style: TextStyle(
                            fontFamily: AppTheme.fontBrand,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          u.email,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      LucideIcons.x,
                      size: 20,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  RoleBadge(u.role),
                  StatusBadge(u),
                  OriginTag(u.origin),
                ],
              ),
            ],
          ),
        ),
        // Body
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 28 + bottomInset),
            children: [
              _factsGrid(context, u),
              if (u.inviteExpired) ...[
                const SizedBox(height: 18),
                _expiredBanner(context, u),
              ],
              const SizedBox(height: 22),
              _sectionLabel(context, context.t('admin.um.manage')),
              const SizedBox(height: 12),
              ..._manageActions(context, u, lastAdmin),
              const SizedBox(height: 22),
              _sectionLabel(context, context.t('admin.um.activity')),
              const SizedBox(height: 12),
              ..._timeline(context, u),
              const SizedBox(height: 22),
              _sectionLabel(context, context.t('admin.um.dangerZone')),
              const SizedBox(height: 12),
              _ActRow(
                icon: LucideIcons.trash2,
                title: context.t('admin.um.deleteThisUser'),
                subtitle: context.t('admin.um.deleteThisUserSub'),
                danger: true,
                enabled: !lastAdmin,
                disabledReason: context.t('admin.um.reasonLastAdmin'),
                onTap: () {
                  Navigator.of(context).pop();
                  actions.openDelete([u.id]);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Row(
    children: [
      Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: AppColors.inkSoft,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 1, color: AppColors.hairline)),
    ],
  );

  Widget _factsGrid(BuildContext context, AdminUser u) {
    final twoFa = u.sso
        ? context.t('admin.um.viaIdp')
        : (u.twoFA ? context.t('admin.um.enabled') : context.t('admin.um.off'));
    Widget fact(IconData ic, String k, String v) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ic, size: 13, color: AppColors.inkFaint),
                const SizedBox(width: 5),
                Text(
                  k,
                  style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              v,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            fact(
              LucideIcons.briefcase,
              context.t('admin.um.fieldTitle'),
              u.title.isEmpty ? '—' : u.title,
            ),
            const SizedBox(width: 10),
            fact(
              LucideIcons.activity,
              context.t('admin.um.lastActive'),
              umRelTime(context, u.lastActive),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            fact(LucideIcons.shield, context.t('admin.um.twoFa'), twoFa),
            const SizedBox(width: 10),
            fact(
              LucideIcons.monitor,
              context.t('admin.um.sessions'),
              '${u.sessions}',
            ),
          ],
        ),
      ],
    );
  }

  Widget _expiredBanner(BuildContext context, AdminUser u) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.dangerSoft,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(LucideIcons.mailWarning, size: 16, color: AppColors.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.t(
              'admin.um.expiredBanner',
              variables: {
                'date': umPrettyDate(u.invitedAt),
                'name': u.name.split(' ').first,
              },
            ),
            style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.ink),
          ),
        ),
      ],
    ),
  );

  List<Widget> _manageActions(
    BuildContext context,
    AdminUser u,
    bool lastAdmin,
  ) {
    final rows = <Widget>[];
    void close() => Navigator.of(context).pop();

    if (u.status == UserStatus.invited) {
      rows.add(
        _ActRow(
          icon: LucideIcons.send,
          accent: true,
          title: context.t('admin.um.resendInvitation'),
          subtitle: context.t('admin.um.resendInvitationSub'),
          onTap: () {
            close();
            actions.openResend([u.id]);
          },
        ),
      );
    } else if (u.status == UserStatus.active) {
      rows.add(
        _ActRow(
          icon: LucideIcons.ban,
          title: context.t('admin.um.deactivateAccount'),
          subtitle: context.t('admin.um.deactivateAccountSub'),
          onTap: () {
            close();
            actions.openDeactivate([u.id]);
          },
        ),
      );
    } else if (u.status == UserStatus.pendingApproval) {
      rows.add(
        _ActRow(
          icon: LucideIcons.userCheck,
          success: true,
          title: context.t('admin.um.approve'),
          subtitle: context.t('admin.approvalHint'),
          onTap: () {
            close();
            actions.approve([u.id]);
          },
        ),
      );
    } else {
      rows.add(
        _ActRow(
          icon: LucideIcons.circleCheck,
          success: true,
          title: context.t('admin.um.reactivateAccount'),
          subtitle: context.t('admin.um.reactivateAccountSub'),
          onTap: () {
            close();
            actions.activate([u.id]);
          },
        ),
      );
    }

    final isAdmin = u.role == AdminRole.admin;
    rows.add(
      _ActRow(
        icon: isAdmin ? LucideIcons.shieldMinus : LucideIcons.shieldCheck,
        title: context.t(
          isAdmin ? 'admin.um.revokeAdminRights' : 'admin.um.promoteToAdmin',
        ),
        subtitle: context.t(
          isAdmin
              ? 'admin.um.revokeAdminRightsSub'
              : 'admin.um.promoteToAdminSub',
        ),
        enabled: isAdmin ? !lastAdmin : u.status != UserStatus.invited,
        disabledReason: context.t(
          isAdmin ? 'admin.um.reasonLastAdmin' : 'admin.um.reasonPendingInvite',
        ),
        onTap: () {
          close();
          actions.setRole([u.id], isAdmin ? AdminRole.user : AdminRole.admin);
        },
      ),
    );

    if (u.status != UserStatus.invited) {
      rows.add(
        _ActRow(
          icon: LucideIcons.keyRound,
          title: context.t(
            u.sso
                ? 'admin.um.passwordManagedByIdp'
                : 'admin.um.sendPasswordReset',
          ),
          subtitle: u.sso
              ? context.t('admin.um.passwordManagedByIdpSub')
              : context.t(
                  'admin.um.sendPasswordResetSub',
                  variables: {'email': u.email},
                ),
          enabled: !u.sso,
          disabledReason: context.t('admin.um.reasonSsoManaged'),
          onTap: () {
            close();
            actions.openReset([u.id]);
          },
        ),
      );
      rows.add(
        _ActRow(
          icon: LucideIcons.logOut,
          title: context.t('admin.um.revokeAllSessions'),
          subtitle: context.t(
            'admin.um.revokeAllSessionsSub',
            variables: {'n': '${u.sessions}'},
          ),
          enabled: u.sessions > 0,
          disabledReason: context.t('admin.um.reasonNoSessions'),
          onTap: () {
            close();
            actions.revokeSessions([u.id]);
          },
        ),
      );
    }

    return _withGaps(rows);
  }

  List<Widget> _timeline(BuildContext context, AdminUser u) {
    final entries = <(String, String)>[];
    if (u.lastActive != null) {
      entries.add((
        context.t('admin.um.tlLastActive'),
        umRelTime(context, u.lastActive),
      ));
    }
    if (u.status == UserStatus.invited) {
      final inviter = actions.nameById(u.invitedBy);
      entries.add((
        u.inviteExpired
            ? context.t('admin.um.tlInviteExpired')
            : (inviter != null
                  ? context.t(
                      'admin.um.tlInvitedBy',
                      variables: {'name': inviter.split(' ').first},
                    )
                  : context.t('admin.um.tlInvited')),
        umPrettyDate(u.invitedAt),
      ));
    } else if (u.joinedAt != null) {
      entries.add((context.t('admin.um.tlJoined'), umPrettyDate(u.joinedAt)));
    }
    entries.add((
      context.t(
        'admin.um.tlCreatedVia',
        variables: {'origin': originLabel(u.origin)},
      ),
      umPrettyDate(u.joinedAt ?? u.invitedAt),
    ));

    return [
      for (var i = 0; i < entries.length; i++)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(top: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (i != entries.length - 1)
                    Expanded(
                      child: Container(width: 1.5, color: AppColors.hairline),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entries[i].$1,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        entries[i].$2,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _withGaps(List<Widget> rows) {
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) out.add(const SizedBox(height: 8));
      out.add(rows[i]);
    }
    return out;
  }
}

/// A large tappable action button in the drawer's Manage / Danger sections.
class _ActRow extends StatelessWidget {
  const _ActRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.disabledReason,
    this.danger = false,
    this.accent = false,
    this.success = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;
  final String? disabledReason;
  final bool danger;
  final bool accent;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final Color tint = danger
        ? AppColors.danger
        : accent
        ? AppColors.accentStrong
        : success
        ? AppColors.success
        : AppColors.ink;
    final iconBg = danger
        ? AppColors.dangerSoft
        : accent
        ? AppColors.accentSoft
        : success
        ? AppColors.success.withValues(alpha: 0.12)
        : AppColors.surfaceMuted;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: danger ? AppColors.danger : AppColors.ink,
                      ),
                    ),
                    Text(
                      enabled ? subtitle : (disabledReason ?? subtitle),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fixed width of the desktop detail drawer.
const double kUmDrawerWidth = 440;
