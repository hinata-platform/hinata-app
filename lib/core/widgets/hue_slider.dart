import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/hue_colors.dart';
import '../theme/hue_labels.dart';
import '../theme/tint_palette.dart';

/// The two sliders of the tint (HIN-150), after iOS 27's "Customize" sheet:
/// a hue on a spectrum track and a level on a track that runs from white to
/// the colour.
///
/// Material `Slider`s with their own shapes, not `GlassSlider`: the glass
/// slider has no gradient track, and the Material one brings keyboard, focus
/// and semantics. A keyboard or screen-reader step fires start, changed and
/// end at once, so [onChangeEnd] carries whether a pointer was down: a
/// pointer release applies at once, a held arrow key is collected.

/// What [HueSlider.onChangeEnd] and [LevelSlider.onChangeEnd] report.
typedef TintChangeEnd = void Function(int value, {required bool pointer});

/// The hue, 0 to 355 in steps of five, on a spectrum track.
class HueSlider extends StatefulWidget {
  const HueSlider({
    super.key,
    required this.hue,
    required this.level,
    required this.onChanged,
    this.onChangeEnd,
  });

  final int hue;

  /// The level the track is painted at, so the spectrum shows what the hue
  /// would look like at this strength.
  final int level;
  final ValueChanged<int> onChanged;
  final TintChangeEnd? onChangeEnd;

  @override
  State<HueSlider> createState() => _HueSliderState();
}

class _HueSliderState extends State<HueSlider> {
  bool _pointer = false;

  @override
  Widget build(BuildContext context) {
    const max = 360 - _hueStep;
    return _TintSliderFrame(
      label: context.t('account.tint.hue'),
      onPointer: (down) => _pointer = down,
      child: SliderTheme(
        data: _theme(
          context,
        ).copyWith(trackShape: SpectrumTrackShape(widget.level)),
        child: Slider(
          value:
              (widget.hue.clamp(0, max) / _hueStep).roundToDouble() * _hueStep,
          min: 0,
          max: max.toDouble(),
          divisions: max ~/ _hueStep,
          onChanged: (v) => widget.onChanged(v.round()),
          onChangeEnd: (v) =>
              widget.onChangeEnd?.call(v.round(), pointer: _pointer),
          semanticFormatterCallback: (v) => context.t(
            'account.tint.hueValue',
            variables: {
              'degrees': v.round(),
              'name': hueFamilyLabel(context, v.round()),
            },
          ),
        ),
      ),
    );
  }
}

/// The level, 0 (clear glass, pale accent) to 100, on a track that runs
/// from white to the colour of [hue].
class LevelSlider extends StatefulWidget {
  const LevelSlider({
    super.key,
    required this.hue,
    required this.level,
    required this.onChanged,
    this.onChangeEnd,
  });

  final int hue;
  final int level;
  final ValueChanged<int> onChanged;
  final TintChangeEnd? onChangeEnd;

  /// What a reader hears beside the number: the glass is clear at the low
  /// end, which a percentage alone does not say.
  static String hintKey(int level) => level < 34
      ? 'account.tint.levelClear'
      : level > 66
      ? 'account.tint.levelStrong'
      : 'account.tint.levelMid';

  @override
  State<LevelSlider> createState() => _LevelSliderState();
}

class _LevelSliderState extends State<LevelSlider> {
  bool _pointer = false;

  @override
  Widget build(BuildContext context) {
    return _TintSliderFrame(
      label: context.t('account.tint.level'),
      onPointer: (down) => _pointer = down,
      child: SliderTheme(
        data: _theme(context).copyWith(trackShape: LevelTrackShape(widget.hue)),
        child: Slider(
          value:
              (widget.level.clamp(0, 100) / _levelStep).roundToDouble() *
              _levelStep,
          min: 0,
          max: 100,
          divisions: 100 ~/ _levelStep,
          onChanged: (v) => widget.onChanged(v.round()),
          onChangeEnd: (v) =>
              widget.onChangeEnd?.call(v.round(), pointer: _pointer),
          semanticFormatterCallback: (v) => context.t(
            'account.tint.levelValue',
            variables: {
              'value': v.round(),
              'hint': context.t(LevelSlider.hintKey(v.round())),
            },
          ),
        ),
      ),
    );
  }
}

const _hueStep = 5;
const _levelStep = 5;

/// The height both sliders take: the thumb's touch target.
const kTintSliderHeight = 48.0;

SliderThemeData _theme(BuildContext context) =>
    SliderTheme.of(context).copyWith(
      trackHeight: 12,
      thumbShape: const RingThumbShape(),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
      overlayColor: AppColors.focusRing.withValues(alpha: 0.18),
      tickMarkShape: SliderTickMarkShape.noTickMark,
      // The track paints itself and never reads these — but they must not
      // both be transparent: the base shape then collapses the track to a
      // height of zero.
      activeTrackColor: AppColors.hairline,
      inactiveTrackColor: AppColors.hairline,
      // Shown as the value is spoken, not drawn: the colour is the label.
      showValueIndicator: ShowValueIndicator.never,
      thumbColor: Colors.white,
    );

/// Names a slider for a reader, tells it whether a pointer is on it, and
/// gives it its height. The visible caption beside it is excluded from the
/// semantics tree (see `tint_section.dart`), so the name is heard once.
class _TintSliderFrame extends StatelessWidget {
  const _TintSliderFrame({
    required this.label,
    required this.onPointer,
    required this.child,
  });

  final String label;
  final ValueChanged<bool> onPointer;
  final Widget child;

  @override
  // Merged, so the name and the slider are one node for a reader rather than
  // a named group around an unnamed control.
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      label: label,
      child: Listener(
        onPointerDown: (_) => onPointer(true),
        // Deferred: this listener hears the pointer go up before the slider's
        // drag recogniser does, and the slider's onChangeEnd must still see it.
        onPointerUp: (_) => scheduleMicrotask(() => onPointer(false)),
        onPointerCancel: (_) => scheduleMicrotask(() => onPointer(false)),
        child: SizedBox(height: kTintSliderHeight, child: child),
      ),
    ),
  );
}

/// The spectrum: every hue at the accent's lightness, at the chroma of the
/// level, in the order of the circle. The stops are the same for every frame
/// of a drag at one level, so they are kept per level.
class SpectrumTrackShape extends _GradientTrackShape {
  const SpectrumTrackShape(this.level);

  final int level;

  static final _stops = <int, List<Color>>{};

  /// One colour every ten degrees, in gamut, for [level].
  static List<Color> stopsFor(int level) => _stops.putIfAbsent(level, () {
    final c = 0.137 * TintPalette.chromaScale(level);
    return [
      for (var h = 0; h <= 360; h += 10) oklchFit(0.742, c, h.toDouble()),
    ];
  });

  @override
  List<Color> get colors => stopsFor(level);
}

/// White to the colour: the level track. Kept per hue.
class LevelTrackShape extends _GradientTrackShape {
  const LevelTrackShape(this.hue);

  final int hue;

  static final _stops = <int, List<Color>>{};

  static List<Color> stopsFor(int hue) => _stops.putIfAbsent(hue, () {
    final full = oklchFit(0.742, 0.137, hue.toDouble());
    final pale = oklchFit(
      0.742,
      0.137 * TintPalette.chromaScale(0),
      hue.toDouble(),
    );
    return [Colors.white, pale, full];
  });

  @override
  List<Color> get colors => stopsFor(hue);
}

/// A capsule track painted with a horizontal gradient and a hairline rim,
/// its shader reused while the stops and the rect stay the same.
abstract class _GradientTrackShape extends SliderTrackShape
    with BaseSliderTrackShape {
  const _GradientTrackShape();

  List<Color> get colors;

  static final _shaders = <(List<Color>, Rect, TextDirection), Shader>{};

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final stops = colors;
    final key = (stops, rect, textDirection);
    final shader = _shaders.putIfAbsent(key, () {
      if (_shaders.length > 16) _shaders.clear();
      return LinearGradient(
        colors: textDirection == TextDirection.rtl
            ? stops.reversed.toList()
            : stops,
      ).createShader(rect);
    });
    final radius = Radius.circular(rect.height / 2);
    final rrect = RRect.fromRectAndRadius(rect, radius);
    context.canvas.drawRRect(rrect, Paint()..shader = shader);
    context.canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.hairline,
    );
  }
}

/// iOS 27's thumb: a white ring with a soft shadow, 28 across; the touch
/// target is the overlay's 48.
class RingThumbShape extends SliderComponentShape {
  const RingThumbShape();

  static const double radius = 14;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
  }
}

/// The hues a drag ticks on: the shared palette hues the projects and labels
/// pick from, and the brand honey, rounded to the slider's five-degree grid
/// (79 ticks at 80).
final _hapticHues = {
  for (final h in [79, ...kLabelHues]) (h / _hueStep).round() * _hueStep,
};

/// A tick of the haptics when a drag reaches a named hue; [previous] keeps a
/// drag that rests on it from ticking every frame.
void tintSnapHaptic(int previous, int next) {
  if (previous == next) return;
  if (_hapticHues.contains(next)) HapticFeedback.selectionClick();
}
