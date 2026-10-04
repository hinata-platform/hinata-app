part of 'user_management_screen.dart';

// ════════════════════════════════════════════════════════════════════════
//  Row / card / small controls
// ════════════════════════════════════════════════════════════════════════

class _UserTableRow extends StatelessWidget {
  const _UserTableRow({
    required this.user,
    required this.actions,
    required this.selected,
    required this.onToggle,
    required this.showOrigin,
    required this.isMe,
  });

  final AdminUser user;
  final UserActions actions;
  final bool selected;
  final VoidCallback onToggle;
  final bool showOrigin;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final idle = isIdle(u.lastActive);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.accentSoft.withValues(alpha: 0.4) : null,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          _Checkbox(
            checked: selected,
            mixed: false,
            label: context.t(
              'admin.um.selectUser',
              variables: {'name': u.name},
            ),
            onTap: onToggle,
          ),
          // 10 dp of gap, 6 of them inside the checkbox's hit area.
          const SizedBox(width: 4),
          Expanded(
            flex: 3,
            child: Semantics(
              button: true,
              child: InkWell(
                onTap: () => actions.openDrawer(u),
                child: Row(
                  children: [
                    UserAvatar(name: u.name, imageUrl: u.avatarUrl, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  u.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: AppType.label,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              PronounsLabel(
                                pronouns: u.pronouns,
                                fontSize: AppType.caption,
                                leadingGap: 6,
                              ),
                              if (isMe) _YouChip(),
                            ],
                          ),
                          Text(
                            u.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppType.caption,
                              color: AppColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: RoleBadges(u),
            ),
          ),
          if (showOrigin) Expanded(flex: 2, child: OriginTag(u.origin)),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusBadge(u),
                if (u.inviteExpired)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: _InlineAction(
                      onTap: () => actions.openResend([u.id]),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.send,
                            size: 11,
                            color: AppColors.accentInk,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            context.t('admin.um.resendInvite'),
                            style: TextStyle(
                              fontSize: AppType.caption,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accentInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              umRelTime(context, u.lastActive),
              style: TextStyle(
                fontSize: AppType.label,
                color: idle ? AppColors.inkFaint : AppColors.inkSoft,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: UserRowMenu(
              user: u,
              actions: actions,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  LucideIcons.ellipsisVertical,
                  size: 18,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.actions,
    required this.selected,
    required this.onToggle,
    required this.isMe,
  });

  final AdminUser user;
  final UserActions actions;
  final bool selected;
  final VoidCallback onToggle;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final u = user;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: selected ? AppColors.accentLine : AppColors.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Lifted by the 3 dp of hit area above the box, so the box keeps
              // its place on the card's top edge.
              Transform.translate(
                offset: const Offset(0, -3),
                child: _Checkbox(
                  checked: selected,
                  mixed: false,
                  label: context.t(
                    'admin.um.selectUser',
                    variables: {'name': u.name},
                  ),
                  onTap: onToggle,
                ),
              ),
              // 10 dp of gap, 6 of them inside the checkbox's hit area.
              const SizedBox(width: 4),
              Expanded(
                child: _InlineAction(
                  onTap: () => actions.openDrawer(u),
                  child: Row(
                    children: [
                      UserAvatar(name: u.name, imageUrl: u.avatarUrl, size: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    u.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: AppType.body,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                PronounsLabel(
                                  pronouns: u.pronouns,
                                  fontSize: AppType.caption,
                                  leadingGap: 6,
                                ),
                                if (isMe) _YouChip(),
                              ],
                            ),
                            Text(
                              u.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppType.caption,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              UserRowMenu(
                user: u,
                actions: actions,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    LucideIcons.ellipsisVertical,
                    size: 18,
                    color: AppColors.inkSoft,
                  ),
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
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(LucideIcons.activity, size: 13, color: AppColors.inkFaint),
              const SizedBox(width: 5),
              Text(
                umRelTime(context, u.lastActive),
                style: TextStyle(
                  fontSize: AppType.caption,
                  color: AppColors.inkSoft,
                ),
              ),
              if (u.inviteExpired) ...[
                const Spacer(),
                _InlineAction(
                  onTap: () => actions.openResend([u.id]),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.send,
                        size: 12,
                        color: AppColors.accentInk,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        context.t('admin.um.resendInvite'),
                        style: TextStyle(
                          fontSize: AppType.caption,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accentInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _YouChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        context.t('admin.um.you'),
        style: TextStyle(
          fontSize: AppType.caption,
          fontWeight: FontWeight.w700,
          color: AppColors.accentInk,
        ),
      ),
    ),
  );
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({
    required this.checked,
    required this.mixed,
    required this.label,
    required this.onTap,
  });
  final bool checked;
  final bool mixed;

  /// What ticking it selects, for screen readers.
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = checked || mixed;
    // The box is 18 dp; the padding takes the hit area to the 24 dp floor
    // (WCAG 2.5.8). A full 48 would grow every table row.
    return Semantics(
      checked: checked,
      mixed: mixed,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(0, 3, 6, 3),
          child: Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.navy : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: on ? AppColors.navy : AppColors.hairline,
                width: 1.5,
              ),
            ),
            child: checked
                ? const Icon(LucideIcons.check, size: 13, color: Colors.white)
                : (mixed
                      ? Container(width: 8, height: 2, color: Colors.white)
                      : null),
          ),
        ),
      ),
    );
  }
}

class _PagerButton extends StatelessWidget {
  const _PagerButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 16),
      color: AppColors.inkSoft,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _PageNumber extends StatelessWidget {
  const _PageNumber({
    required this.n,
    required this.active,
    required this.onTap,
  });
  final int n;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The hit area takes in the 2 dp margins and reaches the height of the
    // pager's arrow buttons (40 dp): 34 x 40 without moving a pixel.
    return Semantics(
      button: true,
      selected: active,
      label: context.t('admin.um.pageNumber', variables: {'n': '$n'}),
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.navy : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: active ? null : Border.all(color: AppColors.hairline),
              ),
              child: Text(
                '$n',
                style: TextStyle(
                  fontSize: AppType.label,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : AppColors.inkSoft,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small tappable that is not a button to look at — a text link, a card's
/// name block. It gets the button role and an ink response on a transparent
/// Material, so the press shows over whatever the parent paints.
class _InlineAction extends StatelessWidget {
  const _InlineAction({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: child,
        ),
      ),
    );
  }
}
