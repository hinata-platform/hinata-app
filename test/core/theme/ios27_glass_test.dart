import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/glass_chrome.dart';
import 'package:hinata/core/widgets/glass_panel.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  group('iOS 27 glass', () {
    test('the neutral chrome is Apple\'s regular glass in both themes', () {
      expect(kNavGlassLight, LiquidGlassSettings.ios27Light);
      expect(kNavGlassDark, LiquidGlassSettings.ios27Dark);
      expect(navGlass(false), same(kNavGlassLight));
      expect(navGlass(true), same(kNavGlassDark));
    });

    for (final dark in const [false, true]) {
      final mode = dark ? 'dark' : 'light';
      final base = dark
          ? LiquidGlassSettings.ios27Dark
          : LiquidGlassSettings.ios27Light;

      test('tinted surfaces share the rim and the lens ($mode)', () {
        for (final settings in [
          amberFrost(dark),
          liquidGlassPanelSettings(glassFill: Colors.white, dark: dark),
        ]) {
          expect(settings.lensModel, GlassLensModel.paraxial);
          expect(settings.rimShade, base.rimShade);
          expect(settings.rimLight, base.rimLight);
          expect(settings.lightAngle, base.lightAngle);
          expect(settings.thickness, base.thickness);
        }
      });

      test('the honey keeps its colour and does not frost ($mode)', () {
        final amber = amberFrost(dark);
        expect(amber.frost, 0);
        expect(amber.saturation, 1);
        expect(amber.glassColor.a, greaterThan(0));
      });

      test('panels frost and leave the shadow to themselves ($mode)', () {
        final panel = liquidGlassPanelSettings(
          glassFill: Colors.white,
          dark: dark,
        );
        expect(panel.frost, base.frost);
        expect(panel.shadowElevation, 0);
      });
    }

    test('surfaces pinned to standard keep a lit edge', () {
      for (final dark in const [false, true]) {
        // The standard shader cannot draw the iOS 27 rim, so the older white
        // specular stays on there.
        expect(navGlass(dark, standard: true).lightIntensity, greaterThan(0));
        expect(amberFrost(dark, standard: true).lightIntensity, greaterThan(0));
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
      expect(light.frost, LiquidGlassSettings.ios27Light.frost);
      expect(dark.rimShade, LiquidGlassSettings.ios27Dark.rimShade);
      expect(dark.lensModel, GlassLensModel.paraxial);
    });
  });
}
