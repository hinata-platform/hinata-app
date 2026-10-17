import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../models/time_usage_models.dart';

/// The two materials every budget shape is made of (HIN-151, "Honigstand"):
/// a glass vessel and the honey inside it.
///
/// The vessel is frosted, never refractive. Every budget shape sits inside a
/// card, sheet or bar that is already glass, and glass inside glass doubles
/// the refraction and costs a second backdrop pass for nothing (the package's
/// own rule two). Frost, a white rim, a specular line along the top and a
/// faint inner shadow read as glass over the app's ambient background without
/// sampling it.
abstract final class HoneyGlass {
  /// Liquid from the top of its surface to the bottom of the vessel: light
  /// honey under the warning share, deep amber from it, ember from the limit.
  static List<Color> liquid(BudgetLevel level) => switch (level) {
    BudgetLevel.within => const [
      Color(0xFFF8D67E),
      Color(0xFFEDB64B),
      Color(0xFFD69A28),
    ],
    BudgetLevel.near => const [
      Color(0xFFF2B952),
      Color(0xFFDC9524),
      Color(0xFFB9760E),
    ],
    BudgetLevel.over => const [
      Color(0xFFF7A27A),
      Color(0xFFE76D55),
      Color(0xFFC5463A),
    ],
  };

  /// A liquid of any colour, for a distribution drawn in the same glass
  /// (HIN-157): a lighter surface, the colour itself, a deeper foot.
  static List<Color> tinted(Color base) {
    final hsl = HSLColor.fromColor(base);
    return [
      hsl.withLightness((hsl.lightness + 0.16).clamp(0, 0.92)).toColor(),
      base,
      hsl.withLightness((hsl.lightness - 0.12).clamp(0.08, 1)).toColor(),
    ];
  }

  /// Ink on the liquid. Navy on every honey and on the light half of ember,
  /// which is where a figure sits in a vessel (measured: 6.9:1 on the honey
  /// middle stop, 4.6:1 on the ember middle stop).
  static const onLiquid = Color(0xFF23223F);

  static Color frost(bool dark) => dark
      ? const Color(0x14FFFFFF) // white 8 %
      : const Color(0x73FFFFFF); // white 45 %

  static Color rim(bool dark) =>
      dark ? const Color(0x2EFFFFFF) : const Color(0xE6FFFFFF);

  /// The hairline outside the rim, so a light vessel still has an edge on a
  /// light card.
  static Color outline(bool dark) =>
      dark ? const Color(0x52000000) : const Color(0x1F2D2B55);

  static Color innerShade(bool dark) =>
      dark ? const Color(0x59000000) : const Color(0x1A2D2B55);

  /// Paints an empty vessel of [shape] within [bounds].
  static void paintVessel(Canvas canvas, Path shape, Rect bounds, bool dark) {
    canvas.drawPath(shape, Paint()..color = frost(dark));
    // A shade that falls from the top edge inwards: the vessel's wall seen
    // from the front.
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(
          bounds.topCenter,
          Offset(bounds.center.dx, bounds.top + bounds.height * 0.55),
          [innerShade(dark), innerShade(dark).withValues(alpha: 0)],
        ),
    );
    canvas.restore();
  }

  /// Paints the vessel's edge: an outline, a rim, and a specular highlight
  /// along its upper part. Called after the liquid so the rim sits on top.
  static void paintRim(Canvas canvas, Path shape, Rect bounds, bool dark) {
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = outline(dark),
    );
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = rim(dark),
    );
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        bounds.left,
        bounds.top,
        bounds.right,
        bounds.top + bounds.height * 0.42,
      ),
    );
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = ui.Gradient.linear(
          bounds.topLeft,
          bounds.topRight,
          [
            const Color(0x00FFFFFF),
            _white.withValues(alpha: dark ? 0.55 : 0.95),
            const Color(0x00FFFFFF),
          ],
          const [0.08, 0.35, 0.92],
        ),
    );
    canvas.restore();
  }

  /// Paints honey inside [shape], filling [liquidRect] (which may be wider or
  /// lower than the shape; the shape clips it). [surface] decides how the top
  /// edge of the liquid looks: a vertical meniscus for a tube filling
  /// sideways, a gentle wave for a cell filling upwards.
  static void paintHoney(
    Canvas canvas,
    Path shape,
    Rect liquidRect,
    BudgetLevel level, {
    HoneySurface surface = HoneySurface.side,
    double alpha = 1,
    bool bubbles = true,
    List<Color>? colorsOverride,
  }) {
    if (liquidRect.isEmpty) return;
    final colors = [
      for (final c in colorsOverride ?? liquid(level))
        c.withValues(alpha: c.a * alpha),
    ];
    canvas.save();
    canvas.clipPath(shape);
    final body = surface == HoneySurface.wave
        ? _wavePath(liquidRect)
        : _sidePath(liquidRect);
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          liquidRect.topCenter,
          liquidRect.bottomCenter,
          colors,
          const [0, 0.55, 1],
        ),
    );
    // Light caught by the liquid's surface.
    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = _white.withValues(alpha: 0.7 * alpha);
    if (surface == HoneySurface.wave) {
      canvas.drawPath(_waveLine(liquidRect), highlight);
    } else {
      final x = liquidRect.right - 1.2;
      canvas.drawLine(
        Offset(x, liquidRect.top + liquidRect.height * 0.22),
        Offset(x, liquidRect.bottom - liquidRect.height * 0.22),
        highlight,
      );
      // The glossy band a tube of honey shows along its upper third.
      canvas.drawRect(
        Rect.fromLTWH(
          liquidRect.left,
          liquidRect.top + liquidRect.height * 0.16,
          liquidRect.width,
          liquidRect.height * 0.14,
        ),
        Paint()..color = _white.withValues(alpha: 0.26 * alpha),
      );
    }
    if (bubbles && alpha == 1) _paintBubbles(canvas, liquidRect);
    canvas.restore();
  }

  /// A translucent hatched band for time that is about to be recorded: the
  /// entry in the form, before it is saved.
  static void paintPending(
    Canvas canvas,
    Path shape,
    Rect rect,
    BudgetLevel level, {
    bool dark = false,
  }) {
    if (rect.isEmpty) return;
    // Stronger on a dark vessel, where translucent honey sinks into the
    // background.
    paintHoney(
      canvas,
      shape,
      rect,
      level,
      alpha: dark ? 0.6 : 0.42,
      bubbles: false,
    );
    canvas.save();
    canvas.clipPath(shape);
    canvas.clipRect(rect);
    final hatch = Paint()
      ..color = (dark ? liquid(level)[0] : liquid(level)[2]).withValues(
        alpha: dark ? 0.85 : 0.55,
      )
      ..strokeWidth = 1.5;
    for (var x = rect.left - rect.height; x < rect.right; x += 5) {
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset(x + rect.height, rect.top),
        hatch,
      );
    }
    canvas.restore();
  }

  static Path _sidePath(Rect r) => Path()..addRect(r);

  static Path _wavePath(Rect r) {
    final path = Path()..moveTo(r.left, r.bottom);
    path.lineTo(r.left, r.top);
    _addWave(path, r);
    path
      ..lineTo(r.right, r.bottom)
      ..close();
    return path;
  }

  static Path _waveLine(Rect r) {
    final path = Path()..moveTo(r.left, r.top);
    _addWave(path, r);
    return path;
  }

  static void _addWave(Path path, Rect r) {
    const steps = 24;
    final amplitude = math.min(3.0, r.height / 4);
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      path.lineTo(
        r.left + r.width * t,
        r.top + math.sin(t * math.pi * 3 + 0.6) * amplitude,
      );
    }
  }

  static void _paintBubbles(Canvas canvas, Rect r) {
    final paint = Paint()..color = _white.withValues(alpha: 0.38);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = _white.withValues(alpha: 0.55);
    // Fixed spots, so a bubble never jumps between frames or between two
    // vessels showing the same level.
    const spots = [(0.18, 0.66, 1.4), (0.42, 0.42, 1.0), (0.71, 0.72, 1.7)];
    for (final (fx, fy, size) in spots) {
      final scale = math.min(1.0, r.height / 18);
      final c = Offset(r.left + r.width * fx, r.top + r.height * fy);
      if (r.width < 18) break;
      canvas.drawCircle(c, size * scale, paint);
      canvas.drawCircle(c, size * scale, ring);
    }
  }
}

enum HoneySurface { side, wave }

const _white = Color(0xFFFFFFFF);
