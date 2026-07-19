import 'package:flutter/material.dart';
import 'package:hinata/core/responsive/responsive.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Hinata hex-mark: a stroked pointy-top hexagon with a horizontal centre bar.
/// SVG source (viewBox 0 0 120 120):
///   path d="M60 14 99.8 37v46L60 106 20.2 83V37Z"   ← hexagon
///   path d="M20.2 60h79.6"                           ← centre bar
/// All stroked, fill: none, round caps & joins.
class HexMark extends StatelessWidget {
  const HexMark({super.key, this.size = 32, this.color = AppColors.accent});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _HexMarkPainter(color: color),
    );
  }
}

/// Full brand lockup used on the connect / onboarding screens:
/// the hex signet in an amber-tinted rounded tile, "hinata" wordmark below.
class HivBrandLockup extends StatelessWidget {
  const HivBrandLockup({super.key, this.hexSize = 64});
  final double hexSize;

  @override
  Widget build(BuildContext context) {
    final tile = hexSize + 16;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: tile,
            height: tile,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(tile * 0.26),
              border: Border.all(color: AppColors.accentLine),
            ),
            alignment: Alignment.center,
            child: HexMark(size: hexSize * 0.68),
          ),
          if (!context.isCompact) ...[
            const SizedBox(height: 12),
            Text(
              'hinata',
              style: TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontSize: hexSize * 0.58,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HexMarkPainter extends CustomPainter {
  const _HexMarkPainter({required this.color});
  final Color color;

  // Original SVG viewBox is 120×120.
  // Hexagon: M60 14 99.8 37v46L60 106 20.2 83V37Z
  // Bar:     M20.2 60h79.6
  static const _vb = 120.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _vb;
    final sw = 11.0 * scale; // stroke-width: 11 in SVG

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Hexagon
    final hex = Path()
      ..moveTo(60 * scale, 14 * scale)
      ..lineTo(99.8 * scale, 37 * scale)
      ..lineTo(99.8 * scale, 83 * scale) // v46
      ..lineTo(60 * scale, 106 * scale)
      ..lineTo(20.2 * scale, 83 * scale)
      ..lineTo(20.2 * scale, 37 * scale) // V37
      ..close();
    canvas.drawPath(hex, paint);

    // Horizontal centre bar
    canvas.drawLine(
      Offset(20.2 * scale, 60 * scale),
      Offset(99.8 * scale, 60 * scale),
      paint,
    );
  }

  @override
  bool shouldRepaint(_HexMarkPainter old) => old.color != color;
}
