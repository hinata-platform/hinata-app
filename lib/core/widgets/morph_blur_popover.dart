import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassMenuAlignment, GlassPopover, GlassQuality, LiquidGlassSettings;

/// Drop-in [GlassPopover] wrapper that ramps the backdrop blur in from 0
/// instead of rendering it at full strength for the whole liquid-morph
/// animation.
///
/// The per-frame BackdropFilter blur is the dominant raster cost while a
/// [GlassPopover] is morphing out of its trigger (see
/// `notification-popover-performance.md` at the repo root for the measured
/// before/after). Gating the blur behind a short ramp keeps the cheapest —
/// still-growing — part of the morph cheap, and animating it continuously
/// (rather than snapping it on after a fixed delay) means the transition is
/// never visible as an on/off switch.
///
/// Use this instead of [GlassPopover] anywhere a popover/menu morphs out of a
/// trigger button. Pass [baseSettings] with the panel's resting blur already
/// set — this widget only overrides `blur` during the opening animation via
/// `baseSettings.copyWith(blur: ...)`.
class MorphBlurPopover extends StatefulWidget {
  const MorphBlurPopover({
    super.key,
    this.trigger,
    this.triggerBuilder,
    required this.contentBuilder,
    required this.baseSettings,
    this.popoverWidth = 280,
    this.popoverHeight,
    this.popoverBorderRadius = 24.0,
    this.alignment,
    this.quality,
    this.onOpen,
    this.onClose,
    this.blurRampDuration = const Duration(milliseconds: 260),
  }) : assert(
         trigger != null || triggerBuilder != null,
         'Either trigger or triggerBuilder must be provided',
       );

  final Widget? trigger;
  final Widget Function(BuildContext context, VoidCallback togglePopover)?
  triggerBuilder;
  final Widget Function(BuildContext context, VoidCallback close)
  contentBuilder;

  /// The popover's resting glass settings — `blur` is the target value the
  /// ramp animates toward, not the value used while opening.
  final LiquidGlassSettings baseSettings;

  final double popoverWidth;
  final double? popoverHeight;
  final double popoverBorderRadius;
  final GlassMenuAlignment? alignment;
  final GlassQuality? quality;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;

  /// How long the blur takes to reach [baseSettings]'s blur once opened.
  /// Defaults to the same window the liquid morph itself settles in.
  final Duration blurRampDuration;

  @override
  State<MorphBlurPopover> createState() => _MorphBlurPopoverState();
}

class _MorphBlurPopoverState extends State<MorphBlurPopover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blur = AnimationController(
    vsync: this,
    duration: widget.blurRampDuration,
  );

  @override
  void dispose() {
    _blur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetBlur = widget.baseSettings.blur;
    return AnimatedBuilder(
      animation: _blur,
      builder: (context, _) {
        final blur = targetBlur * Curves.easeOut.transform(_blur.value);
        return GlassPopover(
          trigger: widget.trigger,
          triggerBuilder: widget.triggerBuilder,
          contentBuilder: widget.contentBuilder,
          popoverWidth: widget.popoverWidth,
          popoverHeight: widget.popoverHeight,
          popoverBorderRadius: widget.popoverBorderRadius,
          alignment: widget.alignment,
          settings: widget.baseSettings.copyWith(blur: blur),
          quality: widget.quality,
          onOpen: () {
            _blur
              ..value = 0
              ..forward();
            widget.onOpen?.call();
          },
          onClose: () {
            _blur.stop();
            widget.onClose?.call();
          },
        );
      },
    );
  }
}
