import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hex_mark.dart';
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
                _ContentTopBar(location: location),
                Expanded(child: child),
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.rail, AppColors.rail2],
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {},
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: const Color(0xFF2A2410),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusControl),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New issue'),
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

            // Footer: settings + user
            _RailItem(
              destination: const _Destination(
                  '/notifications', 'nav.notifications', Icons.notifications_none_rounded),
              selected: location.startsWith('/notifications'),
              collapsed: collapsed,
            ),
            _RailItem(
              destination: const _Destination(
                  '/settings', 'nav.settings', Icons.settings_rounded),
              selected: location.startsWith('/settings'),
              collapsed: collapsed,
            ),
            const SizedBox(height: 8),
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
          horizontal: collapsed ? 8 : 10, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => context.go(destination.route),
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 10 : 12,
              vertical: 9,
            ),
            decoration: selected
                ? BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: const Border(
                      left: BorderSide(color: AppColors.accent, width: 3),
                    ),
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

// ─────────────────────────── Content topbar ────────────────────────────────

class _ContentTopBar extends StatelessWidget {
  const _ContentTopBar({required this.location});
  final String location;

  @override
  Widget build(BuildContext context) {
    final all = [..._primary, ..._secondary];
    final current = all.firstWhere(
      (d) => _isActive(location, d.route),
      orElse: () => const _Destination('/', 'nav.dashboard', Icons.home_rounded),
    );
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          Text(
            context.t(current.labelKey),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: AppTheme.fontBrand,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const Spacer(),
          IconButton(
            tooltip: context.t('nav.notifications'),
            onPressed: () => context.go('/notifications'),
            icon: const Icon(Icons.notifications_none_rounded, size: 20),
            color: AppColors.inkSoft,
          ),
          IconButton(
            tooltip: context.t('nav.settings'),
            onPressed: () => context.go('/settings'),
            icon: const Icon(Icons.settings_rounded, size: 20),
            color: AppColors.inkSoft,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Compact Shell (Liquid-Glass) ─────────────────

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
      // Content fills the entire body and scrolls *behind* the floating glass
      // nav — the translucent BackdropFilter blurs whatever passes underneath.
      body: Stack(
        children: [
          // Full-bleed content scrolls *behind* the glass nav. We inject the
          // nav's footprint into MediaQuery.padding.bottom so screens can pad
          // their scroll content clear of it (via context.bottomGutter) while
          // the content still blurs through the translucent glass.
          Positioned.fill(
            child: Builder(builder: (context) {
              final mq = MediaQuery.of(context);
              // Mirrors _LiquidGlassNav: container(64) + padding-bottom(14)
              // + device safe-area = total pixel footprint.
              final navFootprint = 78 + mq.viewPadding.bottom;
              return MediaQuery(
                data: mq.copyWith(
                  padding: mq.padding.copyWith(bottom: navFootprint),
                  viewPadding: mq.viewPadding.copyWith(bottom: navFootprint),
                ),
                child: SafeArea(bottom: false, child: widget.child),
              );
            }),
          ),
          // Glass nav floats on top — NOT in bottomNavigationBar,
          // so its rounded corners and BackdropFilter are never clipped.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _LiquidGlassNav(
              index: _selectedIndex,
              onTap: _onTap,
            ),
          ),
        ],
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
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + pad),
      // Shadow lives OUTSIDE ClipRRect so it is never clipped away.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [
            BoxShadow(
              color: Color(0x332D2B55),
              blurRadius: 28,
              spreadRadius: -4,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              height: 64,
              padding: const EdgeInsets.all(8),
              // Semi-transparent so the blurred content shows through.
              // 0x55 ≈ 33 % white — adjust lower for more glass, higher for more solid.
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x80FFFFFF), Color(0x55FFFFFF)],
                ),
                border: Border.all(
                  color: const Color(0x70FFFFFF),
                  width: 1,
                ),
              ),
            child: LayoutBuilder(builder: (context, c) {
              final tabW = c.maxWidth / _bottomTabs.length;
              return Stack(
                children: [
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
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(18),
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
    final color = active ? AppColors.accentStrong : AppColors.inkSoft;
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
    _Destination('/notifications', 'nav.notifications', Icons.notifications_none_rounded),
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
            border: const Border(top: BorderSide(color: AppColors.hairline)),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: AppColors.ink,
                              ),
                            ),
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded,
                            size: 20, color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.hairline),
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
