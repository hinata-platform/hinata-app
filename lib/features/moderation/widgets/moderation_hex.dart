import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/models/time_usage_models.dart' show BudgetLevel;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/budget/budget_cell.dart' show hexagonPath;
import '../../../core/widgets/budget/honey_glass.dart';

/// The moderation's cell (HIN-173, HIN-174): a hexagon that says a state
/// twice, by how full of honey it is and by its glyph, and always with the
/// word beside it or as its label. No colour carries the state alone.
class ModerationHex extends StatelessWidget {
  const ModerationHex({
    super.key,
    required this.glyph,
    required this.label,
    this.fill = 0,
    this.dashed = false,
    this.urgent = false,
    this.size = 30,
    this.words = true,
  });

  final IconData glyph;

  /// The state in a word: shown beside the cell, and its label for a screen
  /// reader either way.
  final String label;

  /// How full the cell is, from 0 to 1.
  final double fill;

  /// A dashed rim, for a decision someone appealed.
  final bool dashed;

  /// A warning rim, for what is looked at first.
  final bool urgent;

  /// The cell's width; its height follows the hexagon.
  final double size;
  final bool words;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onHoney = fill >= 0.55;
    final cell = SizedBox(
      width: size,
      height: size * 2 / math.sqrt(3),
      child: CustomPaint(
        painter: _HexPainter(
          fill: fill,
          dark: dark,
          dashed: dashed,
          urgent: urgent,
        ),
        child: Center(
          child: Icon(
            glyph,
            size: size * .42,
            color: onHoney ? HoneyGlass.onLiquid : AppColors.ink,
          ),
        ),
      ),
    );
    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: cell),
          if (words) ...[
            const SizedBox(width: 8),
            ExcludeSemantics(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppType.label,
                  fontWeight: FontWeight.w700,
                  color: urgent ? AppColors.warningInk : AppColors.ink,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  const _HexPainter({
    required this.fill,
    required this.dark,
    required this.dashed,
    required this.urgent,
  });

  final double fill;
  final bool dark;
  final bool dashed;
  final bool urgent;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final shape = hexagonPath(size, corner: 4);
    HoneyGlass.paintVessel(canvas, shape, bounds, dark);
    if (fill > 0) {
      final inner = hexagonPath(size, inset: 2, corner: 3);
      final top = size.height - (size.height - 4) * fill - 2;
      HoneyGlass.paintHoney(
        canvas,
        inner,
        Rect.fromLTRB(0, top, size.width, size.height),
        urgent ? BudgetLevel.near : BudgetLevel.within,
        surface: fill >= 1 ? HoneySurface.side : HoneySurface.wave,
        bubbles: false,
      );
    }
    HoneyGlass.paintRim(canvas, shape, bounds, dark);
    if (fill == 0 && !dashed && !urgent) {
      // An empty cell on white paper loses its vessel; a fine ink rim keeps
      // the shape readable without competing with the glyph inside.
      canvas.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AppColors.inkFaint,
      );
    }
    if (urgent) {
      canvas.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = AppColors.warningBar,
      );
    }
    if (dashed) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = AppColors.inkSoft;
      for (final metric in shape.computeMetrics()) {
        var at = 0.0;
        while (at < metric.length) {
          canvas.drawPath(
            metric.extractPath(at, math.min(at + 4, metric.length)),
            paint,
          );
          at += 7;
        }
      }
    }
  }

  @override
  bool shouldRepaint(_HexPainter old) =>
      old.fill != fill ||
      old.dark != dark ||
      old.dashed != dashed ||
      old.urgent != urgent;
}
