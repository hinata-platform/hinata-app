import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/models/shift_models.dart';
import '../../../core/models/time_usage_models.dart' show BudgetLevel;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/budget/budget_cell.dart' show hexagonPath;
import '../../../core/widgets/budget/honey_glass.dart';
import '../shift_texts.dart';

/// The glyph that says a coverage state a second way, beside the colour
/// (WCAG 1.4.1): a triangle while people are missing, a tick once the need
/// is met, a lock at the upper limit.
(IconData, Color) coverageGlyph(CoverageState state) => switch (state) {
  CoverageState.under => (LucideIcons.triangleAlert, AppColors.warningInk),
  CoverageState.met ||
  CoverageState.over => (LucideIcons.check, AppColors.successInk),
  CoverageState.full => (LucideIcons.lock, AppColors.inkFaint),
};

/// One cell of the hive: a glass hexagon with honey up to [fill] and [label]
/// in the middle (HIN-27 "Besetzungswabe").
///
/// Decorative: it is excluded from semantics, and whatever it says is said
/// beside it in text. With [animate] the honey rises to its level once when
/// the cell first appears (hero and sheet only, never in a scrolling row) and
/// not at all when the reader has asked for less motion.
class HoneyCell extends StatelessWidget {
  const HoneyCell({
    super.key,
    required this.fill,
    required this.label,
    this.size = 26,
    this.warning = false,
    this.capped = false,
    this.animate = false,
  });

  final double fill;
  final String label;

  /// The width; the height follows the hexagon.
  final double size;

  /// Drawn with the warm rim of a cell that still needs people.
  final bool warning;

  /// Sealed with a wax lid: nobody else fits.
  final bool capped;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final still = !animate || MediaQuery.disableAnimationsOf(context);
    Widget cell(double level) => CustomPaint(
      painter: _HoneyCellPainter(
        fill: level,
        dark: dark,
        capped: capped,
        warning: warning,
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: size * 0.14),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              // The figure inside the cell is a picture of the number beside
              // it; it does not grow with the text, the one beside it does.
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontSize: math.max(AppType.badge, size * 0.4),
                fontWeight: FontWeight.w800,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: fill >= 0.55 ? HoneyGlass.onLiquid : AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          width: size,
          height: size * 2 / math.sqrt(3),
          child: still
              ? cell(fill)
              : TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fill),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, level, _) => cell(level),
                ),
        ),
      ),
    );
  }
}

/// A shift's coverage at a glance: the cell, the glyph and the figure
/// (`2 / 3`), announced as one sentence.
///
/// The figure scales with the reader's text; the cell does not. Without
/// [showFigure] only cell and glyph are drawn (the hero, the sheet), and the
/// sentence still carries the count.
class CoverageHex extends StatelessWidget {
  const CoverageHex({
    super.key,
    required this.coverage,
    this.size = 26,
    this.showFigure = true,
    this.animate = false,
    this.onNavy = false,
  });

  final Coverage coverage;
  final double size;
  final bool showFigure;
  final bool animate;

  /// Drawn on the navy hero card, where the figure is light.
  final bool onNavy;

  @override
  Widget build(BuildContext context) {
    final state = coverage.state;
    final (glyph, ink) = coverageGlyph(state);
    return Semantics(
      container: true,
      label: coverageSemantics(context, coverage),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HoneyCell(
              fill: coverage.fill,
              label: '${coverage.assigned}',
              size: size,
              warning: state == CoverageState.under,
              capped: state == CoverageState.full,
              animate: animate,
            ),
            const SizedBox(width: 8),
            Icon(
              glyph,
              size: 15,
              color: onNavy && state != CoverageState.under
                  ? AppColors.inkSoftOnNavy
                  : ink,
            ),
            if (showFigure) ...[
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  coverageFigure(context, coverage),
                  style: TextStyle(
                    fontSize: AppType.label,
                    fontWeight: FontWeight.w700,
                    color: onNavy ? AppColors.inkOnNavy : AppColors.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HoneyCellPainter extends CustomPainter {
  const _HoneyCellPainter({
    required this.fill,
    required this.dark,
    required this.capped,
    required this.warning,
  });

  final double fill;
  final bool dark;
  final bool capped;
  final bool warning;

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
        warning ? BudgetLevel.near : BudgetLevel.within,
        surface: fill >= 1 ? HoneySurface.side : HoneySurface.wave,
        bubbles: false,
      );
    }
    HoneyGlass.paintRim(canvas, shape, bounds, dark);
    if (warning) {
      canvas.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = AppColors.warningBar,
      );
    }
    if (capped) {
      // A sealed cell: wax across the top third.
      canvas.save();
      canvas.clipPath(shape);
      final lid = size.height * 0.34;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, lid),
        Paint()..color = Colors.white.withValues(alpha: dark ? 0.32 : 0.55),
      );
      canvas.drawLine(
        Offset(2, lid),
        Offset(size.width - 2, lid),
        Paint()
          ..color = AppColors.glassShade.withValues(alpha: 0.25)
          ..strokeWidth = 1,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_HoneyCellPainter old) =>
      old.fill != fill ||
      old.dark != dark ||
      old.capped != capped ||
      old.warning != warning;
}
