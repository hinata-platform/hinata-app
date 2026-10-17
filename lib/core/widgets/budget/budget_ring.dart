import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/time_usage_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../hive_widgets.dart' show hiveEase;
import 'budget_style.dart';

/// A budget as an open ring with the percent inside: the dashboard's form,
/// where several projects stand side by side and the shape has to be read at a
/// glance (HIN-151). The name and what is left sit under it as text.
///
/// The arc stops full at the limit; past it, the ring turns to the danger
/// colour and the glyph under the figure says so.
class BudgetRing extends StatelessWidget {
  const BudgetRing({
    super.key,
    required this.label,
    required this.gauge,
    this.format = budgetMinutes,
    this.footer,
    this.onTap,
  });

  final String label;
  final BudgetGauge gauge;
  final BudgetAmountFormat format;

  /// An extra line under the remainder, e.g. "lasts until 14 Nov" (HIN-156).
  final String? footer;
  final VoidCallback? onTap;

  static const _size = 84.0;

  /// The column a ring takes at text scale 1. It grows with the reader's text
  /// size, so a long project name wraps between words instead of inside one.
  static const baseWidth = 108.0;

  @override
  Widget build(BuildContext context) {
    final level = gauge.level;
    final width = MediaQuery.textScalerOf(context).scale(baseWidth);
    final ring = SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: _size,
            child: TweenAnimationBuilder<double>(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 700),
              curve: hiveEase,
              tween: Tween(begin: 0, end: gauge.fraction.clamp(0.0, 1.0)),
              builder: (context, value, child) => CustomPaint(
                painter: _RingPainter(
                  value: value,
                  fill: BudgetStyle.fill(level),
                  track: AppColors.canvas2,
                ),
                child: child,
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      BudgetStyle.percent(context, gauge),
                      style: TextStyle(
                        fontSize: AppType.title,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppType.label,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          // The glyph sits inside the sentence, so a wrapped "14 h over"
          // keeps it on its first line instead of floating beside both.
          Text.rich(
            TextSpan(
              children: [
                if (level == BudgetLevel.over) ...[
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(
                      BudgetStyle.icon(level),
                      size: 13,
                      color: BudgetStyle.ink(level),
                    ),
                  ),
                  const TextSpan(text: '\u00a0'),
                ],
                TextSpan(text: BudgetStyle.remainder(context, gauge, format)),
              ],
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppType.caption,
              height: 1.35,
              color: BudgetStyle.ink(level),
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 2),
            Text(
              footer!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppType.caption,
                height: 1.35,
                color: AppColors.inkSoft,
              ),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      label: BudgetStyle.semantics(context, label, gauge, format),
      excludeSemantics: true,
      onTap: onTap,
      child: onTap == null
          ? ring
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(padding: const EdgeInsets.all(6), child: ring),
            ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.fill,
    required this.track,
  });

  final double value;
  final Color fill;
  final Color track;

  // An open ring: 270 degrees from bottom left round to bottom right.
  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;
  static const _stroke = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, paint..color = track);
    if (value > 0) {
      canvas.drawArc(rect, _start, _sweep * value, false, paint..color = fill);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.fill != fill || old.track != track;
}
