import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/time_usage_models.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_type.dart';
import 'budget_meter.dart' show OverflowCapsule;
import 'budget_style.dart';
import 'honey_glass.dart';

/// A budget as one cell of the hive: a glass hexagon filling with honey from
/// the bottom, the percent in its middle (HIN-151, "Honigstand").
///
/// Made for the dashboard, where several projects stand side by side as a
/// small honeycomb on the navy hero card, and for anything else that wants a
/// budget at a glance. The figure is drawn twice like the capsule's, navy over
/// honey and light over glass, so a half full cell still reads.
///
/// [onDark] picks the vessel for a navy surface; the hero card is navy in both
/// themes.
class BudgetCell extends StatelessWidget {
  const BudgetCell({
    super.key,
    required this.label,
    required this.gauge,
    this.format = budgetMinutes,
    this.onDark = true,
    this.footer,
    this.onTap,
  });

  final String label;
  final BudgetGauge gauge;
  final BudgetAmountFormat format;
  final bool onDark;

  /// An extra line under the remainder, e.g. "lasts until 14 Nov" (HIN-156).
  final String? footer;
  final VoidCallback? onTap;

  /// The cell's width at text scale 1; its height follows the hexagon.
  static const cellWidth = 92.0;

  /// The column a cell and its words take; grows with the text size so a
  /// long project name wraps between words.
  static const columnWidth = 112.0;

  /// What one cell occupies in a row, its tap padding included.
  static double slotWidth(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(columnWidth) + 8;

  @override
  Widget build(BuildContext context) {
    final level = gauge.level;
    final ink = onDark ? const Color(0xFFF3F1FA) : const Color(0xFF23223F);
    final soft = onDark ? const Color(0xFFC9C6DC) : const Color(0xFF55546F);
    final width = MediaQuery.textScalerOf(context).scale(columnWidth);
    final height = cellWidth * 2 / math.sqrt(3);
    Widget figure(Color color) => Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            BudgetStyle.percent(context, gauge),
            style: TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: AppType.title,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: color,
            ),
          ),
        ),
      ),
    );
    final cell = SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: cellWidth,
            height: height,
            child: TweenAnimationBuilder<double>(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 1100),
              curve: Curves.easeOutBack,
              tween: Tween(begin: 0, end: gauge.fraction.clamp(0.0, 1.0)),
              builder: (context, value, _) {
                final painter = _CellPainter(
                  fill: value,
                  level: level,
                  dark: onDark,
                );
                return CustomPaint(
                  painter: painter,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      figure(ink),
                      ClipPath(
                        clipper: _LiquidClip(value),
                        child: figure(HoneyGlass.onLiquid),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (gauge.overBy > 0) ...[
            Transform.translate(
              offset: const Offset(0, -10),
              child: OverflowCapsule(text: '+${format(context, gauge.overBy)}'),
            ),
          ] else
            const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppType.label,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            BudgetStyle.remainder(context, gauge, format),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppType.caption,
              height: 1.3,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: level == BudgetLevel.within
                  ? soft
                  : HoneyGlass.liquid(level).first,
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 2),
            Text(
              footer!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppType.caption,
                height: 1.3,
                color: soft,
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
          ? cell
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(padding: const EdgeInsets.all(4), child: cell),
            ),
    );
  }
}

/// A pointy-top hexagon with slightly rounded corners, filling [size].
Path hexagonPath(Size size, {double inset = 0, double corner = 6}) {
  final r = Rect.fromLTWH(
    inset,
    inset,
    size.width - inset * 2,
    size.height - inset * 2,
  );
  final points = [
    Offset(r.center.dx, r.top),
    Offset(r.right, r.top + r.height * 0.25),
    Offset(r.right, r.top + r.height * 0.75),
    Offset(r.center.dx, r.bottom),
    Offset(r.left, r.top + r.height * 0.75),
    Offset(r.left, r.top + r.height * 0.25),
  ];
  final path = Path();
  for (var i = 0; i < points.length; i++) {
    final prev = points[(i + points.length - 1) % points.length];
    final at = points[i];
    final next = points[(i + 1) % points.length];
    final a = at + (prev - at) * (corner / (prev - at).distance);
    final b = at + (next - at) * (corner / (next - at).distance);
    if (i == 0) {
      path.moveTo(a.dx, a.dy);
    } else {
      path.lineTo(a.dx, a.dy);
    }
    path.quadraticBezierTo(at.dx, at.dy, b.dx, b.dy);
  }
  return path..close();
}

class _LiquidClip extends CustomClipper<Path> {
  const _LiquidClip(this.fill);

  final double fill;

  @override
  Path getClip(Size size) {
    final top = size.height - (size.height - 6) * fill - 3;
    return Path.combine(
      PathOperation.intersect,
      hexagonPath(size, inset: 3),
      Path()..addRect(Rect.fromLTRB(0, top, size.width, size.height)),
    );
  }

  @override
  bool shouldReclip(_LiquidClip old) => old.fill != fill;
}

class _CellPainter extends CustomPainter {
  const _CellPainter({
    required this.fill,
    required this.level,
    required this.dark,
  });

  final double fill;
  final BudgetLevel level;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final shape = hexagonPath(size);
    HoneyGlass.paintVessel(canvas, shape, bounds, dark);
    final inner = hexagonPath(size, inset: 3, corner: 5);
    final top = size.height - (size.height - 6) * fill - 3;
    HoneyGlass.paintHoney(
      canvas,
      inner,
      Rect.fromLTRB(0, top, size.width, size.height),
      fill >= 1 ? BudgetLevel.over : level,
      surface: fill >= 1 ? HoneySurface.side : HoneySurface.wave,
    );
    HoneyGlass.paintRim(canvas, shape, bounds, dark);
  }

  @override
  bool shouldRepaint(_CellPainter old) =>
      old.fill != fill || old.level != level || old.dark != dark;
}
