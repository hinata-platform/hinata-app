import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// App-wide ambient backdrop for the v2 "Liquid Glass" shell: a warm-paper (or
/// deep-navy in dark mode) vertical gradient with two soft, heavily-blurred
/// amber/navy glow blobs. Rendered once behind the whole app (rail + topbar +
/// content) so every screen — not just the dashboard — sits on the same canvas.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [Color(0xFF131226), Color(0xFF1B1936), Color(0xFF171531)]
                : const [Color(0xFFF0EEE6), Color(0xFFF5F3EC), Color(0xFFEFEBE0)],
          ),
        ),
        child: Stack(
          children: [
            _blob(
              left: -140,
              top: -180,
              size: 560,
              color: const Color(0xFFD9A032),
              opacity: dark ? .20 : .34,
            ),
            _blob(
              right: -200,
              top: 260,
              size: 640,
              color: dark ? const Color(0xFF5E58BE) : const Color(0xFF2D2B55),
              opacity: dark ? .26 : .20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _blob({
    double? left,
    double? right,
    double? top,
    required double size,
    required Color color,
    required double opacity,
  }) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: opacity),
          ),
        ),
      ),
    );
  }
}
