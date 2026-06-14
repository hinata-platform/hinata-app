import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Hivora's signature loading indicator — the hex-mark logo brought to life.
///
/// A luminous "worker" comet traces the hexagonal honeycomb cell of the Hivora
/// logo while the centre bar shimmers in sync and the whole cell breathes
/// gently. It is built purely from a single [AnimationController] and
/// [CustomPaint] — no external packages, no fragment shaders that need runtime
/// precompilation — so it renders identically and smoothly on every platform
/// (Android, iOS, macOS, Windows, Linux and Web for both the CanvasKit and
/// HTML/skwasm renderers).
///
/// It is the one loading primitive used across the app. It scales cleanly from
/// a 14 px inline button spinner up to a full-screen splash: the fine details
/// (comet tail, bar shimmer, breathing) fade out below ~28 px so it stays crisp
/// and legible when tiny.
///
/// ```dart
/// // Indeterminate (default) — full-screen / centred:
/// const Center(child: HiveLoader());
///
/// // Inside a button, matching the old 22px spinner:
/// const HiveLoader(size: 22, color: Colors.white, strokeWidth: 2);
///
/// // Determinate progress (0..1) — fills the hexagon outline:
/// HiveLoader(value: downloaded / total);
/// ```
class HiveLoader extends StatefulWidget {
  const HiveLoader({
    super.key,
    this.size = 40,
    this.color,
    this.value,
    this.strokeWidth,
    this.semanticsLabel,
  });

  /// Edge length (logical px) of the square the loader paints into.
  final double size;

  /// Comet / progress colour. Defaults to the signature honey-amber [accent].
  final Color? color;

  /// When non-null and in `0..1`, renders a determinate arc that fills the
  /// hexagon outline instead of the looping comet.
  final double? value;

  /// Optional override for the hexagon stroke width. Defaults to a
  /// size-proportional value that mirrors the static [HexMark] logo.
  final double? strokeWidth;

  /// Accessibility label announced by screen readers.
  final String? semanticsLabel;

  @override
  State<HiveLoader> createState() => _HiveLoaderState();
}

class _HiveLoaderState extends State<HiveLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.accent;
    return Semantics(
      label: widget.semanticsLabel,
      value: widget.value == null
          ? null
          : '${(widget.value!.clamp(0.0, 1.0) * 100).round()}%',
      // RepaintBoundary isolates the per-frame repaint from the rest of the
      // tree so the surrounding UI is never re-rastered while we animate.
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              size: Size.square(widget.size),
              painter: _HiveLoaderPainter(
                t: _controller.value,
                color: color,
                value: widget.value,
                strokeWidth: widget.strokeWidth,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HiveLoaderPainter extends CustomPainter {
  _HiveLoaderPainter({
    required this.t,
    required this.color,
    required this.value,
    required this.strokeWidth,
  });

  /// Animation phase in `0..1`.
  final double t;
  final Color color;

  /// `null` => indeterminate comet, otherwise a `0..1` progress arc.
  final double? value;
  final double? strokeWidth;

  // Logo design space (matches [HexMark] and every native splash path):
  //   hexagon : M60 14 99.8 37v46L60 106 20.2 83V37Z
  //   bar     : M20.2 60h79.6
  static const double _vb = 120.0;
  static const double _tau = 2 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / _vb;
    final bool detail = size.width >= 28; // hide fine motion when tiny
    final double sw = (strokeWidth ?? 9.0 * s).clamp(1.5, 14.0);

    // Subtle "breathing" of the whole cell for a sense of life. Skipped at
    // small sizes where it would only read as jitter.
    if (detail) {
      final breathe = 1 + 0.022 * math.sin(t * _tau);
      final c = size.center(Offset.zero);
      canvas
        ..save()
        ..translate(c.dx, c.dy)
        ..scale(breathe)
        ..translate(-c.dx, -c.dy);
    }

    final hex = _hexPath(s);
    final double barY = 60 * s;
    final double barX1 = 20.2 * s;
    final double barX2 = 99.8 * s;

    // ---- faint track (the resting logo behind the moving light) ----
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: 0.16);
    canvas.drawPath(hex, track);
    canvas.drawLine(Offset(barX1, barY), Offset(barX2, barY), track);

    final metric = hex.computeMetrics().first;
    final double len = metric.length;

    if (value != null) {
      // ---- determinate: fill the outline from the top vertex ----
      final v = value!.clamp(0.0, 1.0);
      if (v > 0) {
        final arc = metric.extractPath(0, len * v);
        canvas.drawPath(
          arc,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = sw
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = color,
        );
      }
    } else {
      // ---- indeterminate: a comet with a fading tail circles the cell ----
      final double head = t * len;
      const int segs = 16;
      final double tail = len * (detail ? 0.5 : 0.34);
      final double step = tail / segs;
      // Draw tail → head so the bright head stays on top.
      for (int i = segs - 1; i >= 0; i--) {
        final double f = i / (segs - 1); // 0 at head, 1 at tail tip
        final double fade = (1 - f) * (1 - f); // ease-out brightness
        final seg = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = sw * (0.55 + 0.45 * (1 - f))
          ..color = color.withValues(alpha: fade);
        _drawDash(canvas, metric, len, head - i * step, step * 1.7, seg);
      }

      // ---- centre bar shimmer: a bright highlight slides left↔right ----
      if (detail) {
        final double u = 0.5 + 0.5 * math.sin(t * _tau);
        final double cx = barX1 + (barX2 - barX1) * u;
        final double half = (barX2 - barX1) * 0.16;
        final double a = (cx - half).clamp(barX1, barX2);
        final double b = (cx + half).clamp(barX1, barX2);
        canvas.drawLine(
          Offset(a, barY),
          Offset(b, barY),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = sw
            ..color = color.withValues(alpha: 0.85),
        );
      }
    }

    if (detail) canvas.restore();
  }

  /// Builds the pointy-top hexagon path scaled into the canvas.
  Path _hexPath(double s) => Path()
    ..moveTo(60 * s, 14 * s)
    ..lineTo(99.8 * s, 37 * s)
    ..lineTo(99.8 * s, 83 * s)
    ..lineTo(60 * s, 106 * s)
    ..lineTo(20.2 * s, 83 * s)
    ..lineTo(20.2 * s, 37 * s)
    ..close();

  /// Draws a short stroke of [segLen] centred at perimeter distance [center],
  /// wrapping seamlessly across the path's start/end seam.
  void _drawDash(
    Canvas canvas,
    PathMetric metric,
    double len,
    double center,
    double segLen,
    Paint paint,
  ) {
    double d = center % len;
    if (d < 0) d += len;
    double a = d - segLen / 2;
    double b = d + segLen / 2;
    if (a < 0) {
      canvas.drawPath(metric.extractPath(a + len, len), paint);
      canvas.drawPath(metric.extractPath(0, b), paint);
    } else if (b > len) {
      canvas.drawPath(metric.extractPath(a, len), paint);
      canvas.drawPath(metric.extractPath(0, b - len), paint);
    } else {
      canvas.drawPath(metric.extractPath(a, b), paint);
    }
  }

  @override
  bool shouldRepaint(_HiveLoaderPainter old) =>
      old.t != t ||
      old.color != color ||
      old.value != value ||
      old.strokeWidth != strokeWidth;
}
