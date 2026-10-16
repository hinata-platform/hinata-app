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
/// the colour, both thick glass capsules with a thumb in the chosen colour.
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
          TintPalette.accentFor(widget.hue, widget.level),
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
        data: _theme(
          context,
          TintPalette.accentFor(widget.hue, widget.level),
        ).copyWith(trackShape: LevelTrackShape(widget.hue)),
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

SliderThemeData _theme(BuildContext context, Color thumb) =>
    SliderTheme.of(context).copyWith(
      trackHeight: GlassThumbShape.radius * 2 - 6,
      thumbShape: const GlassThumbShape(),
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
      // The thumb is filled with the colour it stands on, as on iOS.
      thumbColor: thumb,
    );

/// Names a slider for a reader, tells it whether a pointer is on it, and
/// gives it its height. The panel shows no caption beside it, so this is
/// the slider's only name.
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

  /// One colour every ten degrees for [level]: the accent each hue gives,
  /// so the track promises exactly what the tint will be.
  static List<Color> stopsFor(int level) => _stops.putIfAbsent(level, () {
    return [for (var h = 0; h <= 360; h += 10) TintPalette.accentFor(h, level)];
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
    return [
      Colors.white,
      TintPalette.accentFor(hue, 0),
      TintPalette.accentFor(hue, 100),
    ];
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
    final canvas = context.canvas;
    canvas.drawRRect(rrect, Paint()..shader = shader);
    // Glass over the colour: light from above on the upper half, a shade
    // along the bottom, and a bright rim, as the capsules in iOS 27's sheet.
    canvas.save();
    canvas.clipRRect(rrect);
    final upper = Rect.fromLTWH(
      rect.left,
      rect.top,
      rect.width,
      rect.height * 0.55,
    );
    canvas.drawRect(
      upper,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.38),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(upper),
    );
    final lower = Rect.fromLTWH(
      rect.left,
      rect.top + rect.height * 0.6,
      rect.width,
      rect.height * 0.4,
    );
    canvas.drawRect(
      lower,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.10),
          ],
        ).createShader(lower),
    );
    canvas.restore();
    canvas.drawRRect(
      rrect.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.55),
    );
    // A hairline outside the rim, so the white end of the level track keeps
    // an edge on light paper.
    canvas.drawRRect(
      rrect.inflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.hairline,
    );
  }
}

/// iOS 27's thumb: a disc in the colour under it inside a thick white ring,
/// lifted by a soft shadow, 26 across; the touch target is the overlay's 48.
class GlassThumbShape extends SliderComponentShape {
  const GlassThumbShape();

  static const double radius = 13;

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
    // Grows a little while held, as the iOS thumb does.
    final r = radius * (1 + 0.08 * activationAnimation.value);
    canvas.drawCircle(
      center.translate(0, 1.5),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(center, r, Paint()..color = Colors.white);
    final fill = sliderTheme.thumbColor ?? Colors.white;
    final inner = r - 3;
    canvas.drawCircle(
      center,
      inner,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.45),
          colors: [Color.lerp(fill, Colors.white, 0.22)!, fill],
        ).createShader(Rect.fromCircle(center: center, radius: inner)),
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
