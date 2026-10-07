import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The outline of a suggestion rather than recorded time: a dashed rounded
/// rectangle in the item's own colour, at full strength so it clears 3:1
/// against the canvas.
///
/// Shared by the hour canvas and the month, so an event of the reader's
/// calendar reads as the same kind of thing in both.
class DashedOutline extends CustomPainter {
  const DashedOutline({required this.color, this.radius = 6});

  final Color color;
  final double radius;

  static const double _dash = 4;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.75),
          Radius.circular(radius),
        ),
      );
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += _dash + _gap) {
        canvas.drawPath(
          metric.extractPath(at, math.min(at + _dash, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(DashedOutline old) =>
      old.color != color || old.radius != radius;
}
