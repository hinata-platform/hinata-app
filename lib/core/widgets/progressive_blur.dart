import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

/// A vertical *progressive* backdrop blur: heavy at the top edge, easing to
/// perfectly sharp at the bottom (the iOS-26 header look — cf. Instagram's
/// profile header). Stack it behind a translucent app bar so content dissolves
/// beneath it instead of ending on a hard cut-off.
///
/// It slices the area into many thin [BackdropFilter.grouped] bands sharing one
/// [BackdropGroup] capture, so no band ever samples another (no compounded blur
/// → no pixelation) and the whole thing costs a single backdrop capture.
///
/// Drive [maxSigma] from a scroll offset to fade the blur in/out (0 → sharp).
class ProgressiveBlur extends StatelessWidget {
  const ProgressiveBlur({super.key, required this.maxSigma});

  final double maxSigma;

  /// Slice count. High enough that the per-step sigma delta is sub-perceptual
  /// (~1px), so no visible bands.
  static const int _slices = 50;

  @override
  Widget build(BuildContext context) {
    if (maxSigma <= 0) return const SizedBox.expand();
    return ClipRect(
      child: BackdropGroup(
        child: Column(
          children: [
            for (var i = 0; i < _slices; i++)
              Expanded(
                child: _BlurSlice(
                  // t: 0 at the top → 1 at the bottom. A gentle (^1.2) falloff
                  // keeps the blur strong across the top rows, then eases to
                  // sharp near the bottom edge.
                  sigma:
                      maxSigma * pow(1 - (i / (_slices - 1)), 1.2).toDouble(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BlurSlice extends StatelessWidget {
  const _BlurSlice({required this.sigma});

  final double sigma;

  @override
  Widget build(BuildContext context) {
    // Below ~0.3 a blur is imperceptible; skip the filter so the bottom slices
    // stay genuinely sharp and cheap.
    if (sigma < 0.3) return const SizedBox.expand();
    return ClipRect(
      // .grouped → shares the BackdropGroup's single backdrop capture and never
      // samples sibling slices (no compounded blur → no pixelation).
      child: BackdropFilter.grouped(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: const SizedBox.expand(),
      ),
    );
  }
}
