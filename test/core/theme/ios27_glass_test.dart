import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/glass_chrome.dart';
import 'package:hinata/core/theme/tint_palette.dart';
import 'package:hinata/core/widgets/glass_panel.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  group('iOS 27 glass', () {
    test(
      'the neutral chrome is Apple\'s glass, clear and without the frost',
      () {
        for (final (chrome, apple) in [
          (kNavGlassLight, LiquidGlassSettings.ios27Light),
          (kNavGlassDark, LiquidGlassSettings.ios27Dark),
        ]) {
          // Frost is a blur pass per surface per scrolled frame; the rim stays.
          expect(chrome.frost, 0);
          expect(chrome.rimShade, apple.rimShade);
          expect(chrome.rimLight, apple.rimLight);
          expect(chrome.lensModel, GlassLensModel.paraxial);
          // No white tint: clear glass, not a milky film.
          expect(chrome.glassColor.a, 0);
        }
        for (final standard in [
          navGlass(false, standard: true),
          navGlass(true, standard: true),
        ]) {
          expect(standard.glassColor.a, 0);
          expect(standard.saturation, 1);
          expect(standard.ambientStrength, 0);
        }
        expect(navGlass(false), same(kNavGlassLight));
        expect(navGlass(true), same(kNavGlassDark));
      },
    );

    for (final dark in const [false, true]) {
      final mode = dark ? 'dark' : 'light';
      final base = dark
          ? LiquidGlassSettings.ios27Dark
          : LiquidGlassSettings.ios27Light;

      test('tinted surfaces share the rim and the lens ($mode)', () {
        for (final settings in [
          accentFrost(dark),
          liquidGlassPanelSettings(
            glassFill: Colors.white,
            dark: dark,
            standard: false,
          ),
        ]) {
          expect(settings.lensModel, GlassLensModel.paraxial);
          expect(settings.rimShade, base.rimShade);
          expect(settings.rimLight, base.rimLight);
          expect(settings.lightAngle, base.lightAngle);
          expect(settings.thickness, base.thickness);
        }
      });

      test('the honey keeps its colour and does not frost ($mode)', () {
        final amber = accentFrost(dark);
        expect(amber.frost, 0);
        expect(amber.saturation, 1);
        expect(amber.glassColor.a, greaterThan(0));
      });

      test('panels frost on premium and leave the shadow to themselves '
          '($mode)', () {
        final panel = liquidGlassPanelSettings(
          glassFill: Colors.white,
          dark: dark,
          standard: false,
        );
        expect(panel.frost, base.frost);
        expect(panel.shadowElevation, 0);
      });
    }

    test('panels render on standard by default, for their cost', () {
      expect(kPanelGlassQuality, GlassQuality.standard);
      final panel = liquidGlassPanelSettings(
        glassFill: Colors.white,
        dark: false,
      );
      expect(panel.frost, 0);
      expect(panel.lightIntensity, greaterThan(0));
    });

    test('surfaces pinned to standard keep a lit edge', () {
      for (final dark in const [false, true]) {
        // The standard shader cannot draw the iOS 27 rim, so the older white
        // specular stays on there.
        expect(navGlass(dark, standard: true).lightIntensity, greaterThan(0));
        expect(
          accentFrost(dark, standard: true).lightIntensity,
          greaterThan(0),
        );
        expect(
          liquidGlassPanelSettings(
            glassFill: Colors.white,
            dark: dark,
            standard: true,
          ).lightIntensity,
          greaterThan(0),
        );
      }
    });

    test('premium is the default tier, since only premium draws it', () {
      final theme = ios27GlassTheme();
      expect(theme.light.quality, GlassQuality.premium);
      expect(theme.dark.quality, GlassQuality.premium);
    });

    test('widgets without settings wear the same material', () {
      final theme = ios27GlassTheme();
      final light = theme.light.settings!.applyTo(const LiquidGlassSettings());
      final dark = theme.dark.settings!.applyTo(const LiquidGlassSettings());
      expect(light.rimLight, LiquidGlassSettings.ios27Light.rimLight);
      expect(light.frost, 0);
      expect(dark.rimShade, LiquidGlassSettings.ios27Dark.rimShade);
      expect(dark.lensModel, GlassLensModel.paraxial);
    });
  });

  group('the tint (HIN-150)', () {
    tearDown(() => AppColors.palette = TintPalette.standard);

    test('the chrome keeps its optics and takes the palette colour', () {
      final tinted = TintPalette.of(
        const TintPreferences(style: TintStyle.tinted, hue: 300, level: 100),
      );
      AppColors.palette = tinted;
      for (final dark in const [false, true]) {
        final base = dark ? kNavGlassDark : kNavGlassLight;
        final chrome = navGlass(dark);
        expect(chrome.glassColor, dark ? tinted.chromeTintDark : tinted.chromeTintLight);
        expect(chrome.glassColor.a, greaterThan(0));
        // Everything but the colour is the neutral chrome: no frost pass, same
        // rim and lens, the tint is a uniform.
        expect(chrome.frost, base.frost);
        expect(chrome.blur, base.blur);
        expect(chrome.rimShade, base.rimShade);
        expect(chrome.rimLight, base.rimLight);
        expect(chrome.lensModel, base.lensModel);
        expect(chrome.thickness, base.thickness);
        expect(chrome.saturation, base.saturation);
        final standard = navGlass(dark, standard: true);
        expect(standard.glassColor, chrome.glassColor);
        expect(
          standard.thickness,
          (dark ? kNavGlassStandardDark : kNavGlassStandardLight).thickness,
        );
      }
    });

    test('level 0 and the standard brand are the clear chrome, same instance', () {
      for (final prefs in const [
        TintPreferences.standard,
        TintPreferences(style: TintStyle.tinted, hue: 300, level: 0),
      ]) {
        AppColors.palette = TintPalette.of(prefs);
        expect(navGlass(false), same(kNavGlassLight));
        expect(navGlass(true), same(kNavGlassDark));
        expect(navGlass(true, standard: true), same(kNavGlassStandardDark));
      }
    });

    test('panels stay neutral whatever the tint', () {
      AppColors.palette = TintPalette.of(
        const TintPreferences(style: TintStyle.tinted, hue: 20, level: 100),
      );
      final panel = liquidGlassPanelSettings(
        glassFill: Colors.white,
        dark: false,
        standard: false,
      );
      expect(panel.glassColor, Colors.white);
      expect(ios27GlassTheme().light.settings!.glassColor!.a, 0);
    });
  });
}
