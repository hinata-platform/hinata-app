import 'dart:math' show pow;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hinata/features/issues/issue_form.dart' show showIssueForm;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/hinata_repository.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/blocs/theme_cubit.dart';
import '../../core/events/issue_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/content_models.dart';
import '../../core/models/core_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/hex_mark.dart';
import '../../core/widgets/honeycomb_background.dart';
import '../../core/widgets/app_avatar.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show
        GlassAppBar,
        GlassBottomBar,
        GlassBottomBarTab,
        GlassButton,
        GlassContainer,
        GlassQuality,
        LiquidGlassSettings,
        LiquidRoundedSuperellipse;
import '../../core/widgets/glass_panel.dart';
import '../search/global_search_dialog.dart';
import '../search/search_tokens.dart';
import 'page_chrome.dart';

class _Destination {
  const _Destination(this.route, this.labelKey, this.icon);

  final String route;
  final String labelKey;
  final IconData icon;
}

const _primary = [
  _Destination('/dashboard', 'nav.dashboard', LucideIcons.layoutDashboard),
  _Destination('/teams', 'nav.teams', LucideIcons.usersRound),
  _Destination('/projects', 'nav.projects', LucideIcons.folder),
  _Destination('/issues', 'nav.issues', LucideIcons.circleCheckBig),
  _Destination('/board', 'nav.board', LucideIcons.squareKanban),
];

const _secondary = [
  _Destination('/gantt', 'nav.gantt', LucideIcons.chartColumnStacked),
  _Destination('/timesheet', 'nav.timesheet', LucideIcons.table),
  _Destination('/reports', 'nav.reports', LucideIcons.chartLine),
  _Destination('/knowledge', 'nav.knowledge', LucideIcons.bookOpen),
];

const _bottomTabs = [
  _Destination('/dashboard', 'nav.dashboard', LucideIcons.layoutDashboard),
  _Destination('/issues', 'nav.issues', LucideIcons.circleCheckBig),
  _Destination('/board', 'nav.board', LucideIcons.squareKanban),
  _Destination('/more', 'nav.more', LucideIcons.layoutGrid),
];

// ── Floating bottom-nav glass presets ───────────────────────────────────────
// The mobile nav is two *separate* floating glass elements (the tab pill and a
// detached search button, iOS-26 style). Both must refract identically, so they
// share one preset. Values mirror the package's kBottomBarGlassDefaults; the
// glass is tinted translucent-black in dark mode (so it doesn't turn milky) and
// translucent-white in light mode (clean frost).
const kNavGlassDark = LiquidGlassSettings(
  thickness: 30,
  blur: 3,
  chromaticAberration: 0.3,
  lightIntensity: 0.6,
  refractiveIndex: 1.59,
  saturation: 0.7,
  ambientStrength: 1,
  lightAngle: 2.356194490192345, // 0.75π — Apple key light
  glassColor: Color(0x4D0A0A0A),
);
const kNavGlassLight = LiquidGlassSettings(
  thickness: 30,
  blur: 3,
  chromaticAberration: 0.3,
  lightIntensity: 0.6,
  refractiveIndex: 1.59,
  saturation: 0.7,
  ambientStrength: 1,
  lightAngle: 2.356194490192345, // 0.75π — Apple key light
  glassColor: Color(0x3DFFFFFF),
);

bool get isNativeApp =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Responsive scaffold:
/// • phone/compact (<987): Liquid-Glass floating bottom nav
/// • desktop/wide (≥987): persistent dark Navy rail on the left
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // One controller per shell: sub-pages publish their title / back behaviour to
  // it (via [PageChrome]) and the top bars listen so they can render a back
  // button + the real page title instead of the brand mark.
  final _chrome = PageChromeController();

  @override
  void initState() {
    super.initState();
    // App-level ⌘K / Ctrl+K opens the global search palette (§4.5). A hardware
    // key handler is genuinely global and never disturbs widget focus.
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    _chrome.dispose();
    super.dispose();
  }

  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyK) return false;
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final meta =
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    final ctrl =
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    if (!meta && !ctrl) return false;
    // Don't stack a second palette (or open one over another modal).
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    openGlobalSearch(context);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // The shell is persistent (it outlives route changes) and paints
    // theme-aware surfaces by reading AppColors' static getters — which don't
    // trigger rebuilds on their own. Subscribe to the inputs that resolve the
    // active brightness so the whole shell subtree re-runs build (and re-reads
    // AppColors) the moment the theme flips: the chosen ThemeMode, plus the OS
    // brightness for ThemeMode.system.
    context.watch<ThemeCubit>();
    MediaQuery.platformBrightnessOf(context);
    // `widget.location` (from the ShellRoute builder's state) goes STALE after
    // an imperative `push` of a nested route — it keeps reporting the underlying
    // page (e.g. `/board`) while a pushed `/issues/:id` is on screen, so the top
    // bar shows the wrong title/brand mark and never treats it as a sub-page.
    // Read the live location straight from the router instead, rebuilding when
    // it changes.
    final router = GoRouter.of(context);
    return PageChromeScope(
      controller: _chrome,
      child: ListenableBuilder(
        listenable: router.routerDelegate,
        builder: (context, _) {
          final location = router.state.matchedLocation;
          return ResponsiveBuilder(
            builder: (context, size) {
              // The full-screen single-issue view is immersive on compact: its
              // own top bar (back/minimize/delete) + docked composer replace the
              // shell's app bar and floating nav.
              final immersive =
                  size == LayoutSize.compact && _isImmersive(location);
              return size == LayoutSize.compact
                  ? _CompactShell(
                      location: location,
                      immersive: immersive,
                      child: widget.child,
                    )
                  : _WideShell(location: location, child: widget.child);
            },
          );
        },
      ),
    );
  }
}

/// Whether [location] is a route that takes over the whole compact screen — no
/// shell app bar, no floating nav — because it renders its own full-screen
/// chrome. The full-page issue view (`/issues/:id`) is the case today.
bool _isImmersive(String location) => location.startsWith('/issues/');

// ─────────────────────────── Sub-page chrome ──────────────────────────────
// A "sub-page" is any route that isn't a primary nav destination — its top bar
// shows a back button + the page's own title instead of the brand mark + the
// nav-derived breadcrumb. The i18n key here is only a fallback; pages with a
// dynamic title (an issue, an article, a board…) override it through
// [PageChrome].

/// Fallback title key for a sub-page route, or null if [location] is a primary
/// nav destination (dashboard, projects, issues, board, …).
String? _subPageTitleKey(String location) {
  if (location == '/admin') return 'admin.title';
  if (location.startsWith('/admin/users')) return 'admin.users';
  if (location == '/notifications') return 'nav.notifications';
  if (location == '/settings') return 'nav.settings';
  if (location.startsWith('/issues/')) return 'nav.issues';
  if (location.startsWith('/knowledge/')) return 'nav.knowledge';
  if (location.startsWith('/boards/')) return 'nav.board';
  if (location.startsWith('/projects/')) return 'board.boards';
  if (location.startsWith('/teams/')) return 'nav.teams';
  return null;
}

/// Parent route to fall back to when a sub-page can't simply pop (e.g. opened
/// via a deep link with nothing on the navigation stack).
String _subPageBackRoute(String location) {
  if (location.startsWith('/admin/users')) return '/admin';
  if (location == '/admin') return '/settings';
  if (location.startsWith('/issues/')) return '/issues';
  if (location.startsWith('/knowledge/')) return '/knowledge';
  if (location.startsWith('/boards/')) return '/board';
  if (location.startsWith('/projects/')) return '/projects';
  if (location.startsWith('/teams/')) return '/teams';
  return '/dashboard';
}

/// Resolves the back action for a sub-page: a page-supplied [override] wins,
/// otherwise pop the stack, otherwise jump to the parent route.
void _handleBack(
  BuildContext context,
  String location,
  VoidCallback? override,
) {
  if (override != null) {
    override();
  } else if (context.canPop()) {
    context.pop();
  } else {
    context.go(_subPageBackRoute(location));
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
  if (navRoute == '/teams') {
    return location.startsWith('/teams');
  }
  return location.startsWith(navRoute);
}

// ─────────────────────────── Wide Shell (Navy Rail) ───────────────────────

class _WideShell extends StatefulWidget {
  const _WideShell({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  State<_WideShell> createState() => _WideShellState();
}

class _WideShellState extends State<_WideShell> {
  // Desktop-only manual collapse. Medium widths are always collapsed (no room
  // to expand), so the toggle is offered only on the full layout.
  bool _collapsed = false;
  final double maxBodyWidth = 1618;

  @override
  Widget build(BuildContext context) {
    final isMedium = context.layoutSize == LayoutSize.medium;
    final collapsed = isMedium || _collapsed;
    final railWidth = collapsed ? 76.0 : 244.0;
    final subKey = _subPageTitleKey(widget.location);
    final dark = Theme.of(context).brightness == Brightness.dark;

    // The ambient backdrop is painted app-wide; the floating glass topbar and
    // nav rail sit over it, with the content area between/below them. The outer
    // SafeArea consumes the status-bar inset once (so context.topGutter stays 0
    // for pages, as before).
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Stack(
        children: [
          Positioned.fill(child: AmbientBackground(dark: dark)),
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    child: _GlassFloatingTopBar(location: widget.location),
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _NavRail(
                          location: widget.location,
                          collapsed: collapsed,
                          width: railWidth,
                          canToggle: !isMedium,
                          onToggle: () =>
                              setState(() => _collapsed = !_collapsed),
                        ),
                        Expanded(
                          child: _ScrollWheelPassthrough(
                            maxContentWidth: maxBodyWidth,
                            child: Column(
                              children: [
                                // Sub-pages keep a slim back + title bar (the floating
                                // topbar carries no breadcrumb); primary pages render
                                // their own PageHead instead.
                                if (subKey != null)
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: maxBodyWidth,
                                    ),
                                    child: _SubPageBar(
                                      location: widget.location,
                                      titleKey: subKey,
                                    ),
                                  ),
                                Expanded(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: maxBodyWidth,
                                    ),
                                    child: widget.child,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The centered [maxContentWidth] body leaves empty margins on wide screens
/// that no [Scrollable] covers, so a mouse wheel there does nothing. This
/// wraps the full-width area and, when a scroll happens outside the centered
/// content, re-dispatches it as if it occurred at the nearest point inside
/// the content so the page underneath still scrolls.
class _ScrollWheelPassthrough extends StatelessWidget {
  const _ScrollWheelPassthrough({
    required this.maxContentWidth,
    required this.child,
  });

  final double maxContentWidth;
  final Widget child;

  void _onPointerSignal(BuildContext context, PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return;

    final local = box.globalToLocal(event.position);
    final centerX = box.size.width / 2;
    final halfContent = maxContentWidth / 2;
    final offsetFromCenter = local.dx - centerX;
    if (offsetFromCenter.abs() <= halfContent) {
      return; // Already inside the content column; let normal hit-testing handle it.
    }

    final clampedDx =
        centerX + offsetFromCenter.clamp(-halfContent, halfContent);
    final targetGlobal = box.localToGlobal(Offset(clampedDx, local.dy));
    final viewId = View.of(context).viewId;
    final result = HitTestResult();
    RendererBinding.instance.hitTestInView(result, targetGlobal, viewId);
    RendererBinding.instance.dispatchEvent(
      PointerScrollEvent(
        timeStamp: event.timeStamp,
        kind: event.kind,
        device: event.device,
        position: targetGlobal,
        scrollDelta: event.scrollDelta,
        viewId: viewId,
        embedderId: event.embedderId,
      ),
      result,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Listener defaults to HitTestBehavior.deferToChild, so in the empty
      // margins beside the centered content (where no child claims the hit)
      // it would never be hit-tested and onPointerSignal would never fire.
      // opaque makes it always participate in hit-testing over its full area.
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (event) => _onPointerSignal(context, event),
      child: child,
    );
  }
}

/// Opens the create-issue form from global chrome (the nav-rail CTA). On a
/// successful create it broadcasts [IssueEvents.notifyChanged] so whatever
/// issue-bearing screen is currently visible re-fetches — the rail itself has
/// no handle to that page's cubit, so the change travels through the event bus.
/// [showIssueForm] already opens the new issue's detail sheet on success.
Future<void> _createIssue(BuildContext context) async {
  final created = await showIssueForm(context);
  if (created != null) IssueEvents.instance.notifyChanged();
}

class _NavRail extends StatelessWidget {
  const _NavRail({
    required this.location,
    required this.collapsed,
    required this.width,
    this.canToggle = false,
    this.onToggle,
  });

  final String location;
  final bool collapsed;
  final double width;

  /// Whether to show the manual collapse/expand control (desktop only).
  final bool canToggle;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      width: width,
      margin: const EdgeInsets.fromLTRB(16, 0, 0, 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D2B55).withValues(alpha: 0.34),
            blurRadius: 30,
            spreadRadius: -12,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Frosted navy liquid glass: blur the ambient behind the rail and lay
          // a slightly-translucent navy gradient over it so it reads as glass.
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.rail, AppColors.rail2],
                  ),
                ),
              ),
            ),
          ),
          // Faint honeycomb texture pooling at the base of the rail.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 240,
            child: HoneycombBackground(),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Column(
                // Centre every item on the rail's vertical axis when collapsed;
                // left-align them in the expanded view.
                crossAxisAlignment: collapsed
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  // Scrollable nav section so short viewports never overflow the
                  // rail; the footer (toggle + account) below stays pinned.
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: collapsed
                            ? CrossAxisAlignment.center
                            : CrossAxisAlignment.start,
                        children: [
                          // Brand now lives in the floating topbar; the rail opens
                          // straight into its actions.
                          const SizedBox(height: 16),

                          // New issue CTA
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: collapsed ? 12 : 16,
                              vertical: 4,
                            ),
                            child: collapsed
                                ? _RailIconButton(
                                    icon: LucideIcons.plus,
                                    active: false,
                                    amber: true,
                                    tooltip: context.t('issues.new'),
                                    onTap: () => _createIssue(context),
                                  )
                                : DecoratedBox(
                                    // Soft honey glow beneath the CTA (matches the web
                                    // prototype's box-shadow: 0 6px 18px -8px amber/0.7).
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        AppTheme.radiusControl,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.accent.withValues(
                                            alpha: 0.45,
                                          ),
                                          blurRadius: 18,
                                          spreadRadius: -6,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: () => _createIssue(context),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.accent,
                                          foregroundColor: const Color(
                                            0xFF2A2410,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              AppTheme.radiusControl,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                          textStyle: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        icon: const Icon(
                                          LucideIcons.plus,
                                          size: 18,
                                        ),
                                        label: Text(context.t('issues.new')),
                                      ),
                                    ),
                                  ),
                          ),

                          const SizedBox(height: 16),

                          // Primary group
                          if (!collapsed) _RailGroupLabel('WORK'),
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
                        ],
                      ),
                    ),
                  ),

                  // Collapse / expand toggle — desktop only, sits above the user.
                  if (canToggle && onToggle != null)
                    _CollapseToggle(collapsed: collapsed, onToggle: onToggle!),

                  // Settings entry — a standard rail item so it matches the nav
                  // above (icon + label expanded, icon-only collapsed).
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: _RailItem(
                      destination: const _Destination(
                        '/settings',
                        'nav.settings',
                        LucideIcons.settings,
                      ),
                      selected: _isActive(location, '/settings'),
                      collapsed: collapsed,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop rail collapse/expand control. Full-width labelled row when expanded,
/// a centered icon button when collapsed. Sits just above the user button.
class _CollapseToggle extends StatelessWidget {
  const _CollapseToggle({required this.collapsed, required this.onToggle});

  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final icon = collapsed
        ? LucideIcons.panelLeftOpen
        : LucideIcons.panelLeftClose;
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: _RailIconButton(
          icon: icon,
          active: false,
          tooltip: context.t('nav.expandSidebar'),
          onTap: onToggle,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.railFaint),
                const SizedBox(width: 10),
                Text(
                  context.t('nav.collapse'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.railFaint,
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
        horizontal: collapsed ? 8 : 10,
        vertical: 2,
      ),
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
                          color: selected
                              ? AppColors.accent
                              : AppColors.railFaint,
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
          child: Icon(
            icon,
            size: 20,
            color: amber ? const Color(0xFF2A2410) : AppColors.railFaint,
          ),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: child) : child;
  }
}

// ─────────────────────── Desktop / tablet floating topbar ──────────────────
// A full-width floating glass bar: brand mark + wordmark (left), a centred ⌘K
// search pill, and the notification bell + avatar (→ settings) on the right.
// The compact shell keeps its own overlay glass app bar (_GlassTopBar).

class _GlassFloatingTopBar extends StatelessWidget {
  const _GlassFloatingTopBar({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final user = context.select((AuthBloc bloc) => bloc.state.user);
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.hairline),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D2B55).withValues(alpha: dark ? .34 : .10),
            blurRadius: 26,
            spreadRadius: -10,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          HexMark(size: 26, color: dark ? AppColors.accent : AppColors.navy),
          const SizedBox(width: 11),
          Text(
            'hinata',
            style: TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: AppColors.ink,
            ),
          ),
          const Expanded(
            child: Center(
              child: _TopSearchField(compact: false, maxWidth: 520),
            ),
          ),
          const SizedBox(width: 6),
          _NotificationBell(active: location.startsWith('/notifications')),
          const SizedBox(width: 10),
          Tooltip(
            message: context.t('nav.settings'),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context.go('/settings'),
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: AppAvatar(
                    name: user?.displayName ?? '?',
                    imageUrl: user?.avatarUrl,
                    radius: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim contextual bar shown on sub-pages under the floating topbar: a back
/// button + the page's title (published via [PageChrome]).
class _SubPageBar extends StatelessWidget {
  const _SubPageBar({required this.location, required this.titleKey});

  final String location;
  final String titleKey;

  @override
  Widget build(BuildContext context) {
    final chrome = PageChromeScope.of(context);
    final title = chrome.titleFor(location) ?? context.t(titleKey);
    final override = chrome.onBackFor(location);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 24, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _handleBack(context, location, override),
            visualDensity: VisualDensity.compact,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: Icon(
              LucideIcons.arrowLeft,
              size: 20,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill global-search field. Collapses to a single icon button on compact.
class _TopSearchField extends StatelessWidget {
  const _TopSearchField({required this.compact, this.maxWidth = 300});

  final bool compact;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _TopIconButton(
        icon: LucideIcons.search,
        tooltip: context.t('appbar.search'),
        onTap: () => openGlobalSearch(context),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 38),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          side: BorderSide(color: AppColors.hairline),
        ),
        child: InkWell(
          onTap: () => openGlobalSearch(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                Icon(LucideIcons.search, size: 16, color: AppColors.inkFaint),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    context.t('appbar.search'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                  ),
                ),
                const SizedBox(width: 9),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
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
          color: active ? AppColors.hairline : Colors.transparent,
        ),
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
              Icon(
                icon,
                size: 18,
                color: active ? AppColors.ink : AppColors.inkSoft,
              ),
              ?child,
            ],
          ),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: button) : button;
  }
}

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
    _cubit = FetchCubit(() => context.read<HinataRepository>().notifications())
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
      await context.read<HinataRepository>().markNotificationsRead(unread);
    } catch (_) {
      // Non-critical; the reload below reflects server truth.
    }
    await _cubit.load();
  }

  Future<void> _openNotification(AppNotification notification) async {
    _close();
    final repository = context.read<HinataRepository>();
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
    final (icon, tint) = _notifVisual(notification.type);
    final ago = _timeAgo(notification.createdAt);
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

/// Leading icon + tint for a notification type.
(IconData, Color) _notifVisual(String type) => switch (type.toUpperCase()) {
  'MENTION' => (LucideIcons.atSign, AppColors.stReview),
  'ASSIGN' ||
  'ASSIGNED' ||
  'ASSIGNMENT' => (LucideIcons.userCheck, AppColors.stTodo),
  'COMMENT' => (LucideIcons.messageSquare, AppColors.stProgress),
  'REVIEW' ||
  'REVIEW_REQUEST' => (LucideIcons.messageSquareText, AppColors.stReview),
  'DUE' || 'DEADLINE' => (LucideIcons.calendarDays, AppColors.priHigh),
  _ => (LucideIcons.bell, AppColors.inkSoft),
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

// ─────────────────────────── Compact Shell (Liquid-Glass) ─────────────────

/// Content height of the compact glass app bar (excludes the status-bar inset).
const double _kCompactBarHeight = 52;

class _CompactShell extends StatefulWidget {
  const _CompactShell({
    required this.location,
    required this.child,
    this.immersive = false,
  });

  final String location;
  final Widget child;

  /// A full-screen route that supplies its own chrome: hide the shell's glass
  /// app bar + floating nav and drop their footprints from the content gutters.
  final bool immersive;

  @override
  State<_CompactShell> createState() => _CompactShellState();
}

class _CompactShellState extends State<_CompactShell> {
  int get _selectedIndex {
    for (var i = 0; i < _bottomTabs.length - 1; i++) {
      if (_isActive(widget.location, _bottomTabs[i].route)) return i;
    }
    // Everything not in first 3 tabs → "More" tab (index 3)
    final inPrimary = _primary.any((d) => _isActive(widget.location, d.route));
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
      barrierColor: Colors.black.withValues(alpha: 0.32),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      // Content fills the whole screen and scrolls *behind* the translucent
      // glass app bar and the floating glass nav. We inject both bars'
      // footprints into MediaQuery.padding so screens clear them via
      // context.topGutter / context.bottomGutter while still blurring through.
      body: Stack(
        children: [
          // App-wide ambient backdrop (same as the wide shell) so every screen
          // — including the mobile dashboard — sits on the v2 canvas.
          Positioned.fill(child: AmbientBackground(dark: dark)),
          Positioned.fill(
            child: Builder(
              builder: (context) {
                final mq = MediaQuery.of(context);
                // Glass app bar: status-bar inset + bar content height. Immersive
                // routes hide the bar, so only the status-bar inset remains.
                final topFootprint = widget.immersive
                    ? mq.viewPadding.top
                    : _kCompactBarHeight + mq.viewPadding.top;
                // Floating nav: GlassBottomBar barHeight(64) + verticalPadding
                // (8 top + 8 bottom) + device safe-area. Immersive routes hide
                // the nav, so only the device safe-area remains.
                final navFootprint = widget.immersive
                    ? mq.viewPadding.bottom
                    : 80 + mq.viewPadding.bottom;
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
              },
            ),
          ),
          // Black gradient scrim rising from the bottom up to the nav so content
          // dissolves beneath the floating glass pill. (Hidden when immersive.)
          if (!widget.immersive)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(child: _BottomNavScrim()),
            ),
          // Floating liquid-glass nav (package GlassBottomBar). Kept in the
          // Stack (not Scaffold.bottomNavigationBar) so it floats over the
          // content it refracts; SafeArea lifts it above the home indicator.
          if (!widget.immersive)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                bottom: false,
                // iOS-26 layout: the tab pill and a detached global-search button
                // are two separate floating glass elements with a gap between
                // them. The padding that used to live inside GlassBottomBar is
                // hoisted to this Row so both elements share the same inset and
                // the footprint injected above (navFootprint) stays unchanged.
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GlassBottomBar(
                          horizontalPadding: 0,
                          verticalPadding: 0,
                          selectedIndex: _selectedIndex,
                          onTabSelected: _onTap,
                          // Black-tinted glass in dark mode (so it doesn't turn
                          // milky), clean white frost in light — see _kNavGlass*.
                          settings: dark ? kNavGlassDark : kNavGlassLight,
                          // Honey-amber indicator (translucent so the glass shows
                          // through).
                          indicatorColor: AppColors.accent.withValues(
                            alpha: dark ? 0.30 : 0.22,
                          ),
                          selectedIconColor: dark
                              ? AppColors.accent
                              : AppColors.accentStrong,
                          unselectedIconColor: dark
                              ? AppColors.inkDark
                              : AppColors.ink,
                          tabs: [
                            for (final d in _bottomTabs)
                              GlassBottomBarTab(
                                icon: Icon(d.icon),
                                label: context.t(d.labelKey),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _GlassNavSearchButton(dark: dark),
                    ],
                  ),
                ),
              ),
            ),
          // Transparent glass app bar with a top-down scrim — overlays content.
          // (Hidden when immersive; the page draws its own top bar.)
          if (!widget.immersive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _GlassTopBar(location: widget.location, dark: dark),
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
  const _GlassTopBar({required this.location, required this.dark});

  final String location;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.viewPaddingOf(context).top;

    // Sub-page → back button + the page's own title; primary nav page → brand
    // mark + the nav-derived title.
    final subKey = _subPageTitleKey(location);
    final String titleText;
    VoidCallback? onBack;
    if (subKey != null) {
      final chrome = PageChromeScope.of(context);
      titleText = chrome.titleFor(location) ?? context.t(subKey);
      final override = chrome.onBackFor(location);
      onBack = () => _handleBack(context, location, override);
    } else {
      final all = [..._primary, ..._secondary];
      final current = all.firstWhere(
        (d) => _isActive(location, d.route),
        orElse: () =>
            const _Destination('/', 'nav.dashboard', LucideIcons.house),
      );
      titleText = context.t(current.labelKey);
    }
    // Black scrim, strongest under the status bar, fading to nothing at the
    // bar's lower edge. Subtle in light (keeps dark status-bar icons legible),
    // stronger in dark.
    //
    // The bar reads content through a *progressive* backdrop blur — heavy at the
    // status-bar edge, easing to perfectly sharp at the bottom (the iOS-26 look,
    // cf. Instagram's profile header). The pill/buttons on top must NOT add
    // their own BackdropFilter: a filter sampling an already-blurred backdrop is
    // what produced the pixelated / "layered" blocks. Instead they are
    // translucent frosted surfaces that simply let this one blur show through.
    final scrimTop = dark ? 0.5 : 0.16;
    final height = topInset + _kCompactBarHeight;

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          // Smooth progressive blur: strongest at the top, fading to sharp at the
          // bottom edge so the bar dissolves into the content beneath it.
          Positioned.fill(child: _ProgressiveBlur(maxSigma: dark ? 30 : 26)),
          // Darkening scrim (fades to transparent at the bottom edge so the bar
          // dissolves into the content instead of ending on a hard cut-off).
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
          // The bar itself is the package's GlassAppBar — a transparent layout
          // container (leading · centered title · actions) that handles its own
          // status-bar SafeArea. Its children are translucent frosted surfaces
          // that let the progressive blur above show through (no nested
          // BackdropFilter): a back affordance and the action capsule (which
          // carries the notification-bell popover).
          GlassAppBar(
            backgroundColor: Colors.transparent,
            centerTitle: true,
            preferredSize: const Size.fromHeight(_kCompactBarHeight),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            leading: onBack != null
                ? Tooltip(
                    message: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    child: !isNativeApp
                        ? _FrostedCircleButton(
                            icon: LucideIcons.arrowLeft,
                            onTap: onBack,
                          )
                        : GlassButton(
                            icon: const Icon(LucideIcons.arrowLeft),
                            onTap: onBack,
                            width: 42,
                            height: 42,
                            iconSize: 18,
                            useOwnLayer: true,
                            settings: dark ? kNavGlassDark : kNavGlassLight,
                            iconColor: dark ? AppColors.inkDark : AppColors.ink,
                            glowColor: AppColors.accent,

                            // Keep the tactile press-scale but damp the liquid drag-follow so the
                            // isolated button doesn't over-stretch on tap.
                            stretch: 0.15,
                          ),
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: HexMark(size: 24, color: AppColors.accent),
                  ),
            title: Text(
              titleText,
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
            actions: [_GlassTopActions(location: location, dark: dark)],
          ),
        ],
      ),
    );
  }
}

/// Persistent top-bar actions — notifications and settings, each its own
/// separate round iOS-26 liquid-glass button (no more grouped capsule; global
/// search moved to the floating bottom nav). Each button is a [_FrostedSurface]
/// circle that relies on the bar's single [_ProgressiveBlur] showing through its
/// translucent fill (no nested [BackdropFilter], which would re-sample the
/// already-blurred backdrop and pixelate).
class _GlassTopActions extends StatelessWidget {
  const _GlassTopActions({required this.location, required this.dark});

  final String location;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NotificationBell(
          active: location.startsWith('/notifications'),
          frosted: true,
          dark: dark,
        ),
        const SizedBox(width: 8),
        !isNativeApp
            ? _FrostedCircleButton(
                icon: LucideIcons.settings,
                tooltip: context.t('nav.settings'),
                active: location.startsWith('/settings'),
                onTap: () => context.go('/settings'),
              )
            : Tooltip(
                message: context.t('nav.settings'),
                child: GlassButton(
                  icon: const Icon(LucideIcons.settings2),
                  onTap: () => context.go('/settings'),
                  width: 42,
                  height: 42,
                  iconSize: 18,
                  useOwnLayer: true,
                  settings: dark ? kNavGlassDark : kNavGlassLight,
                  iconColor: dark ? AppColors.inkDark : AppColors.ink,
                  glowColor: AppColors.accent,

                  // Keep the tactile press-scale but damp the liquid drag-follow so the
                  // isolated button doesn't over-stretch on tap.
                  stretch: 0.15,
                ),
              ),
      ],
    );
  }
}

/// A translucent frosted surface — the visual "glass" used by the top-bar
/// pill/buttons. It carries NO blur of its own; it relies on the bar's single
/// progressive [BackdropFilter] showing through the semi-transparent fill, then
/// adds the hairline edge + top specular highlight that read as a glass rim.
/// Keeping the blur in ONE place is what keeps the surface crisp (no nested
/// backdrop sampling → no pixelation).
class _FrostedSurface extends StatelessWidget {
  const _FrostedSurface({
    required this.child,
    required this.borderRadius,
    required this.dark,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        // Light frost lift in dark, a brighter wash in light — translucent so
        // the progressive blur behind stays visible through the surface.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0x33FFFFFF), Color(0x1FFFFFFF)]
              : const [Color(0x6BFFFFFF), Color(0x4DFFFFFF)],
        ),
        border: Border.all(
          color: dark ? const Color(0x40FFFFFF) : const Color(0x66FFFFFF),
          width: 0.6,
        ),
      ),
      child: child,
    );
  }
}

/// 40×40 frosted circular button — the iOS-26 standalone glass control used for
/// the top-bar back affordance and each trailing action (notifications ·
/// settings). Same no-own-blur frosted treatment as [_FrostedSurface]. When
/// [active] it fills with a translucent honey-amber tint and the glyph adopts
/// the accent colour; [overlay] paints an extra badge (e.g. the unread dot)
/// above the icon.
class _FrostedCircleButton extends StatelessWidget {
  const _FrostedCircleButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
    this.overlay,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;

  /// Optional badge (e.g. the unread dot) painted above the icon.
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final button = _FrostedSurface(
      borderRadius: BorderRadius.circular(20),
      dark: dark,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (active)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent.withValues(
                          alpha: dark ? 0.30 : 0.20,
                        ),
                      ),
                    ),
                  ),
                Icon(
                  icon,
                  size: 18,
                  color: active
                      ? (dark ? AppColors.accent : AppColors.accentStrong)
                      : AppColors.ink,
                ),
                ?overlay,
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: button) : button;
  }
}

/// Smooth vertical *gradient* backdrop blur: strongest at the top, easing to
/// perfectly sharp at the bottom, so the frosted bar dissolves into the content
/// beneath it (no hard cut-off edge) — the iOS-26 top-of-screen blur.
///
/// ## Why this is smooth AND cheap
///
/// A true gradient blur isn't expressible with a single primitive: a custom
/// fragment shader can't sample the backdrop (no Flutter API), and wrapping a
/// [BackdropFilter] in a [ShaderMask] breaks it (the filter samples an empty
/// backdrop inside the mask's save-layer). So we approximate the gradient with
/// many thin horizontal slices of increasing sigma.
///
/// The trick that makes it premium-quality:
///
/// 1. **No banding** — enough slices ([_slices]) that the sigma step between
///    neighbours falls below the perceptible threshold, so the discrete strips
///    read as one continuous gradient.
/// 2. **No pixelation** — every slice is a [BackdropFilter.grouped] sharing one
///    [BackdropGroup] key, so they all blur the *same original* backdrop
///    snapshot. They never sample each other, so there's no compounded /
///    down-sampled "blur of a blur" (which is what produced the earlier blocky
///    artefacts).
/// 3. **Performant** — the shared [BackdropGroup] lets the engine capture the
///    backdrop a single time for the whole stack instead of once per slice.
class _ProgressiveBlur extends StatelessWidget {
  const _ProgressiveBlur({required this.maxSigma});

  final double maxSigma;

  /// Slice count. High enough that the per-step sigma delta is sub-perceptual
  /// (~1px), so no visible bands. Cheap thanks to the shared [BackdropGroup].
  static const int _slices = 28;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropGroup(
        child: Column(
          children: [
            for (var i = 0; i < _slices; i++)
              Expanded(
                child: _BlurSlice(
                  // t: 0 at the top → 1 at the bottom. A gentle (^1.2) falloff
                  // keeps the blur strong across the status bar AND the
                  // title/pill row — like the reference — then eases to sharp
                  // near the bottom edge, so the pill still reads as glass.
                  sigma:
                      maxSigma * pow(1 - (i / (_slices - 1)), 1.2).toDouble(),
                ),
              ),
          ],
        ),
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
      // .grouped → shares the BackdropGroup's single backdrop capture and never
      // samples sibling slices (no compounded blur → no pixelation).
      child: BackdropFilter.grouped(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Detached liquid-glass button carrying the global search, floating to the
/// right of the tab pill (iOS-26 separated-controls layout). It is its own
/// glass layer ([GlassButton.useOwnLayer]) so it refracts the content behind it
/// independently of the tab pill, matched to the same [kNavGlassDark] /
/// [kNavGlassLight] preset so the two elements read as one material. Sized to
/// the bar's 64px height so both align.
class _GlassNavSearchButton extends StatelessWidget {
  const _GlassNavSearchButton({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.t('appbar.search'),
      child: GlassButton(
        icon: const Icon(LucideIcons.search),
        onTap: () => openGlobalSearch(context),
        width: 64,
        height: 64,
        iconSize: 24,
        useOwnLayer: true,
        settings: dark ? kNavGlassDark : kNavGlassLight,
        iconColor: dark ? AppColors.inkDark : AppColors.ink,
        // Keep the tactile press-scale but damp the liquid drag-follow so the
        // isolated button doesn't over-stretch on tap.
        stretch: 0.15,
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
    _Destination('/projects', 'nav.projects', LucideIcons.folder),
    _Destination('/teams', 'nav.teams', LucideIcons.usersRound),
    _Destination('/gantt', 'nav.gantt', LucideIcons.chartColumnStacked),
    _Destination('/timesheet', 'nav.timesheet', LucideIcons.table),
    _Destination('/reports', 'nav.reports', LucideIcons.chartLine),
    _Destination('/knowledge', 'nav.knowledge', LucideIcons.bookOpen),
    // Notifications intentionally omitted — they live in the always-visible
    // top bar bell, so they need no entry in the overflow sheet.
  ];

  static const double _radius = 28;

  @override
  Widget build(BuildContext context) {
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;

    final subtitle = user?.title?.isNotEmpty == true
        ? user!.title!
        : user?.roles.isNotEmpty == true
        ? user!.roles.first.toLowerCase()
        : user?.email ?? '';

    final panel = GlassPanelShadow(
      radius: BorderRadius.circular(_radius),
      shadows: tokens.panelShadow,
      child: GlassContainer(
        useOwnLayer: true,
        quality: GlassQuality.premium,
        clipBehavior: Clip.antiAlias,
        shape: const LiquidRoundedSuperellipse(borderRadius: _radius),
        settings: liquidGlassPanelSettings(
          glassFill: tokens.glassFill,
          dark: dark,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.hairline,
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
                              color: tokens.ink,
                            ),
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: tokens.inkSoft,
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
                        color: tokens.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: tokens.hairline,
              ),
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
                  tokens: tokens,
                  destination: _items[i],
                  active: location.startsWith(_items[i].route),
                  onTap: () => onNavigate(_items[i].route),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: panel,
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.tokens,
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final SearchTokens tokens;
  final _Destination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = active ? AppColors.accentStrong : tokens.inkSoft;
    final badgeBg = active ? AppColors.accentSoft : tokens.field;
    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: active ? AppColors.accentSoft.withValues(alpha: 0.35) : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(
              color: active ? AppColors.accentLine : tokens.hairline,
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
