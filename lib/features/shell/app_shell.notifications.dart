part of 'app_shell.dart';

// ─────────────────────────── Notification bell + popover ──────────────────

/// Bell action with an unread dot and an anchored popover listing the 10 most
/// recent notifications. The popover footer links to the full list.
class _NotificationBell extends StatefulWidget {
  const _NotificationBell({
    required this.active,
    this.dark = false,
    this.frosted = false,
  });

  final bool frosted;
  final bool active;

  /// When true the trigger is a standalone iOS-26 [_FrostedCircleButton]
  /// (mobile top bar); otherwise the desktop ghost [_TopIconButton].
  final bool dark;

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  final _portalController = OverlayPortalController();
  final _link = LayerLink();
  late final FetchCubit<List<AppNotification>> _cubit;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _cubit = FetchCubit(
      () => context.read<NotificationRepository>().notifications(),
    )..load();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _cubit.load(); // refresh contents whenever the popover opens
      setState(() => _open = true);
      _portalController.show();
    }
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _portalController.hide();
  }

  Future<void> _markAllRead(List<AppNotification> items) async {
    final unread = items.where((n) => !n.read).map((n) => n.id).toList();
    if (unread.isEmpty) return;
    try {
      await context.read<NotificationRepository>().markNotificationsRead(
        unread,
      );
    } catch (_) {
      // Non-critical; the reload below reflects server truth.
    }
    await _cubit.load();
  }

  Future<void> _openNotification(AppNotification notification) async {
    _close();
    final repository = context.read<NotificationRepository>();
    if (!notification.read) {
      try {
        await repository.markNotificationRead(notification.id);
      } catch (_) {}
      _cubit.load();
    }
    final link = notification.link;
    // Any in-app route (issues, projects, teams, admin …), not just issues, so
    // every notification type is tappable from the bell like it is in the feed.
    if (link != null && link.startsWith('/') && mounted) {
      context.go(link);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child:
          BlocBuilder<
            FetchCubit<List<AppNotification>>,
            FetchState<List<AppNotification>>
          >(
            builder: (context, state) {
              final items = state.data ?? const <AppNotification>[];
              final hasUnread = items.any((n) => !n.read);
              final showDot = hasUnread && !_open;
              final trigger = widget.frosted
                  ? _FrostedCircleButton(
                      icon: LucideIcons.bell,
                      tooltip: context.t('nav.notifications'),
                      active: widget.active || _open,
                      onTap: _toggle,
                      overlay: showDot
                          ? const Positioned(
                              top: 8,
                              right: 9,
                              child: _UnreadDot(),
                            )
                          : null,
                    )
                  : _TopIconButton(
                      icon: LucideIcons.bell,
                      tooltip: context.t('nav.notifications'),
                      active: widget.active || _open,
                      onTap: _toggle,
                      child: showDot
                          ? const Positioned(
                              top: 7,
                              right: 8,
                              child: _UnreadDot(),
                            )
                          : null,
                    );
              final nativeButton = GlassButton(
                icon: const Icon(LucideIcons.bell),
                onTap: _toggle,
                width: 42,
                height: 42,
                iconSize: 18,
                useOwnLayer: true,
                settings: widget.dark ? kNavGlassDark : kNavGlassLight,
                iconColor: widget.dark ? AppColors.inkDark : AppColors.ink,
                glowColor: AppColors.accent,

                // Keep the tactile press-scale but damp the liquid drag-follow so the
                // isolated button doesn't over-stretch on tap.
                stretch: 0.15,
              );
              final mobileTrigger = Tooltip(
                message: context.t('nav.notifications'),
                child: Badge(
                  backgroundColor: AppColors.accent,
                  smallSize: 10.5,
                  isLabelVisible: showDot,
                  child: nativeButton,
                ),
              );
              return OverlayPortal(
                controller: _portalController,
                overlayChildBuilder: (_) => _buildOverlay(items),
                child: CompositedTransformTarget(
                  link: _link,
                  child: isNativeApp ? mobileTrigger : trigger,
                ),
              );
            },
          ),
    );
  }

  Widget _buildOverlay(List<AppNotification> items) {
    return Stack(
      children: [
        // Transparent click-catcher (mirrors the prototype's z-29 backdrop).
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 8),
          child: Align(
            alignment: Alignment.topRight,
            child: _NotifPopoverCard(
              items: items,
              onMarkAllRead: () => _markAllRead(items),
              onTapNotification: _openNotification,
              onViewAll: () {
                _close();
                context.go('/notifications');
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: AppColors.accentStrong,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.canvas, width: 2),
      ),
    );
  }
}

class _NotifPopoverCard extends StatelessWidget {
  const _NotifPopoverCard({
    required this.items,
    required this.onMarkAllRead,
    required this.onTapNotification,
    required this.onViewAll,
  });

  final List<AppNotification> items;
  final VoidCallback onMarkAllRead;
  final void Function(AppNotification) onTapNotification;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = (media.size.width - 24).clamp(0.0, 340.0);
    final maxListHeight = media.size.height * 0.5;
    final latest = items.take(10).toList();
    final hasUnread = items.any((n) => !n.read);
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // A touch more opaque than the shared search glass so notification text
    // reads clearly over busy backgrounds (still glassy, just a tick denser).
    final glassFill = tokens.glassFill.withValues(
      alpha: (tokens.glassFill.a + 0.22).clamp(0.0, 0.92),
    );

    return _PopIn(
      child: SizedBox(
        width: width,
        child: GlassPanelShadow(
          radius: BorderRadius.circular(AppTheme.radiusCard),
          shadows: tokens.panelShadow,
          child: GlassContainer(
            useOwnLayer: true,
            quality: GlassQuality.premium,
            clipBehavior: Clip.antiAlias,
            shape: const LiquidRoundedSuperellipse(
              borderRadius: AppTheme.radiusCard,
            ),
            settings: liquidGlassPanelSettings(
              glassFill: glassFill,
              dark: dark,
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                    child: Row(
                      children: [
                        Text(
                          context.t('notifications.title'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: AppColors.ink,
                          ),
                        ),
                        const Spacer(),
                        if (hasUnread)
                          InkWell(
                            onTap: onMarkAllRead,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              child: Text(
                                context.t('notifications.markAllRead'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.accentStrong,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: AppColors.hairline2),
                  // List (max 10 latest)
                  if (latest.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 30,
                        horizontal: 16,
                      ),
                      child: Text(
                        context.t('notifications.empty'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 13,
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxListHeight),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: latest.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: AppColors.hairline2),
                          itemBuilder: (_, i) => _NotifRow(
                            notification: latest[i],
                            onTap: () => onTapNotification(latest[i]),
                          ),
                        ),
                      ),
                    ),
                  Divider(height: 1, color: AppColors.hairline2),
                  // Fixed footer → full notifications page
                  InkWell(
                    onTap: onViewAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            context.t('notifications.viewAll'),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.inkSoft,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            LucideIcons.arrowRight,
                            size: 15,
                            color: AppColors.inkSoft,
                          ),
                        ],
                      ),
                    ),
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

class _NotifRow extends StatelessWidget {
  const _NotifRow({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.read;
    final (icon, tint) = notificationVisual(notification.type);
    final ago = notificationTimeAgo(notification.createdAt);
    return Material(
      // Transparent read rows let the glass panel show through; unread keep a
      // soft accent wash.
      color: unread ? AppColors.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.soft(tint),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: tint),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppColors.ink,
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (ago != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            ago,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.inkFaint,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if ((notification.body ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notification.body!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Icon/tint mapping and relative time live in
// core/notifications/notification_visuals.dart, shared with the full
// notifications page.

/// Subtle scale + fade entrance for the popover (anchored top-right).
class _PopIn extends StatefulWidget {
  const _PopIn({required this.child});
  final Widget child;

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curve,
      child: AnimatedBuilder(
        animation: curve,
        child: widget.child,
        builder: (context, child) => Transform.scale(
          alignment: Alignment.topRight,
          scale: 0.96 + 0.04 * curve.value,
          child: child,
        ),
      ),
    );
  }
}
