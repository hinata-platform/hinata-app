import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show LiquidGlassSettings;

/// Shared liquid-glass plumbing for the app's glass panels / overlays.
///
/// The iOS-26 liquid-glass effect comes from **refraction + blur + specular**,
/// NOT from an opaque tint fill — the package's own default `glassColor` is
/// fully transparent. Passing a heavy fill (e.g. a 0.62-alpha tint) buries the
/// lens and the surface reads as a flat card. So always feed a *light*
/// [glassFill] and pair this with `quality: GlassQuality.premium` on the
/// `GlassContainer` (texture capture + chromatic aberration on Impeller; it
/// falls back gracefully on Skia/Web).

/// The app's standard liquid-glass settings for panels/overlays.
LiquidGlassSettings liquidGlassPanelSettings({
  required Color glassFill,
  required bool dark,
  double blur = 6,
  double thickness = 22,
}) {
  return LiquidGlassSettings(
    glassColor: glassFill,
    blur: blur,
    thickness: thickness,
    refractiveIndex: 1.2,
    chromaticAberration: 0.04,
    saturation: 1.6,
    lightIntensity: 0.7,
    glowIntensity: 0.6,
    // Dark glass gets a slight frost lift; light relies on the tint.
    whitenStrength: dark ? 0.04 : 0.04,
    whitenGated: false,
    shadowElevation: 0, // the panel paints its own clipped drop shadow
  );
}

/// Drop shadow for a translucent glass panel, painted ONLY *outside* the
/// panel's rounded rect.
///
/// A glass surface backdrop-samples (and is translucent over) whatever sits
/// behind it, so a plain `BoxDecoration` `boxShadow` would bleed its dark blur
/// up through the glass and tint the surface. Clipping the shadow to the region
/// outside the panel mirrors CSS outer `box-shadow`, which is never painted
/// under the element's own box.
class GlassPanelShadow extends StatelessWidget {
  const GlassPanelShadow({
    super.key,
    required this.radius,
    required this.shadows,
    required this.child,
  });

  final BorderRadius radius;
  final List<BoxShadow> shadows;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GlassPanelShadowPainter(radius: radius, shadows: shadows),
      child: child,
    );
  }
}

class _GlassPanelShadowPainter extends CustomPainter {
  _GlassPanelShadowPainter({required this.radius, required this.shadows});
  final BorderRadius radius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = radius.toRRect(Offset.zero & size);
    // even-odd: everything in the big rect EXCEPT the panel area → "outside".
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(
          Rect.fromLTRB(-2000, -2000, size.width + 2000, size.height + 2000))
      ..addRRect(rrect);
    canvas.save();
    canvas.clipPath(outside);
    for (final s in shadows) {
      canvas.drawRRect(
        rrect.shift(s.offset).inflate(s.spreadRadius),
        s.toPaint(),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassPanelShadowPainter old) =>
      old.radius != radius || old.shadows != shadows;
}
