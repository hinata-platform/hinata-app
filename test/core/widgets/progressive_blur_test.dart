import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/progressive_blur.dart';

/// Performance regression guard for [ProgressiveBlur].
///
/// Each slice is a real GPU [BackdropFilter] blur pass, and this widget renders
/// the app's always-on top bar over scrolling content — so every pass re-runs on
/// each scroll/keystroke frame. A previous version used 50 slices (~48 live blur
/// passes per frame) and was the app's dominant source of Android jank.
///
/// These tests pin the pass count to a small ceiling. If someone raises the
/// slice count again, the first test fails loudly instead of silently
/// re-introducing the jank.
void main() {
  Widget host(double maxSigma) => MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.white)),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 120,
                child: ProgressiveBlur(maxSigma: maxSigma),
              ),
            ],
          ),
        ),
      );

  testWidgets('renders far fewer than the old 50 backdrop passes', (
    tester,
  ) async {
    await tester.pumpWidget(host(30));

    final passes = tester.widgetList<BackdropFilter>(
      find.byType(BackdropFilter),
    );

    // Hard ceiling: the current design uses 8 slices (bottom ones fall below the
    // sub-perceptual sigma threshold and are skipped). 12 leaves headroom for a
    // small tweak while still catching a regression to the old 50.
    expect(
      passes.length,
      lessThanOrEqualTo(12),
      reason:
          'ProgressiveBlur must stay cheap: each BackdropFilter is a live GPU '
          'blur pass over scrolling content. A jump back toward 50 was the '
          'original global jank bug.',
    );
    // Sanity: it still blurs (the effect is not accidentally disabled).
    expect(passes.length, greaterThanOrEqualTo(1));

    // Every emitted pass must carry a real blur filter.
    for (final f in passes) {
      expect(f.filter, isA<ImageFilter>());
    }
  });

  testWidgets('emits no blur pass at all when maxSigma is 0', (tester) async {
    await tester.pumpWidget(host(0));
    // maxSigma <= 0 short-circuits to a plain box — zero backdrop cost when the
    // bar is scrolled to its sharp (top-of-page) state.
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
