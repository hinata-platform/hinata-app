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

  /// Slice count — a hard performance ceiling.
  ///
  /// Each slice is a real [BackdropFilter] blur *pass* on the GPU. `BackdropGroup`
  /// only shares the backdrop *capture*; it does NOT collapse the N blur passes
  /// into one. This bar overlays scrolling content, so every pass re-runs on each
  /// scroll/keystroke frame — the earlier value of 50 meant ~48 blur passes per
  /// frame and was the app's dominant source of jank on Android.
  ///
  /// 8 slices keep the gradient dissolve visually smooth (the translucent scrim
  /// on top masks any residual banding) at ~6x lower cost. Do NOT raise this
  /// without profiling on a real mid-range Android device — [progressiveBlurTest]
  /// guards the ceiling.
  static const int _slices = 8;

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
