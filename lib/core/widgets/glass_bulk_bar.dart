import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/search/search_tokens.dart';
import '../i18n/i18n.dart';
import '../responsive/responsive.dart';
import '../theme/app_colors.dart';
import 'glass_panel.dart';
import '../theme/app_type.dart';

/// Docks a [GlassBulkBar] just above whatever sits at the bottom of the page:
/// the floating nav on a phone, the window edge (plus its safe area) elsewhere.
///
/// Place it directly in the page's `Stack`. It reads the nav's top edge from
/// [ShellInsets.bottom] rather than from `context.bottomGutter`: the gutter is
/// what *scrolling content* must clear and already adds the device's bottom
/// inset once more on top of the pill (see `AppShellCompact`). Measured from the
/// gutter, the bar floated a whole home-indicator height above the nav on an
/// iPhone. From the pill's edge, the gap is [gap] everywhere.
class GlassBulkBarDock extends StatelessWidget {
  const GlassBulkBarDock({super.key, required this.child, this.gap = 12});

  final Widget child;

  /// Space between the bar and the nav (or the bottom inset without one).
  final double gap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: ShellInsets.bottom,
      child: Center(child: child),
      builder: (context, navEdge, centered) => Positioned(
        left: context.pageGutter,
        right: context.pageGutter,
        // No floating nav on this route (wide shell, immersive page): the
        // gutter is just the safe area there, which is what the bar must clear.
        bottom: (navEdge > 0 ? navEdge : context.bottomGutter) + gap,
        child: centered!,
      ),
    );
  }
}

/// Floating liquid-glass bulk-selection bar ("N selected · actions · ✕").
///
/// The same iOS-26 lens material as the popup menus / board filter
/// (refraction + blur + specular rim, see [glass_panel.dart]), themed via
/// [SearchTokens] so it stays legible in both light and dark mode.
///
/// Responsive by construction: the bar hugs its content when it fits and
/// scrolls its action strip horizontally when it doesn't, so on narrow
/// phones no action can be pushed off-screen.
class GlassBulkBar extends StatelessWidget {
  const GlassBulkBar({
    super.key,
    required this.countLabel,
    this.countSemanticsLabel,
    required this.actions,
    required this.onClear,
    this.clearTooltip,
    this.leading,
    this.labelledMinWidth = 760,
  });

  /// The leading "N selected" label.
  final String countLabel;

  /// What a screen reader says for the count, when [countLabel] is shortened
  /// for a narrow bar (just the number on a phone).
  final String? countSemanticsLabel;

  /// The action strip — typically [GlassBulkAction] buttons, but any inline
  /// control (e.g. a dropdown) works.
  final List<Widget> actions;

  final VoidCallback onClear;
  final String? clearTooltip;

  /// Sits right after the count, before the divider: what acts on the selection
  /// itself rather than on the issues, such as "Select all".
  final Widget? leading;

  /// Narrowest bar that still shows its actions with labels. The default fits
  /// the count and four labelled actions in German at the default text size;
  /// a bar with more actions passes more.
  final double labelledMinWidth;

  static const double _radius = 26;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SearchTokens.of(dark ? Brightness.dark : Brightness.light);

    // Named even when the caller passes no tooltip: an icon alone is nothing
    // to a screen reader.
    final close = IconButton(
      onPressed: onClear,
      tooltip: clearTooltip ?? context.t('common.close'),
      icon: Icon(LucideIcons.x, size: 18, color: tokens.inkSoft),
      visualDensity: VisualDensity.compact,
    );

    return GlassFloatingSurface(
      radius: _radius,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: LayoutBuilder(
          builder: (context, constraints) => _BulkBarScope(
            iconOnly:
                constraints.maxWidth < labelledMinWidth || context.isCompact,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // At most two fifths of the bar, so a long translation or a
                // large text size shortens the count instead of pushing the
                // actions and the close button off the bar. A cap rather than a
                // flex share: two flexible halves gave the strip only half the
                // bar, and it scrolled its last action out of sight even where
                // the window had room for all of them.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth.isFinite
                        ? constraints.maxWidth * 0.4
                        : double.infinity,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      countLabel,
                      semanticsLabel: countSemanticsLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: AppType.label,
                      ),
                    ),
                  ),
                ),
                ?leading,
                const GlassBulkDivider(),
                // The action strip scrolls when the bar can't fit — instead of
                // overflowing the screen edge or clipping labels.
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                close,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tells the [GlassBulkAction]s of one bar whether there is room for labels.
class _BulkBarScope extends InheritedWidget {
  const _BulkBarScope({required this.iconOnly, required super.child});

  final bool iconOnly;

  /// Icon only inside a narrow bar, and on a phone outside any bar.
  static bool iconOnlyIn(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BulkBarScope>()?.iconOnly ??
      context.isCompact;

  @override
  bool updateShouldNotify(_BulkBarScope oldWidget) =>
      iconOnly != oldWidget.iconOnly;
}

/// A hairline between groups of actions in a [GlassBulkBar]: what changes the
/// issues, what removes them, what is left in the overflow.
class GlassBulkDivider extends StatelessWidget {
  const GlassBulkDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SearchTokens.of(dark ? Brightness.dark : Brightness.light);
    return ExcludeSemantics(
      child: Container(
        width: 1,
        height: 22,
        color: tokens.hairline,
        margin: const EdgeInsets.symmetric(horizontal: 6),
      ),
    );
  }
}

/// One icon+label action inside a [GlassBulkBar].
///
/// In a narrow bar it drops the label and keeps the icon, the label moving into
/// the tooltip and the semantics: four labelled actions next to the count fit
/// neither a phone nor a tablet beside the rail, and a strip that scrolls hides
/// the last ones from view. The bar decides by its own width, not the window's.
class GlassBulkAction extends StatelessWidget {
  const GlassBulkAction({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.onTapAt,
    this.danger = false,
    this.menu = false,
    this.iconOnly = false,
  });

  final IconData icon;
  final String label;

  /// Null disables the action, e.g. while nothing is selected yet, unless
  /// [onTapAt] is given instead.
  final VoidCallback? onTap;

  /// Like [onTap], with the action's own rectangle in window coordinates, for
  /// a popover to grow out of the button that opened it.
  final ValueChanged<Rect>? onTapAt;

  final bool danger;

  /// Opens a menu rather than acting at once; a labelled action shows a chevron.
  final bool menu;

  /// Always just the icon, with the label as its tooltip: the overflow button.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SearchTokens.of(dark ? Brightness.dark : Brightness.light);
    final tapAt = onTapAt;
    final VoidCallback? handler = tapAt != null
        ? () {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null || !box.hasSize) return;
            tapAt(box.localToGlobal(Offset.zero) & box.size);
          }
        : onTap;
    final enabled = handler != null;
    final base = danger
        ? (dark ? const Color(0xFFFF8A80) : AppColors.danger)
        : tokens.ink;
    final color = enabled ? base : tokens.inkSoft;
    if (iconOnly || _BulkBarScope.iconOnlyIn(context)) {
      return IconButton(
        onPressed: handler,
        tooltip: label,
        style: IconButton.styleFrom(overlayColor: tokens.rowHover),
        icon: Icon(icon, size: 20, color: color),
      );
    }
    return TextButton(
      onPressed: handler,
      style: TextButton.styleFrom(
        foregroundColor: color,
        overlayColor: tokens.rowHover,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: AppType.label,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Text(label),
          if (menu) ...[
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 14, color: color),
          ],
        ],
      ),
    );
  }
}
