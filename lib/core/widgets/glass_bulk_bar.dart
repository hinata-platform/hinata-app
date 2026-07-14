import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/search/search_tokens.dart';
import '../theme/app_colors.dart';
import 'glass_panel.dart';

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
    required this.actions,
    required this.onClear,
    this.clearTooltip,
  });

  /// The leading "N selected" label.
  final String countLabel;

  /// The action strip — typically [GlassBulkAction] buttons, but any inline
  /// control (e.g. a dropdown) works.
  final List<Widget> actions;

  final VoidCallback onClear;
  final String? clearTooltip;

  static const double _radius = 26;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SearchTokens.of(dark ? Brightness.dark : Brightness.light);
    final radius = BorderRadius.circular(_radius);

    final close = IconButton(
      onPressed: onClear,
      icon: Icon(LucideIcons.x, size: 18, color: tokens.inkSoft),
      visualDensity: VisualDensity.compact,
    );

    final content = Stack(
      children: [
        Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    countLabel,
                    style: TextStyle(
                      color: tokens.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 22,
                  color: tokens.hairline,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                ),
                // The action strip scrolls when the bar can't fit — instead of
                // overflowing the screen edge or clipping labels.
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(mainAxisSize: MainAxisSize.min, children: actions),
                  ),
                ),
                const SizedBox(width: 2),
                clearTooltip != null
                    ? Tooltip(message: clearTooltip!, child: close)
                    : close,
              ],
            ),
          ),
        ),
        // Specular rim on top of the lens.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _BulkBarRimPainter(
                radius: _radius,
                edge: tokens.edge,
                edgeSoft: tokens.edgeSoft,
              ),
            ),
          ),
        ),
      ],
    );

    return GlassPanelShadow(
      radius: radius,
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
        child: content,
      ),
    );
  }
}

/// One icon+label action inside a [GlassBulkBar].
class GlassBulkAction extends StatelessWidget {
  const GlassBulkAction({
    super.key,
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SearchTokens.of(dark ? Brightness.dark : Brightness.light);
    final color = danger
        ? (dark ? const Color(0xFFFF8A80) : AppColors.danger)
        : tokens.ink;
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        overlayColor: tokens.rowHover,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
      ),
      icon: Icon(icon, size: 15, color: color),
      label: Text(label),
    );
  }
}

class _BulkBarRimPainter extends CustomPainter {
  _BulkBarRimPainter({
    required this.radius,
    required this.edge,
    required this.edgeSoft,
  });

  final double radius;
  final Color edge;
  final Color edgeSoft;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        [edge, edgeSoft, Colors.transparent, edgeSoft],
        const [0.0, 0.28, 0.52, 1.0],
      );
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_BulkBarRimPainter old) =>
      old.radius != radius || old.edge != edge || old.edgeSoft != edgeSoft;
}
