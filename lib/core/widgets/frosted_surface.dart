import 'package:flutter/material.dart';

/// A translucent "frosted glass" surface for controls that sit ON TOP of an
/// existing single blur — e.g. the compact app bar's one `ProgressiveBlur`. It
/// carries NO `BackdropFilter` of its own: it relies on that blur showing
/// through its semi-transparent fill, then adds the hairline rim + specular
/// wash that read as a glass edge. Keeping the blur in ONE place is what keeps
/// the surface crisp — nested backdrop sampling pixelates on web/Skia.
///
/// This is the web / non-Impeller counterpart to the package's own-layer
/// `GlassContainer`/`GlassButton`: on native those render real refractive glass
/// (Impeller samples the composited backdrop cleanly), while this frosted
/// surface is used wherever a *second* backdrop sample must be avoided.
///
/// Mirrors the shell's private `_FrostedSurface` (app bar bell/settings/back);
/// promoted here so on-blur controls outside the shell can share the same look.
class FrostedSurface extends StatelessWidget {
  const FrostedSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    required this.dark,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        // Light frost lift in dark, a brighter wash in light — translucent so
        // the progressive blur behind stays visible through the surface.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0x33FFFFFF), Color(0x1FFFFFFF)]
              : const [Color(0x6BFFFFFF), Color(0x4DFFFFFF)],
        ),
        border: Border.all(
          color: dark ? const Color(0x40FFFFFF) : const Color(0x66FFFFFF),
          width: 0.6,
        ),
      ),
      child: child,
    );
  }
}
