import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/hivora_repository.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/content_models.dart';
import '../../core/models/core_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hex_mark.dart';
import '../../core/widgets/honeycomb_background.dart';
import '../../core/widgets/app_avatar.dart';

class _Destination {
  const _Destination(this.route, this.labelKey, this.icon);

  final String route;
  final String labelKey;
  final IconData icon;
}

const _primary = [
  _Destination('/dashboard', 'nav.dashboard', Icons.dashboard_rounded),
  _Destination('/projects', 'nav.projects', Icons.folder_rounded),
  _Destination('/issues', 'nav.issues', Icons.task_alt_rounded),
  _Destination('/board', 'nav.board', Icons.view_kanban_rounded),
];

const _secondary = [
  _Destination('/gantt', 'nav.gantt', Icons.stacked_bar_chart_rounded),
  _Destination('/timesheet', 'nav.timesheet', Icons.table_chart_rounded),
  _Destination('/reports', 'nav.reports', Icons.insights_rounded),
  _Destination('/knowledge', 'nav.knowledge', Icons.menu_book_rounded),
];

const _bottomTabs = [
  _Destination('/dashboard', 'nav.dashboard', Icons.dashboard_rounded),
  _Destination('/issues', 'nav.issues', Icons.task_alt_rounded),
  _Destination('/board', 'nav.board', Icons.view_kanban_rounded),
  _Destination('/more', 'nav.more', Icons.grid_view_rounded),
];

/// Responsive scaffold:
/// • phone/compact (<987): Liquid-Glass floating bottom nav
/// • desktop/wide (≥987): persistent dark Navy rail on the left
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, size) => size == LayoutSize.compact
          ? _CompactShell(location: location, child: child)
          : _WideShell(location: location, child: child),
    );
  }
}

// Maps the current location to the nav route that should appear active.
// /boards/:id      → /board (Board nav item)
// /projects/:id/*  → /projects (Projects nav item)
bool _isActive(String location, String navRoute) {
  if (navRoute == '/board') {
    return location.startsWith('/board') || location.startsWith('/boards/');
  }
  if (navRoute == '/projects') {
    return location.startsWith('/projects');
  }
  return location.startsWith(navRoute);
}

// ─────────────────────────── Wide Shell (Navy Rail) ───────────────────────

class _WideShell extends StatelessWidget {
  const _WideShell({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isMedium = context.layoutSize == LayoutSize.medium;
    final railWidth = isMedium ? 76.0 : 244.0;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Row(
        children: [
          _NavRail(
            location: location,
            collapsed: isMedium,
            width: railWidth,
          ),
          Expanded(
            child: Column(
              children: [
                _HivoraTopBar(location: location, compact: false),
                // The top bar already consumes the status-bar inset, so zero the
                // top padding for the content — keeps context.topGutter at 0 on
                // wide layouts (no overlay app bar there).
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  const _NavRail({
    required this.location,
    required this.collapsed,
    required this.width,
  });

  final String location;
  final bool collapsed;
  final double width;

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc bloc) => bloc.state.user);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      width: width,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.rail, AppColors.rail2],
        ),
      ),
      child: Stack(
        children: [
          // Faint honeycomb texture pooling at the base of the rail.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 240,
            child: HoneycombBackground(),
          ),
          SafeArea(
            child: Column(
          // Centre every item on the rail's vertical axis when collapsed;
          // left-align them in the expanded view.
          crossAxisAlignment:
              collapsed ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            // Logo
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 18 : 20,
                vertical: 20,
              ),
              child: collapsed
                  ? HexMark(size: 32, color: AppColors.accent)
                  : Row(
                      children: [
                        HexMark(size: 28, color: AppColors.accent),
                        const SizedBox(width: 10),
                        const Text(
                          'hivora',
                          style: TextStyle(
                            fontFamily: AppTheme.fontBrand,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                    ),
            ),

            // New issue CTA
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 12 : 16,
                vertical: 4,
              ),
              child: collapsed
                  ? _RailIconButton(
                      icon: Icons.add_rounded,
                      active: false,
                      amber: true,
                      tooltip: 'New issue',
                      onTap: () {},
                    )
                  : DecoratedBox(
                      // Soft honey glow beneath the CTA (matches the web
                      // prototype's box-shadow: 0 6px 18px -8px amber/0.7).
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusControl),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.45),
                            blurRadius: 18,
                            spreadRadius: -6,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => context.go('/issues'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: const Color(0xFF2A2410),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusControl),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            textStyle: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13.5),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('New issue'),
                        ),
                      ),
                    ),
            ),

            const SizedBox(height: 16),

            // Primary group
            if (!collapsed)
              _RailGroupLabel('WORK'),
            for (final dest in _primary)
              _RailItem(
                destination: dest,
                selected: _isActive(location, dest.route),
                collapsed: collapsed,
              ),

            const SizedBox(height: 8),
            if (!collapsed) _RailGroupLabel('PLAN'),
            for (final dest in _secondary)
              _RailItem(
                destination: dest,
                selected: _isActive(location, dest.route),
                collapsed: collapsed,
              ),

            const Spacer(),

            if (!collapsed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: InkWell(
                  onTap: () => context.go('/settings'),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      AppAvatar(
                        name: user?.displayName ?? '?',
                        imageUrl: user?.avatarUrl,
                        radius: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              user?.displayName ?? '',
                              style: const TextStyle(
                                  color: AppColors.railInk,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              user?.email ?? '',
                              style: const TextStyle(
                                  color: AppColors.railFaint, fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: InkWell(
                    onTap: () => context.go('/settings'),
                    borderRadius: BorderRadius.circular(20),
                    child: AppAvatar(
                      name: user?.displayName ?? '?',
                      imageUrl: user?.avatarUrl,
                      radius: 16,
                    ),
                  ),
                ),
              ),
          ],
        ),
          ),
        ],
      ),
    );
  }
}

class _RailGroupLabel extends StatelessWidget {
  const _RailGroupLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppColors.railFaint,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.collapsed,
  });

  final _Destination destination;
  final bool selected;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 8 : 10, vertical: 2),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Clean amber edge indicator (3×18, rounded) — sits just outside
          // the tile's left edge like the prototype's `::before` bar.
          if (selected && !collapsed)
            Positioned(
              left: -10,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => context.go(destination.route),
              borderRadius: BorderRadius.circular(8),
              hoverColor: Colors.white.withValues(alpha: 0.06),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: collapsed ? null : double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: collapsed ? 10 : 12,
                  vertical: 9,
                ),
                decoration: selected
                    ? BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: collapsed
                ? Tooltip(
                    message: context.t(destination.labelKey),
                    preferBelow: false,
                    child: Icon(
                      destination.icon,
                      size: 20,
                      color: selected ? AppColors.accent : AppColors.railFaint,
                    ),
                  )
                : Row(
                    children: [
                      Icon(
                        destination.icon,
                        size: 18,
                        color: selected
                            ? AppColors.accent
                            : AppColors.railFaint,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        context.t(destination.labelKey),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selected
                              ? AppColors.railInk
                              : AppColors.railFaint,
                        ),
                      ),
                    ],
                  ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailIconButton extends StatelessWidget {
  const _RailIconButton({
    required this.icon,
    required this.active,
    required this.onTap,
    this.amber = false,
    this.tooltip,
  });

  final IconData icon;
  final bool active;
  final bool amber;
  final String? tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: amber ? AppColors.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon,
              size: 20,
              color: amber ? const Color(0xFF2A2410) : AppColors.railFaint),
        ),
      ),
    );
    return tooltip != null
        ? Tooltip(message: tooltip!, child: child)
        : child;
  }
}

// ─────────────────────────── App top bar ───────────────────────────────────
// Shared across every screen size. Left → right: brand mark (compact only),
// breadcrumb, global search, notification bell (with unread dot + popover),
// settings. The bell + settings live here so they never disappear on mobile.

class _HivoraTopBar extends StatelessWidget {
  const _HivoraTopBar({required this.location, required this.compact});

  final String location;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final all = [..._primary, ..._secondary];
    final current = all.firstWhere(
      (d) => _isActive(location, d.route),
      orElse: () => const _Destination('/', 'nav.dashboard', Icons.home_rounded),
    );
    final segStyle = TextStyle(fontSize: 13, color: AppColors.inkSoft);
    final curStyle = TextStyle(
        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 28, vertical: 11),
          child: Row(
            children: [
              if (compact) ...[
                HexMark(size: 26, color: AppColors.accent),
                const SizedBox(width: 12),
              ],
              // Breadcrumb zone. A single Expanded absorbs all free space (so the
              // search + actions sit flush right) and shrinks/ellipsises under
              // pressure (so nothing overflows on narrow widths). On compact only
              // the current page label shows.
              Expanded(
                child: Row(
                  children: [
                    if (!compact) ...[
                      Text(context.t('appbar.workspace'), style: segStyle),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.chevron_right_rounded,
                            size: 16, color: AppColors.inkFaint),
                      ),
                    ],
                    Flexible(
                      child: Text(
                        context.t(current.labelKey),
                        style: curStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _TopSearchField(compact: compact),
              const SizedBox(width: 8),
              _NotificationBell(active: location.startsWith('/notifications')),
              const SizedBox(width: 4),
              _TopIconButton(
                icon: Icons.settings_rounded,
                tooltip: context.t('nav.settings'),
                active: location.startsWith('/settings'),
                onTap: () => context.go('/settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill global-search field. Collapses to a single icon button on compact.
class _TopSearchField extends StatelessWidget {
  const _TopSearchField({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _TopIconButton(
        icon: Icons.search_rounded,
        tooltip: context.t('appbar.search'),
        onTap: () {},
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300, maxHeight: 38),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          side: BorderSide(color: AppColors.hairline),
        ),
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                Icon(Icons.search_rounded,
                    size: 16, color: AppColors.inkFaint),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    context.t('appbar.search'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.inkFaint),
                  ),
                ),
                const SizedBox(width: 9),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Text(
                    '⌘K',
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 38×38 ghost icon button matching the prototype's `.icon-btn`.
class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
    this.child,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;

  /// Optional overlay (e.g. the unread dot) painted above the icon.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: active ? AppColors.surface : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        side: BorderSide(
            color: active ? AppColors.hairline : Colors.transparent),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        hoverColor: AppColors.surface,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: active ? AppColors.ink : AppColors.inkSoft),
              ?child,
            ],
          ),
        ),
      ),
    );
    return tooltip != null
        ? Tooltip(message: tooltip!, child: button)
        : button;
  }
}

// ─────────────────────────── Notification bell + popover ──────────────────

/// Bell action with an unread dot and an anchored popover listing the 10 most
/// recent notifications. The popover footer links to the full list.
class _NotificationBell extends StatefulWidget {
  const _NotificationBell({required this.active});

  final bool active;

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
    _cubit = FetchCubit(() => context.read<HivoraRepository>().notifications())
      ..load();
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
      await context.read<HivoraRepository>().markNotificationsRead(unread);
    } catch (_) {
      // Non-critical; the reload below reflects server truth.
    }
    await _cubit.load();
  }

  Future<void> _openNotification(AppNotification notification) async {
    _close();
    final repository = context.read<HivoraRepository>();
    if (!notification.read) {
      try {
        await repository.markNotificationRead(notification.id);
      } catch (_) {}
      _cubit.load();
    }
    final link = notification.link;
    if (link != null && link.startsWith('/issues/') && mounted) {
      context.go(link);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<FetchCubit<List<AppNotification>>,
          FetchState<List<AppNotification>>>(
        builder: (context, state) {
          final items = state.data ?? const <AppNotification>[];
          final hasUnread = items.any((n) => !n.read);
          return OverlayPortal(
            controller: _portalController,
            overlayChildBuilder: (_) => _buildOverlay(items),
            child: CompositedTransformTarget(
              link: _link,
              child: _TopIconButton(
                icon: Icons.notifications_none_rounded,
                tooltip: context.t('nav.notifications'),
                active: widget.active || _open,
                onTap: _toggle,
                child: (hasUnread && !_open)
                    ? const Positioned(top: 7, right: 8, child: _UnreadDot())
                    : null,
              ),
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

    return _PopIn(
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: AppColors.hairline),
          boxShadow: const [
            BoxShadow(
              color: Color(0x222D2B55),
              blurRadius: 28,
              spreadRadius: -6,
              offset: Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
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
                          color: AppColors.ink),
                    ),
                    const Spacer(),
                    if (hasUnread)
                      InkWell(
                        onTap: onMarkAllRead,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Text(
                            context.t('notifications.markAllRead'),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.accentStrong),
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
                  padding:
                      const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
                  child: Text(
                    context.t('notifications.empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.inkSoft, fontSize: 13),
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
                            color: AppColors.inkSoft),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded,
                          size: 15, color: AppColors.inkSoft),
                    ],
                  ),
                ),
              ),
            ],
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
    final (icon, tint) = _notifVisual(notification.type);
    final ago = _timeAgo(notification.createdAt);
    return Material(
      color: unread ? AppColors.accentSoft : AppColors.surface,
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
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (ago != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            ago,
                            style: TextStyle(
                                fontSize: 11, color: AppColors.inkFaint),
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
                            height: 1.4),
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

/// Leading icon + tint for a notification type.
(IconData, Color) _notifVisual(String type) => switch (type.toUpperCase()) {
      'MENTION' => (Icons.alternate_email_rounded, AppColors.stReview),
      'ASSIGN' ||
      'ASSIGNED' ||
      'ASSIGNMENT' =>
        (Icons.assignment_ind_rounded, AppColors.stTodo),
      'COMMENT' => (Icons.mode_comment_outlined, AppColors.stProgress),
      'REVIEW' ||
      'REVIEW_REQUEST' =>
        (Icons.rate_review_rounded, AppColors.stReview),
      'DUE' || 'DEADLINE' => (Icons.event_rounded, AppColors.priHigh),
      _ => (Icons.notifications_rounded, AppColors.inkSoft),
    };

/// Compact relative time ("now", "8m", "2h", "3d", "5w").
String? _timeAgo(DateTime? time) {
  if (time == null) return null;
  final diff = DateTime.now().difference(time);
  if (diff.isNegative || diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${(diff.inDays / 7).floor()}w';
}

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
    final curve =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
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

// ─────────────────────────── Compact Shell (Liquid-Glass) ─────────────────

/// Content height of the compact glass app bar (excludes the status-bar inset).
const double _kCompactBarHeight = 52;

class _CompactShell extends StatefulWidget {
  const _CompactShell({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  State<_CompactShell> createState() => _CompactShellState();
}

class _CompactShellState extends State<_CompactShell> {
  int get _selectedIndex {
    for (var i = 0; i < _bottomTabs.length - 1; i++) {
      if (_isActive(widget.location, _bottomTabs[i].route)) return i;
    }
    // Everything not in first 3 tabs → "More" tab (index 3)
    final inPrimary =
        _primary.any((d) => _isActive(widget.location, d.route));
    return inPrimary ? 0 : 3;
  }

  void _onTap(int index) {
    final tab = _bottomTabs[index];
    if (tab.route == '/more') {
      _showMoreSheet();
    } else {
      context.go(tab.route);
    }
  }

  void _showMoreSheet() {
    final user = context.read<AuthBloc>().state.user;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _MoreSheet(
        location: widget.location,
        user: user,
        onNavigate: (route) {
          Navigator.of(sheetCtx).pop();
          context.go(route);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      // Content fills the whole screen and scrolls *behind* the translucent
      // glass app bar and the floating glass nav. We inject both bars'
      // footprints into MediaQuery.padding so screens clear them via
      // context.topGutter / context.bottomGutter while still blurring through.
      body: Stack(
        children: [
          Positioned.fill(
            child: Builder(builder: (context) {
              final mq = MediaQuery.of(context);
              // Glass app bar: status-bar inset + bar content height.
              final topFootprint = _kCompactBarHeight + mq.viewPadding.top;
              // Floating nav: container(64) + padding-bottom(14) + safe-area.
              final navFootprint = 78 + mq.viewPadding.bottom;
              return MediaQuery(
                data: mq.copyWith(
                  padding: mq.padding.copyWith(
                    top: topFootprint,
                    bottom: navFootprint,
                  ),
                  viewPadding: mq.viewPadding.copyWith(
                    top: topFootprint,
                    bottom: navFootprint,
                  ),
                ),
                // Keep left/right safe-area handling; top/bottom flow through as
                // gutters so content can scroll behind the bars.
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: widget.child,
                ),
              );
            }),
          ),
          // Black gradient scrim rising from the bottom up to the nav so content
          // dissolves beneath the floating glass pill.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(child: _BottomNavScrim()),
          ),
          // Floating liquid-glass nav — NOT in bottomNavigationBar, so its
          // rounded corners and BackdropFilter are never clipped.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _LiquidGlassNav(index: _selectedIndex, onTap: _onTap),
          ),
          // Transparent glass app bar with a top-down scrim — overlays content.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _GlassTopBar(location: widget.location),
          ),
        ],
      ),
    );
  }
}

/// Transparent liquid-glass app bar for the compact (mobile) shell. Blurs the
/// content scrolling beneath it and lays a subtle top-down black scrim so the
/// status bar and title stay legible. Centered page title, brand mark on the
/// left, the always-visible action icons (search · notifications · settings)
/// grouped in a glass capsule on the right.
class _GlassTopBar extends StatelessWidget {
  const _GlassTopBar({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final all = [..._primary, ..._secondary];
    final current = all.firstWhere(
      (d) => _isActive(location, d.route),
      orElse: () =>
          const _Destination('/', 'nav.dashboard', Icons.home_rounded),
    );
    // Black scrim, strongest under the status bar, fading to nothing at the
    // bar's lower edge. Subtle in light (keeps dark status-bar icons legible),
    // stronger in dark.
    final scrimTop = dark ? 0.55 : 0.18;
    final height = topInset + _kCompactBarHeight;

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          // Progressive blur: heavy at the top, fading to perfectly sharp at the
          // lower edge — so the bar dissolves into the content instead of ending
          // on a hard cut-off line.
          Positioned.fill(
            child: _ProgressiveBlur(maxSigma: dark ? 26 : 22),
          ),
          // Matching darkening scrim (also fades to transparent at the bottom).
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: scrimTop),
                    Colors.black.withValues(alpha: scrimTop * 0.4),
                    Colors.black.withValues(alpha: 0),
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),
          ),
          // Bar content sits below the status bar inset.
          Positioned(
            top: topInset,
            left: 0,
            right: 0,
            height: _kCompactBarHeight,
            child: Stack(
              children: [
                // Centered page title. The horizontal reserve clears the brand
                // mark (left) and the 3-icon action capsule (right) so a long
                // title ellipsizes instead of ever overlapping them.
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 136),
                    child: Text(
                      context.t(current.labelKey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
                // Brand mark, left.
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: HexMark(size: 24, color: AppColors.accent),
                  ),
                ),
                // Action capsule, right.
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _GlassActionCapsule(location: location),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A vertical *gradient* backdrop blur: the blur is strongest at the top and
/// eases to zero at the bottom, so the frosted region melts into the sharp
/// content beneath it (no hard cut-off edge).
///
/// Implemented as a stack of thin horizontal slices each running its own
/// [BackdropFilter] with a decreasing sigma. A single masked BackdropFilter
/// can't do this — a BackdropFilter has no backdrop to sample once it's wrapped
/// in a ShaderMask's layer — so slicing is the reliable primitive-only route.
class _ProgressiveBlur extends StatelessWidget {
  const _ProgressiveBlur({required this.maxSigma});

  final double maxSigma;

  /// Number of blur bands. More = smoother gradient, but each is a separate
  /// (costly) BackdropFilter; 8 reads as continuous on a ~100px bar.
  static const int _slices = 8;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Column(
        children: [
          for (var i = 0; i < _slices; i++)
            Expanded(
              child: _BlurSlice(
                // i=0 → full sigma at the top; last slice → ~0 (sharp).
                sigma: maxSigma * (1 - i / (_slices - 1)),
              ),
            ),
        ],
      ),
    );
  }
}

class _BlurSlice extends StatelessWidget {
  const _BlurSlice({required this.sigma});

  final double sigma;

  @override
  Widget build(BuildContext context) {
    // Below ~0.3 a blur is imperceptible; skip the filter so the bottom slices
    // stay genuinely sharp and cheap.
    if (sigma < 0.3) return const SizedBox.expand();
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Translucent rounded capsule grouping the persistent top-bar actions
/// (search · notifications · settings) — mirrors the iOS liquid-glass action
/// pill. Theme-aware frosted fill.
class _GlassActionCapsule extends StatelessWidget {
  const _GlassActionCapsule({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: dark ? const Color(0x26FFFFFF) : const Color(0x4DFFFFFF),
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            border: Border.all(
              color: dark ? const Color(0x33FFFFFF) : const Color(0x59FFFFFF),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TopSearchField(compact: true),
              _NotificationBell(active: location.startsWith('/notifications')),
              _TopIconButton(
                icon: Icons.settings_rounded,
                tooltip: context.t('nav.settings'),
                active: location.startsWith('/settings'),
                onTap: () => context.go('/settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Black gradient that fades up from the bottom edge to behind the floating
/// nav, so scrolling content dissolves beneath it (the liquid-glass scrim).
class _BottomNavScrim extends StatelessWidget {
  const _BottomNavScrim();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pad = MediaQuery.viewPaddingOf(context).bottom;
    return SizedBox(
      height: 96 + pad,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0),
              Colors.black.withValues(alpha: dark ? 0.42 : 0.12),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiquidGlassNav extends StatelessWidget {
  const _LiquidGlassNav({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewPaddingOf(context).bottom;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    // Frosted glass: a bright specular top easing into a thinner film at the
    // bottom — the liquid-glass body, over the blurred content (light or dark).
    final fill = dark
        ? const [Color(0x40FFFFFF), Color(0x1AFFFFFF), Color(0x0FFFFFFF)]
        : const [Color(0xA6FFFFFF), Color(0x66FFFFFF), Color(0x4DFFFFFF)];
    final borderColor = dark ? const Color(0x40FFFFFF) : const Color(0x8AFFFFFF);
    final shadowColor = dark ? const Color(0x73000000) : const Color(0x332D2B55);

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + pad),
      // Shadow lives OUTSIDE ClipRRect so it is never clipped away.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 30,
              spreadRadius: -4,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              height: 64,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: fill,
                  stops: const [0.0, 0.55, 1.0],
                ),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: LayoutBuilder(builder: (context, c) {
                final tabW = c.maxWidth / _bottomTabs.length;
                return Stack(
                  children: [
                    // Specular rim: a thin bright highlight hugging the top edge.
                    Positioned(
                      top: 0,
                      left: 14,
                      right: 14,
                      height: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0),
                              Colors.white.withValues(alpha: dark ? 0.45 : 0.85),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: reducedMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 500),
                      curve: const Cubic(0.5, 1.5, 0.4, 1),
                      left: index * tabW,
                      width: tabW,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          // Honey-amber active indicator (kept per request).
                          color: AppColors.accentSoft,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.accent
                                .withValues(alpha: dark ? 0.50 : 0.32),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accent
                                  .withValues(alpha: dark ? 0.28 : 0.18),
                              blurRadius: 12,
                              spreadRadius: -2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < _bottomTabs.length; i++)
                          Expanded(
                            child: _GlassTab(
                              data: _bottomTabs[i],
                              active: i == index,
                              onTap: () => onTap(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassTab extends StatelessWidget {
  const _GlassTab(
      {required this.data, required this.active, required this.onTap});

  final _Destination data;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Honey-amber active accent (brighter on dark for contrast); muted ink idle.
    final color = active
        ? (dark ? AppColors.accent : AppColors.accentStrong)
        : AppColors.inkSoft;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            duration: const Duration(milliseconds: 400),
            scale: active ? 1.06 : 1.0,
            child: Icon(data.icon, size: 22, color: color),
          ),
          const SizedBox(height: 3),
          Text(
            context.t(data.labelKey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreSheet extends StatelessWidget {
  const _MoreSheet({
    required this.location,
    required this.onNavigate,
    this.user,
  });

  final String location;
  final void Function(String route) onNavigate;
  final AuthUser? user;

  static const _items = [
    _Destination('/projects', 'nav.projects', Icons.folder_rounded),
    _Destination('/gantt', 'nav.gantt', Icons.stacked_bar_chart_rounded),
    _Destination('/timesheet', 'nav.timesheet', Icons.table_chart_rounded),
    _Destination('/reports', 'nav.reports', Icons.insights_rounded),
    _Destination('/knowledge', 'nav.knowledge', Icons.menu_book_rounded),
    _Destination('/settings', 'nav.settings', Icons.settings_rounded),
    // Notifications intentionally omitted — they live in the always-visible
    // top bar bell, so they need no entry in the overflow sheet.
  ];

  @override
  Widget build(BuildContext context) {
    final subtitle = user?.title?.isNotEmpty == true
        ? user!.title!
        : user?.roles.isNotEmpty == true
            ? user!.roles.first.toLowerCase()
            : user?.email ?? '';

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.96),
            border: Border(top: BorderSide(color: AppColors.hairline)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // User header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                  child: Row(
                    children: [
                      AppAvatar(
                        name: user?.displayName ?? '?',
                        imageUrl: user?.avatarUrl,
                        radius: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              user?.displayName ?? '',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: AppColors.ink,
                              ),
                            ),
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close_rounded,
                            size: 20, color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppColors.hairline),
                const SizedBox(height: 12),
                // Compact 3-column grid — fixed row height so tiles never bloat
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (context, i) => _MoreTile(
                    destination: _items[i],
                    active: location.startsWith(_items[i].route),
                    onTap: () => onNavigate(_items[i].route),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile(
      {required this.destination, required this.active, required this.onTap});

  final _Destination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = active ? AppColors.accentStrong : AppColors.inkSoft;
    final badgeBg = active ? AppColors.accentSoft : AppColors.canvas2;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(
              color: active ? AppColors.accentLine : AppColors.hairline,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon badge — small rounded square, matches reference design
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(destination.icon, size: 20, color: iconColor),
              ),
              const SizedBox(height: 7),
              Text(
                context.t(destination.labelKey),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: iconColor,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
