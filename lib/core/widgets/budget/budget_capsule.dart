import 'package:flutter/material.dart';

import '../../models/time_usage_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import 'budget_style.dart';
import 'honey_glass.dart';

/// A budget as a glass capsule with honey filling it from the start: the
/// short form, for heads and rows where a tube would not fit (HIN-151) — the
/// project head on the board, the project list, a Gantt row.
///
/// The figure is drawn twice, the way the battery percent sits in iOS: navy
/// where it stands over honey, the page's ink where it stands over glass. So
/// it stays legible at every level without a box behind it.
///
/// When [onTap] is set it is a button with a 48 dp tall hit area; the tooltip
/// and the semantics carry the sums the capsule leaves out.
class BudgetCapsule extends StatelessWidget {
  const BudgetCapsule({
    super.key,
    required this.label,
    required this.gauge,
    this.format = budgetMinutes,
    this.onTap,
  });

  final String label;
  final BudgetGauge gauge;
  final BudgetAmountFormat format;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final level = gauge.level;
    final fill = gauge.fraction.clamp(0.0, 1.0);

    Widget figure(Color color) => Padding(
      padding: const EdgeInsets.fromLTRB(9, 4, 11, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(BudgetStyle.icon(level), size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            BudgetStyle.percent(context, gauge),
            style: TextStyle(
              fontSize: AppType.caption,
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    final capsule = TweenAnimationBuilder<double>(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: fill),
      builder: (context, value, _) => CustomPaint(
        painter: _CapsulePainter(
          fill: value,
          level: level,
          dark: dark,
          direction: Directionality.of(context),
        ),
        child: Stack(
          children: [
            figure(
              level == BudgetLevel.within
                  ? AppColors.inkSoft
                  : BudgetStyle.ink(level),
            ),
            Positioned.fill(
              child: ClipRect(
                clipper: _FractionClip(value, Directionality.of(context)),
                child: figure(HoneyGlass.onLiquid),
              ),
            ),
          ],
        ),
      ),
    );

    final tooltip =
        '${BudgetStyle.usedOfLimit(context, gauge, format)}, '
        '${BudgetStyle.remainder(context, gauge, format)}';
    return Semantics(
      button: onTap != null,
      label: BudgetStyle.semantics(context, label, gauge, format),
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: onTap == null
            ? capsule
            : InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(99),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Center(widthFactor: 1, child: capsule),
                ),
              ),
      ),
    );
  }
}

class _FractionClip extends CustomClipper<Rect> {
  const _FractionClip(this.fraction, this.direction);

  final double fraction;

  /// Honey fills from where reading starts, so from the right in Arabic.
  final TextDirection direction;

  @override
  Rect getClip(Size size) {
    // The liquid starts inside the rim, so its edge sits that much in.
    const inset = 2.0;
    final width = inset + (size.width - inset * 2) * fraction;
    return direction == TextDirection.rtl
        ? Rect.fromLTWH(size.width - width, 0, width, size.height)
        : Rect.fromLTWH(0, 0, width, size.height);
  }

  @override
  bool shouldReclip(_FractionClip old) =>
      old.fraction != fraction || old.direction != direction;
}

class _CapsulePainter extends CustomPainter {
  const _CapsulePainter({
    required this.fill,
    required this.level,
    required this.dark,
    required this.direction,
  });

  final double fill;
  final BudgetLevel level;
  final bool dark;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final shape = Path()
      ..addRRect(
        RRect.fromRectAndRadius(bounds, Radius.circular(size.height / 2)),
      );
    HoneyGlass.paintVessel(canvas, shape, bounds, dark);
    final inner = bounds.deflate(2);
    final innerShape = Path()
      ..addRRect(
        RRect.fromRectAndRadius(inner, Radius.circular(inner.height / 2)),
      );
    HoneyGlass.paintHoney(
      canvas,
      innerShape,
      direction == TextDirection.rtl
          ? Rect.fromLTWH(
              inner.right - inner.width * fill,
              inner.top,
              inner.width * fill,
              inner.height,
            )
          : Rect.fromLTWH(
              inner.left,
              inner.top,
              inner.width * fill,
              inner.height,
            ),
      level,
      bubbles: false,
    );
    HoneyGlass.paintRim(canvas, shape, bounds, dark);
  }

  @override
  bool shouldRepaint(_CapsulePainter old) =>
      old.fill != fill ||
      old.level != level ||
      old.dark != dark ||
      old.direction != direction;
}
