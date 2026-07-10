import 'package:flutter/material.dart';

/// iOS-style edge swipe-back for the shell's content area, on every platform.
///
/// The app navigates with `go` + a custom SharedAxis transition, so Flutter's
/// built-in Cupertino back-swipe (which needs a Cupertino route transition and
/// a real navigator pop) never applies. This widget recreates the gesture on
/// top of any page: a horizontal drag that *starts on the left edge* drags the
/// page along for feedback and, past a distance or fling threshold, fires
/// [onBack] — which routes through the same fallback chain as the system back
/// button, so it also unwinds in-page steps (settings/admin sections).
///
/// Only a narrow edge strip claims the gesture, so horizontally scrolling
/// content (board, gantt, timeline) keeps working everywhere else. The strip
/// is translucent to taps: it carries no tap recognizers, so taps fall through
/// to the page beneath.
class SwipeBackGesture extends StatefulWidget {
  const SwipeBackGesture({
    super.key,
    required this.enabled,
    required this.onBack,
    required this.child,
  });

  /// Queried at drag start — whether there is anything to go back to right
  /// now (pop, in-page override, or a sub-page parent route).
  final ValueGetter<bool> enabled;
  final VoidCallback onBack;
  final Widget child;

  @override
  State<SwipeBackGesture> createState() => _SwipeBackGestureState();
}

class _SwipeBackGestureState extends State<SwipeBackGesture>
    with SingleTickerProviderStateMixin {
  /// Width of the left-edge strip that starts the gesture. Matches the zone
  /// iOS uses so it stays reachable but out of the way of page content.
  static const _edgeWidth = 28.0;

  /// Drag progress past this fraction of the page width triggers back.
  static const _distanceThreshold = 0.30;

  /// Rightward fling velocity (fraction of width per second) that triggers
  /// back regardless of distance.
  static const _flingThreshold = 1.0;

  // value = horizontal drag progress as a fraction of the page width.
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  bool _dragging = false;

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _onStart(DragStartDetails details) {
    if (!widget.enabled()) return;
    _dragging = true;
    _progress.stop();
  }

  void _onUpdate(DragUpdateDetails details, double width) {
    if (!_dragging) return;
    _progress.value += details.delta.dx / width;
  }

  void _onEnd(DragEndDetails details, double width) {
    if (!_dragging) return;
    _dragging = false;
    final velocity = details.velocity.pixelsPerSecond.dx / width;
    final commit =
        velocity >= _flingThreshold ||
        (_progress.value >= _distanceThreshold && velocity > -_flingThreshold);
    if (commit) {
      // Fire the back navigation and settle the page home while the route
      // transition takes over — the outgoing page is fading out anyway, so
      // the settle reads as a hand-off rather than a snap-back.
      widget.onBack();
    }
    _progress.animateBack(0, curve: Curves.easeOutCubic);
  }

  void _onCancel() {
    if (!_dragging) return;
    _dragging = false;
    _progress.animateBack(0, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          children: [
            AnimatedBuilder(
              animation: _progress,
              child: widget.child,
              // A translating render object in a hover path floods
              // !debugNeedsLayout asserts on web during layout churn, so the
              // page is only wrapped while a drag is actually in flight.
              builder: (context, child) => _progress.value == 0
                  ? child!
                  : FractionalTranslation(
                      translation: Offset(_progress.value, 0),
                      child: child,
                    ),
            ),
            // Fixed edge strip that owns the gesture. Being on top of the
            // page it wins the gesture arena against inner horizontal
            // scrollables — but only for drags starting inside the strip.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _edgeWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: _onStart,
                onHorizontalDragUpdate: (d) => _onUpdate(d, width),
                onHorizontalDragEnd: (d) => _onEnd(d, width),
                onHorizontalDragCancel: _onCancel,
              ),
            ),
          ],
        );
      },
    );
  }
}
