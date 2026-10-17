import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/time_usage_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../hive_widgets.dart' show hiveEase;
import 'budget_style.dart';

/// A budget or an estimate as a bar with its sums: the large form, for the
/// places where somebody decides how much more to spend (HIN-151).
///
/// The bar keeps its meaning past the limit. Instead of stopping full, the
/// track then stands for everything recorded: the part up to the limit is
/// solid, the overhang hatched, and a tick marks where the limit was. "125 h of
/// 100 h" so reads as a fifth over rather than as a bar that merely filled up.
///
/// [gauge] null renders the loading state: an empty track and a dash, the same
/// height as the finished meter so nothing jumps when the numbers arrive.
class BudgetMeter extends StatelessWidget {
  const BudgetMeter({
    super.key,
    required this.label,
    required this.gauge,
    this.format = budgetMinutes,
    this.showRemainder = true,
    this.footer,
  });

  final String label;
  final BudgetGauge? gauge;
  final BudgetAmountFormat format;

  /// The "24 h left" line under the bar.
  final bool showRemainder;

  /// An extra line under the remainder, e.g. a forecast (HIN-156).
  final Widget? footer;

  static const _barHeight = 6.0;

  @override
  Widget build(BuildContext context) {
    final gauge = this.gauge;
    final level = gauge?.level ?? BudgetLevel.within;
    final labelStyle = TextStyle(
      fontSize: AppType.label,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
    );
    final sumsStyle = TextStyle(
      fontSize: AppType.label,
      height: 1.4,
      color: AppColors.inkSoft,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final meter = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label and sums share a line while they fit, and wrap under each
        // other at a large text size instead of clipping.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 2,
          children: [
            Text(label, style: labelStyle),
            Text(
              gauge == null
                  ? '–'
                  : '${BudgetStyle.usedOfLimit(context, gauge, format)} · '
                        '${BudgetStyle.percent(context, gauge)}',
              style: sumsStyle,
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _barHeight,
          child: TweenAnimationBuilder<double>(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 600),
            curve: hiveEase,
            tween: Tween(begin: 0, end: gauge?.fraction ?? 0),
            builder: (context, fraction, _) => CustomPaint(
              painter: _BarPainter(
                fraction: fraction,
                fill: BudgetStyle.fill(level),
                track: AppColors.canvas2,
                rim: AppColors.hairline,
                tick: AppColors.ink,
              ),
            ),
          ),
        ),
        if (showRemainder && gauge != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              if (level != BudgetLevel.within) ...[
                Icon(
                  BudgetStyle.icon(level),
                  size: 14,
                  color: BudgetStyle.ink(level),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  BudgetStyle.remainder(context, gauge, format),
                  style: TextStyle(
                    fontSize: AppType.caption,
                    height: 1.4,
                    fontWeight: level == BudgetLevel.within
                        ? FontWeight.w400
                        : FontWeight.w600,
                    color: BudgetStyle.ink(level),
                  ),
                ),
              ),
            ],
          ),
        ],
        if (footer != null) ...[const SizedBox(height: 6), footer!],
      ],
    );
    return Semantics(
      container: true,
      label: gauge == null
          ? label
          : BudgetStyle.semantics(context, label, gauge, format),
      child: ExcludeSemantics(child: meter),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.fraction,
    required this.fill,
    required this.track,
    required this.rim,
    required this.tick,
  });

  final double fraction;
  final Color fill;
  final Color track;
  final Color rim;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final whole = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(whole, Paint()..color = track);
    canvas.drawRRect(
      whole.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = rim,
    );
    if (fraction <= 0) return;

    canvas.save();
    canvas.clipRRect(whole);
    if (fraction <= 1) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * fraction, size.height),
        Paint()..color = fill,
      );
    } else {
      // The track now stands for everything recorded; the limit sits at
      // 1 / fraction of it.
      final limitX = size.width / fraction;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, limitX, size.height),
        Paint()..color = fill,
      );
      final over = Rect.fromLTWH(limitX, 0, size.width - limitX, size.height);
      canvas.drawRect(over, Paint()..color = fill.withValues(alpha: 0.28));
      final hatch = Paint()
        ..color = fill
        ..strokeWidth = 2;
      canvas.clipRect(over);
      for (var x = limitX - size.height; x < size.width; x += 5) {
        canvas.drawLine(
          Offset(x, size.height),
          Offset(x + size.height, 0),
          hatch,
        );
      }
      canvas.restore();
      canvas.save();
      // The limit's tick stands a little proud of the bar so it reads even
      // where both sides of it are the same colour.
      canvas.drawRect(
        Rect.fromLTWH(math.max(0, limitX - 1), -2, 2, size.height + 4),
        Paint()..color = tick,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.fraction != fraction ||
      old.fill != fill ||
      old.track != track ||
      old.rim != rim ||
      old.tick != tick;
}
