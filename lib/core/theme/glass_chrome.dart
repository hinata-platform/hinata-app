import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app_colors.dart';

// Glass presets for the app's floating chrome.
//
// They live in core rather than beside their first user because more than one
// surface has to refract identically to read as the same material — the mobile
// nav is two separate floating elements (the tab pill and the detached search
// button) and the page headers add a third.
//
// Since HIN-130 the material is iOS 27's `glassEffect(.regular)`, as
// liquid_glass_widgets 1.8.0 measured it against SwiftUI: a frost cloud the
// content still shows through, a half-point rim shade and a rim light instead
// of the older white specular stroke, and a paraxial lens that folds the rim
// band evenly. The neutral chrome takes Apple's presets without their frost; every
// tinted surface (the honey of a primary action, the near-solid composer and
// menus) keeps its own colour but shares the rim and the lens through
// [ios27Glass], so the app reads as one material in both themes.
//
// The terms only render at `GlassQuality.premium` on Impeller. Standard and
// minimal quality, and the web, keep their lighter fallbacks untouched.

/// Neutral chrome, dark: Apple's iOS 27 regular glass in the dark appearance,
/// without its frost (see [_withoutFrost]).
final kNavGlassDark = _withoutFrost(LiquidGlassSettings.ios27Dark);

/// Neutral chrome, light: Apple's iOS 27 regular glass in the light appearance,
/// without its frost (see [_withoutFrost]).
final kNavGlassLight = _withoutFrost(LiquidGlassSettings.ios27Light);

const _chromeBlur = 3.0;

/// No tint at all: the chrome is clear glass in both themes.
const _clearGlass = Color(0x00FFFFFF);

/// [preset] without the frost pass and without its white tint, for the chrome
/// that sits over scrolling content: clear glass, no milky veil.
///
/// Measured on the iPhone simulator with real frames (hin-130-review/perf): the
/// frost is a blur pass of its own on every surface, and the bar, its round
/// buttons, the docked toolbar and the tab pill each paid it on every scrolled
/// frame. Scrolling the issues list went from 5.2 to 9.2 ms at the 90th
/// percentile, past a 120 Hz display's 8.3 ms. Without the frost, and with the
/// chrome's own blur of 3 in its place, it is at 5.7 ms, and the rim shade, rim
/// light and lens that make the glass read as
/// iOS 27 stay. Menus, popovers and sheets keep their frost: they open over
/// still content, where the pass is paid once, not per frame.
///
/// The preset's tint (53 % white in light, 12 % in dark) is dropped too: over
/// the warm paper it read as a milky film on every bar and button. What is
/// behind the chrome now shows through in its own colours, and the rim shade,
/// rim light and lens alone draw the edge.
LiquidGlassSettings _withoutFrost(LiquidGlassSettings preset) =>
    LiquidGlassSettings(
      glassColor: _clearGlass,
      saturation: preset.saturation,
      // The blur the chrome always had. The preset's own 0.6 counts on the
      // frost to diffuse what is behind; without it, a list row's text stood
      // sharp behind the tab labels, text on text.
      blur: _chromeBlur,
      thickness: preset.thickness,
      refractiveIndex: preset.refractiveIndex,
      lensModel: preset.lensModel,
      lightAngle: preset.lightAngle,
      lightIntensity: 0,
      fresnelStrength: 0,
      chromaticAberration: 0,
      edgeAbsorption: preset.edgeAbsorption,
      rimShade: preset.rimShade,
      rimShadeEnds: preset.rimShadeEnds,
      rimLight: preset.rimLight,
    );

/// The optics of the standard quality tier, which the iOS 27 terms do not
/// reach: its lightweight shader knows no frost, rim shade or rim light, and
/// the iOS 27 presets switch the older white specular off in their favour.
/// Handed the iOS 27 settings, a surface pinned to standard lost its lit edge
/// and kept only the thicker lens, which read as a grey band inside the rim.
/// Surfaces that stay on standard for their cost keep this recipe.
const _stdThickness = 30.0;
const _stdBlur = 3.0;
const _stdChromaticAberration = 0.3;
const _stdLightIntensity = 0.6;
const _stdRefractiveIndex = 1.59;
const _stdAmbientStrength = 1.0;

/// The neutral chrome on the standard tier is clear like the premium one: no
/// white tint, no desaturation and no ambient lift, the three things that
/// turned it into frosted milk. The amber button keeps the tuned recipe above.
const _stdClearSaturation = 1.0;
const _stdClearAmbientStrength = 0.0;

/// 0.75π — the key light the standard tier is lit from.
const _stdLightAngle = 2.356194490192345;

/// Neutral chrome on the standard tier, dark.
const kNavGlassStandardDark = LiquidGlassSettings(
  thickness: _stdThickness,
  blur: _stdBlur,
  chromaticAberration: _stdChromaticAberration,
  lightIntensity: _stdLightIntensity,
  refractiveIndex: _stdRefractiveIndex,
  saturation: _stdClearSaturation,
  ambientStrength: _stdClearAmbientStrength,
  lightAngle: _stdLightAngle,
  glassColor: _clearGlass,
);

/// Neutral chrome on the standard tier, light.
const kNavGlassStandardLight = LiquidGlassSettings(
  thickness: _stdThickness,
  blur: _stdBlur,
  chromaticAberration: _stdChromaticAberration,
  lightIntensity: _stdLightIntensity,
  refractiveIndex: _stdRefractiveIndex,
  saturation: _stdClearSaturation,
  ambientStrength: _stdClearAmbientStrength,
  lightAngle: _stdLightAngle,
  glassColor: _clearGlass,
);

/// iOS 27 glass in the app's own [glassColor].
///
/// The optics — thickness, lens, rim shade and rim light, the light from above
/// in light mode and from below in dark — are those of [kNavGlassLight] and
/// [kNavGlassDark], so a tinted surface sits next to the neutral chrome as the
/// same material. What a surface changes is its colour, how much of the colour
/// behind it survives ([saturation]), and whether it frosts at all: a surface
/// that is nearly opaque anyway gains nothing from a frost pass but its cost,
/// and the honey of a primary action would only be washed out by one.
LiquidGlassSettings ios27Glass({
  required bool dark,
  required Color glassColor,
  double saturation = 1,
  bool frost = false,
  double shadowElevation = 1,
}) {
  // The full presets, frost terms included: a panel that frosts wants Apple's.
  final base = dark
      ? LiquidGlassSettings.ios27Dark
      : LiquidGlassSettings.ios27Light;
  return LiquidGlassSettings(
    glassColor: glassColor,
    saturation: saturation,
    blur: base.blur,
    blurWeight: frost ? base.blurWeight : 1,
    frost: frost ? base.frost : 0,
    frostOpacity: base.frostOpacity,
    frostClamp: base.frostClamp,
    frostWeight: base.frostWeight,
    thickness: base.thickness,
    refractiveIndex: base.refractiveIndex,
    lensModel: base.lensModel,
    lightAngle: base.lightAngle,
    lightIntensity: 0,
    fresnelStrength: 0,
    chromaticAberration: 0,
    edgeAbsorption: base.edgeAbsorption,
    rimShade: base.rimShade,
    rimShadeEnds: base.rimShadeEnds,
    rimLight: base.rimLight,
    // The package's own shadow; a surface that paints its own clipped shadow
    // passes 0.
    shadowElevation: shadowElevation,
  );
}

/// The frost that sits *on top of* the amber ground of a primary action.
///
/// It shares the chrome's optics but not its colour handling, and the reason
/// is the whole point of this preset. Neutral chrome frosts what it refracts
/// and lays a white cloud over it, which is right for a surface whose job is to
/// disappear. Over amber it is exactly wrong: the colour *is* the design, and a
/// white wash leaves the beige button that shipped in 10.3.2. So: saturation
/// left at 1, no frost, and the veil in amber rather than white — a white one
/// dilutes the ground instead of sitting in it.
///
/// **The veil is much heavier over a dark page, and that is not a taste call.**
/// Measured on the running app: the button is only ~64% opaque, so a third of
/// whatever is behind it comes through. Over the light canvas that is free
/// brightness; over the dark one it drags the honey down to 0.72 value where
/// light reads 0.82, which is the "washed out" everyone sees and nobody can
/// name. Brightening the ground cannot fix it — the arithmetic asks for a red
/// channel of 295. What fixes it is making the third that comes through *amber
/// too*, which is this alpha. It lands at RGB(208,154,51) against light's
/// (209,156,54).
LiquidGlassSettings amberFrost(bool dark, {bool standard = false}) => standard
    ? _amberFrostStandard(dark)
    : ios27Glass(
        dark: dark,
        // Saturation stays at 1 and there is no frost: over amber the colour
        // *is* the design, and a white frost cloud would dilute it just as the
        // old white veil did. The iOS 27 rim light takes over from the white
        // specular stroke that bloomed into a grey reif over a dark page.
        glassColor: _amberVeil(dark),
      );

Color _amberVeil(bool dark) =>
    dark ? const Color(0x59FFBC3B) : const Color(0x1FD9A032);

/// [amberFrost] on the standard tier: the white specular rim is a stroke drawn
/// with BlendMode.overlay, so it wants opposite things over the two pages.
/// Over a near-black page it blooms into a grey reif and has to stay narrow
/// and faint; over the light page there is nothing to bloom against and the
/// full stroke is what gives the disc its lit edge.
LiquidGlassSettings _amberFrostStandard(bool dark) => LiquidGlassSettings(
  thickness: _stdThickness,
  blur: _stdBlur,
  chromaticAberration: _stdChromaticAberration,
  lightIntensity: dark ? 0.45 : 0.9,
  refractiveIndex: _stdRefractiveIndex,
  // Left at 1: more blew red and green out to a glowing disc in dark.
  saturation: 1,
  ambientStrength: dark ? 0.3 : _stdAmbientStrength,
  lightAngle: _stdLightAngle,
  glassColor: _amberVeil(dark),
);

/// The honey-amber ground a primary action's glass floats on. Same three stops
/// as the composer's send button, so the app's two amber circles are one thing.
const kAmberGround = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFE7B24A), AppColors.accent, AppColors.accentStrong],
);

/// The same ground, lifted for a dark page.
///
/// Measured, not eyeballed: the glass renders the identical ground about 22%
/// darker over a dark page than over a light one — the same hue at the same
/// saturation, every channel multiplied by roughly 0.78. Light does not need
/// the lift; dark does, or the primary action sits there dimmer than the page
/// expects it to be.
///
/// These are the light stops with **value raised 20% and saturation left
/// alone** — not paler ambers, which is the obvious way to brighten a colour
/// and the wrong one. The first attempt walked the gradient up to lighter
/// honeys and lost a tenth of the saturation doing it, because a lighter amber
/// simply is a less saturated one. Brightness and saturation are separate axes
/// and only one of them was the problem.
const kAmberGroundDark = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFFC452), Color(0xFFFFBC3B), Color(0xFFDE9D25)],
);

LinearGradient amberGround(bool dark) => dark ? kAmberGroundDark : kAmberGround;

/// The ink that sits on amber — the same near-black the solid accent button
/// uses for its label, so the glyph reads identically whichever form the button
/// is in.
const kOnAmber = Color(0xFF2A2410);

/// The neutral chrome for [dark], on the premium tier unless [standard].
LiquidGlassSettings navGlass(bool dark, {bool standard = false}) => standard
    ? (dark ? kNavGlassStandardDark : kNavGlassStandardLight)
    : (dark ? kNavGlassDark : kNavGlassLight);

/// A round Liquid Glass button, the shape the app's floating chrome is made of.
///
/// The shape is a superellipse with `radius = size / 2` — a perfect circle — and
/// deliberately not the package's `LiquidOval`. An oval glass surface is clipped
/// with `ClipPath`, which the engine cannot forward to the descendant
/// `BackdropFilter`, so the blur stays a rectangle behind the circle and its
/// vertical edges leak as faint seams beside the button. `ClipRRect`, which the
/// superellipse uses, forwards the clip and kills the halo.
///
/// Pinned to [GlassQuality.standard]: the lightweight shader renders correctly
/// over a scrolling page and on rotation, where the premium pipeline does not.
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 46,
    this.iconSize = 20,
    this.amber = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  /// Honey-amber tint, for a primary action. Neutral chrome otherwise.
  final bool amber;

  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    Widget button = GlassButton(
      icon: Icon(icon, size: iconSize),
      // The tooltip names it for a pointer; a screen reader needs the label.
      label: tooltip ?? '',
      onTap: onTap ?? () {},
      enabled: onTap != null,
      width: size,
      height: size,
      iconSize: iconSize,
      shape: LiquidRoundedSuperellipse(borderRadius: size / 2),
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: amber
          ? amberFrost(dark, standard: true)
          : navGlass(dark, standard: true),
      iconColor: amber
          ? kOnAmber
          : (dark ? AppColors.inkDark : AppColors.inkLight),
      glowColor: AppColors.accent,
      // Keep the tactile press-scale but damp the liquid drag-follow so an
      // isolated button doesn't over-stretch on tap.
      stretch: 0.15,
      // A pressed GlassButton lays a flat white sheet over its whole surface —
      // 0.3 opaque in light, 0.14 in dark. On neutral chrome that is the iOS 26
      // lift and it is right. On amber it is a bleach: at 0.3 the honey button
      // turns beige for as long as the finger is down, which is what shipped in
      // 10.3.2 and what a screenshot taken mid-tap shows. An explicit value is
      // used unchanged in both themes, so this is one number: enough lift to
      // answer the touch, not enough to take the colour with it. The press
      // scale and the glow carry the rest of the feedback.
      ambientBaseLight: amber ? 0.10 : null,
    );
    if (amber) {
      button = Stack(
        alignment: Alignment.center,
        children: [
          // The ground the glass refracts. IgnorePointer so the glass keeps the
          // whole gesture — the ground is paint, not a target.
          IgnorePointer(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: amberGround(dark),
                boxShadow: [
                  BoxShadow(
                    // An amber halo around an amber disc reads as a soft edge,
                    // and over a dark page it is the only thing near it with
                    // any light in it — so it spreads and the button loses its
                    // outline. Over a light page the same glow is invisible.
                    // Hence: barely there in dark, unchanged in light.
                    color: AppColors.accent.withValues(
                      alpha: dark ? 0.16 : 0.45,
                    ),
                    blurRadius: dark ? 9 : 14,
                    spreadRadius: -5,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
            ),
          ),
          button,
        ],
      );
    }
    final label = tooltip;
    return label == null ? button : Tooltip(message: label, child: button);
  }
}

/// The iOS 27 material for every glass widget that does not bring its own
/// settings — the tab bar, switches, sliders, sheets. Handed to
/// `LiquidGlassWidgets.wrap` once, at the top of the app.
///
/// Premium is the default tier with it, because only premium renders the
/// material; a widget that asks for less keeps asking, and the adaptive
/// ceiling (`kGlassCeiling`) still steps a device down that cannot keep up.
GlassThemeData ios27GlassTheme() => GlassThemeData(
  light: GlassThemeVariant(
    settings: _themeSettings(kNavGlassLight),
    quality: GlassQuality.premium,
  ),
  dark: GlassThemeVariant(
    settings: _themeSettings(kNavGlassDark),
    quality: GlassQuality.premium,
  ),
);

GlassThemeSettings _themeSettings(LiquidGlassSettings s) => GlassThemeSettings(
  glassColor: s.glassColor,
  thickness: s.thickness,
  blur: s.blur,
  blurWeight: s.blurWeight,
  frost: s.frost,
  frostOpacity: s.frostOpacity,
  frostClamp: s.frostClamp,
  frostWeight: s.frostWeight,
  chromaticAberration: s.chromaticAberration,
  lightAngle: s.lightAngle,
  lightIntensity: s.lightIntensity,
  fresnelStrength: s.fresnelStrength,
  refractiveIndex: s.refractiveIndex,
  saturation: s.saturation,
  edgeAbsorption: s.edgeAbsorption,
  rimShade: s.rimShade,
  rimShadeEnds: s.rimShadeEnds,
  rimLight: s.rimLight,
  lensModel: s.lensModel,
);
