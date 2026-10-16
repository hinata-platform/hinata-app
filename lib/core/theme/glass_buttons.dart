import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_type.dart';
import 'tint_palette.dart';

/// The app's buttons in the glass language: capsules lit from above.
///
/// One source for every [FilledButton], [OutlinedButton] and [TextButton] —
/// the theme hands these out, so a call site writes `FilledButton(...)` and
/// gets the capsule. A call site still sets its own fill (danger, a module
/// colour) and keeps the light: the gloss is a white wash *over* whatever fill
/// the button resolved, not a fill of its own.
///
/// None of them is refractive glass. Buttons sit on cards, in dialogs and
/// inside glass bars, and glass inside glass doubles the distortion; they are
/// the jewels set into the surface, the way iOS sets its tinted capsules.
abstract final class GlassButtons {
  /// The height a capsule keeps at least: the touch minimum.
  static const double minHeight = 44;

  /// The primary action: an accent capsule with the primary as ink (honey
  /// and navy in the standard brand, 5.7:1), in both themes. Navy on the dark
  /// glass was 1.2:1. The palette's values are captured here, not read through
  /// the getters, so a style built for one palette stays that palette's.
  static ButtonStyle filled(Brightness brightness, TintPalette palette) {
    final dark = brightness == Brightness.dark;
    final inkSoft = dark ? AppColors.inkSoftDark : AppColors.inkSoftLight;
    final accent = palette.accent;
    final primary = palette.primary;
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(minHeight, minHeight)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      ),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      // The rim of light. As [ButtonStyle.side], not on the shape: a call
      // site that sets its own side replaces it instead of drawing a second.
      side: WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: Colors.white.withValues(
            alpha: states.contains(WidgetState.disabled) ? 0.2 : 0.55,
          ),
          width: 0.8,
        ),
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? accent.withValues(alpha: 0.24)
            : accent,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? inkSoft : primary,
      ),
      overlayColor: WidgetStatePropertyAll(primary.withValues(alpha: 0.08)),
      elevation: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? 0 : 2,
      ),
      shadowColor: WidgetStatePropertyAll(
        accent.withValues(alpha: dark ? 0.45 : 0.5),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontWeight: FontWeight.w700, fontSize: AppType.label),
      ),
      backgroundBuilder: gloss,
    );
  }

  /// The secondary action: a frosted capsule, a clear pane with a rim of light.
  static ButtonStyle outlined(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final ink = dark ? AppColors.inkDark : AppColors.inkLight;
    final inkSoft = dark ? AppColors.inkSoftDark : AppColors.inkSoftLight;
    final hairline = dark ? AppColors.hairlineDark : AppColors.hairlineLight;
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(minHeight, minHeight)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      ),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      side: WidgetStatePropertyAll(
        BorderSide(
          color: dark ? Colors.white.withValues(alpha: 0.16) : hairline,
          width: 0.8,
        ),
      ),
      backgroundColor: WidgetStatePropertyAll(
        dark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.62),
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? inkSoft : ink,
      ),
      overlayColor: WidgetStatePropertyAll(ink.withValues(alpha: 0.06)),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontWeight: FontWeight.w600, fontSize: AppType.label),
      ),
      backgroundBuilder: gloss,
    );
  }

  /// A quiet action: no surface until hovered or pressed, then a capsule wash.
  static ButtonStyle text(Brightness brightness, TintPalette palette) {
    final dark = brightness == Brightness.dark;
    final ink = dark ? palette.accent : palette.primary;
    return ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      foregroundColor: WidgetStatePropertyAll(ink),
      overlayColor: WidgetStatePropertyAll(ink.withValues(alpha: 0.08)),
    );
  }

  /// Light falling on the capsule from above: a white wash that fades out by
  /// the middle, over whatever fill the button resolved. Disabled buttons get
  /// none — a lit button reads as one you can press.
  static Widget gloss(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) {
    if (states.contains(WidgetState.disabled)) return child ?? const SizedBox();
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.26),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.6],
        ),
      ),
      child: child,
    );
  }
}
