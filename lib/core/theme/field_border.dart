import 'package:flutter/material.dart';

/// The app's field rim: a rounded rectangle that carries its label *inside* the
/// field rather than astride the rim.
///
/// Material has two shapes and each decides where the label goes. An outline
/// border cuts a gap in itself and centres the floating label on the rim —
/// which is right for a field with nothing behind it, and wrong for ours, which
/// are filled: half the glyphs then stood on the page and half on the fill, and
/// the seam between the two cut the word in two. An underline border floats the
/// label *into* the field, over its own fill, which is legible on any surface —
/// but it draws a single line instead of the rounded rim the design is made of.
///
/// So this takes the placement from one and the shape from the other:
/// [isOutline] is false, so the decorator puts the label inside the field and
/// reserves the room for it, and [paint] draws the rounded rim. The result is
/// the same two-line shape `FieldButton` has — a small caption above its value
/// — which is what the pickers beside these fields already look like.
@immutable
class HiveFieldBorder extends InputBorder {
  const HiveFieldBorder({
    super.borderSide = const BorderSide(),
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  final BorderRadius borderRadius;

  /// False on purpose — see the class doc. It is the whole point of this class.
  @override
  bool get isOutline => false;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.width);

  @override
  HiveFieldBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
  }) => HiveFieldBorder(
    borderSide: borderSide ?? this.borderSide,
    borderRadius: borderRadius ?? this.borderRadius,
  );

  @override
  HiveFieldBorder scale(double t) => HiveFieldBorder(
    borderSide: borderSide.scale(t),
    borderRadius: borderRadius * t,
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is HiveFieldBorder
      ? HiveFieldBorder(
          borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
          borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
        )
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is HiveFieldBorder
      ? HiveFieldBorder(
          borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
          borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
        )
      : super.lerpTo(b, t);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path()
    ..addRRect(
      borderRadius
          .resolve(textDirection)
          .toRRect(rect)
          .deflate(borderSide.width),
    );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.resolve(textDirection).toRRect(rect));

  /// The gap arguments belong to the outline border's cut-out and are ignored:
  /// the rim is drawn whole, because the label never crosses it.
  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    if (borderSide.style == BorderStyle.none) return;
    final outer = borderRadius.resolve(textDirection).toRRect(rect);
    canvas.drawRRect(outer.deflate(borderSide.width / 2), borderSide.toPaint());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HiveFieldBorder &&
          other.borderSide == borderSide &&
          other.borderRadius == borderRadius);

  @override
  int get hashCode => Object.hash(borderSide, borderRadius);
}
