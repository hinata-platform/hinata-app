import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// The pieces every report list is built from (HIN-93, shared since HIN-119):
/// a scroll that asks for the next page before its end, and the slices a lazy
/// list of rows reads as one card with.

/// A scroll view of slivers that asks for more when the reader nears its end.
class ReportPagedScroll extends StatelessWidget {
  const ReportPagedScroll({
    super.key,
    required this.slivers,
    required this.onEnd,
  });

  final List<Widget> slivers;
  final Future<void> Function() onEnd;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical &&
            notification.metrics.extentAfter < 600) {
          unawaited(onEnd());
        }
        return false;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: slivers,
      ),
    );
  }
}

/// A slice of one card: its sides always, its top edge on the first slice and
/// its bottom edge and corners on the last — so a lazy list of rows reads as
/// one card. Each edge is its own line, never a border with a gap in it.
class ReportCardEdge extends StatelessWidget {
  const ReportCardEdge({
    super.key,
    required this.child,
    this.top = false,
    this.last = false,
  });

  final Widget child;
  final bool top;
  final bool last;

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(AppTheme.radiusCard);
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: top ? radius : Radius.zero,
        bottom: last ? radius : Radius.zero,
      ),
      child: CustomPaint(
        foregroundPainter: _EdgePainter(
          color: AppColors.hairline,
          top: top,
          bottom: last,
          radius: AppTheme.radiusCard,
        ),
        child: ColoredBox(color: AppColors.surface, child: child),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  const _EdgePainter({
    required this.color,
    required this.top,
    required this.bottom,
    required this.radius,
  });

  final Color color;
  final bool top;
  final bool bottom;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Offset.zero & size;
    final path = Path();
    final r = radius;
    final left = rect.left + 0.5;
    final right = rect.right - 0.5;
    final topY = rect.top + 0.5;
    final bottomY = rect.bottom - 0.5;
    // Left side, the bottom edge when this slice closes the card, the right
    // side, and the top edge when it opens it.
    path.moveTo(left, top ? topY + r : rect.top);
    path.lineTo(left, bottom ? bottomY - r : rect.bottom);
    if (bottom) {
      path.arcToPoint(
        Offset(left + r, bottomY),
        radius: Radius.circular(r),
        clockwise: false,
      );
      path.lineTo(right - r, bottomY);
      path.arcToPoint(
        Offset(right, bottomY - r),
        radius: Radius.circular(r),
        clockwise: false,
      );
    } else {
      path.moveTo(right, rect.bottom);
    }
    path.lineTo(right, top ? topY + r : rect.top);
    if (top) {
      path.arcToPoint(
        Offset(right - r, topY),
        radius: Radius.circular(r),
        clockwise: false,
      );
      path.lineTo(left + r, topY);
      path.arcToPoint(
        Offset(left, topY + r),
        radius: Radius.circular(r),
        clockwise: false,
      );
    }
    canvas.drawPath(path, paint);
    if (!bottom) {
      // The line between two rows, inset like a list's divider.
      canvas.drawLine(
        Offset(16, rect.bottom - 0.5),
        Offset(rect.right - 16, rect.bottom - 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.color != color ||
      old.top != top ||
      old.bottom != bottom ||
      old.radius != radius;
}
