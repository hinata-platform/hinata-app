part of 'user_management_widgets.dart';

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
            // Only while the drawer is the top route: a second tap during its
            // slide out would pop the page below, the router's last one included.
            child: GestureDetector(
              onTap: () {
                if (ModalRoute.of(ctx)?.isCurrent ?? false) {
                  Navigator.of(ctx).pop();
                }
              },
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
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
                      radius: BorderRadius.circular(AppTheme.radiusDialog),
                      shadows: tokens.panelShadow,
                      child: GlassContainer(
                        useOwnLayer: true,
                        quality: kPanelGlassQuality,
                        clipBehavior: Clip.antiAlias,
                        shape: const LiquidRoundedSuperellipse(
                          borderRadius: AppTheme.radiusDialog,
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
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: Text(
                                u.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: AppTheme.fontBrand,
                                  fontSize: AppType.heading,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            PronounsLabel(
                              pronouns: u.pronouns,
                              fontSize: AppType.label,
                              leadingGap: 7,
                            ),
                          ],
                        ),
                        Text(
                          u.email,
                          style: TextStyle(
                            fontSize: AppType.label,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.t('common.close'),
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
                children: [RoleBadges(u), StatusBadge(u), OriginTag(u.origin)],
              ),
            ],
          ),
        ),
        // Body
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 28 + bottomInset),
            children: [
              UserAdminSections(
                user: u,
                actions: actions,
                onDismiss: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The organisation role in the drawer: a switch with one line on what the role
/// grants and what it does not.
class OrgAdminToggle extends StatelessWidget {
  const OrgAdminToggle({super.key, required this.user, required this.actions});

  final AdminUser user;
  final UserActions actions;

  @override
  Widget build(BuildContext context) => _RoleToggle(
    user: user,
    held: user.orgAdmin,
    set: actions.setOrgAdmin,
    currentUserId: actions.currentUserId,
    icon: LucideIcons.building2,
    titleKey: 'admin.um.orgAdminTitle',
    hintKey: 'admin.um.orgAdminHint',
    infoKey: 'admin.um.orgAdminInfo',
    ownRoleKey: 'admin.um.reasonOwnOrgRole',
  );
}

/// The moderation role in the drawer (HIN-26), beside the organisation role
/// and built the same way.
class ModeratorToggle extends StatelessWidget {
  const ModeratorToggle({super.key, required this.user, required this.actions});

  final AdminUser user;
  final UserActions actions;

  @override
  Widget build(BuildContext context) => _RoleToggle(
    user: user,
    held: user.moderator,
    set: actions.setModerator,
    currentUserId: actions.currentUserId,
    icon: LucideIcons.shieldUser,
    titleKey: 'admin.um.moderatorTitle',
    hintKey: 'admin.um.moderatorHint',
    infoKey: 'admin.um.moderatorInfo',
    ownRoleKey: 'admin.um.reasonOwnModeratorRole',
  );
}

/// A role held beside the platform role, as a switch with its name, an "i"
/// for what it grants, and the reason when the switch cannot move.
///
/// Holds the value itself so the switch moves at once; it returns to what the
/// server holds when the change is refused (the board shows the error toast).
/// An invitation nobody accepted yet has no account to hand the role to.
class _RoleToggle extends StatefulWidget {
  const _RoleToggle({
    required this.user,
    required this.held,
    required this.set,
    required this.currentUserId,
    required this.icon,
    required this.titleKey,
    required this.hintKey,
    required this.infoKey,
    required this.ownRoleKey,
  });

  final AdminUser user;
  final bool held;
  final Future<bool> Function(List<String> ids, bool grant) set;
  final String? currentUserId;
  final IconData icon;
  final String titleKey;
  final String hintKey;
  final String infoKey;
  final String ownRoleKey;

  @override
  State<_RoleToggle> createState() => _RoleToggleState();
}

class _RoleToggleState extends State<_RoleToggle> {
  late bool _value = widget.held;
  bool _busy = false;

  @override
  void didUpdateWidget(_RoleToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.held != widget.held) {
      _value = widget.held;
    }
  }

  Future<void> _set(bool value) async {
    setState(() {
      _value = value;
      _busy = true;
    });
    final ok = await widget.set([widget.user.id], value);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _value = !value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final invited = widget.user.status == UserStatus.invited;
    // Nobody hands these roles to themselves; the server refuses it too.
    final self = widget.user.id == widget.currentUserId;
    final title = context.t(widget.titleKey);
    // Not one merged node: the "i" next to the title is a control of its own,
    // and merged into the switch a screen reader could not reach it. The
    // switch carries the title as its name instead.
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
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
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.icon, size: 17, color: AppColors.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: ExcludeSemantics(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: AppType.label,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                    // What the role may see is long; it waits behind the
                    // "i" instead of pushing the drawer's actions down.
                    InfoCircleButton(
                      title: title,
                      message: context.t(widget.hintKey),
                      tooltip: context.t(widget.infoKey),
                    ),
                  ],
                ),
                // Only why the switch cannot move stays in view.
                if (invited || self)
                  Text(
                    context.t(
                      invited
                          ? 'admin.um.reasonPendingInvite'
                          : widget.ownRoleKey,
                    ),
                    style: TextStyle(
                      fontSize: AppType.caption,
                      height: 1.3,
                      color: AppColors.inkSoft,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: Center(
              child: Semantics(
                label: title,
                child: HiveSwitch(
                  value: _value,
                  onChanged: invited || self || _busy ? null : _set,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
      child: Semantics(
        button: true,
        enabled: enabled,
        // Ink, not Container: the fill sits on the Material, so the press
        // ripple shows above it.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            child: Ink(
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
                            fontSize: AppType.label,
                            fontWeight: FontWeight.w700,
                            color: danger ? AppColors.dangerInk : AppColors.ink,
                          ),
                        ),
                        Text(
                          enabled ? subtitle : (disabledReason ?? subtitle),
                          style: TextStyle(
                            fontSize: AppType.caption,
                            height: 1.3,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    forwardChevron(context),
                    size: 16,
                    color: AppColors.inkFaint,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fixed width of the desktop detail drawer.
const double kUmDrawerWidth = 440;
