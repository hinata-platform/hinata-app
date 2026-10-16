import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:hinata/core/theme/glass_chrome.dart';
import 'package:hinata/core/theme/tint_palette.dart';

void main() {
  tearDown(() {
    AppColors.palette = TintPalette.standard;
    AppColors.brightness = Brightness.light;
  });

  test('brand tokens read the active palette', () {
    expect(AppColors.accent, const Color(0xFFD9A032));
    expect(AppColors.primary, const Color(0xFF2D2B55));
    final tinted = TintPalette.of(
      const TintPreferences(style: TintStyle.tinted, hue: 200, level: 100),
    );
    AppColors.palette = tinted;
    expect(AppColors.accent, tinted.accent);
    expect(AppColors.primary, tinted.primary);
    expect(AppColors.rail, tinted.rail);
    expect(AppColors.accentInk, tinted.accentText);
    expect(AppColors.focusRing, tinted.focusRingLight);
    expect(AppColors.stateBorder, tinted.stateBorderLight);
    AppColors.brightness = Brightness.dark;
    expect(AppColors.accentInk, tinted.accent);
    expect(AppColors.focusRing, tinted.focusRingDark);
    expect(AppColors.brandInk, tinted.railInk);
    expect(AppColors.accentGround(true), tinted.accentGroundDark);
    expect(AppColors.onAccent, tinted.onAccent);
  });

  test('themeKey changes with brightness and with the palette', () {
    final a = AppColors.themeKey;
    AppColors.brightness = Brightness.dark;
    final b = AppColors.themeKey;
    AppColors.palette = TintPalette.of(
      const TintPreferences(style: TintStyle.tinted, hue: 10, level: 50),
    );
    final c = AppColors.themeKey;
    expect(a, isNot(b));
    expect(b, isNot(c));
  });

  test('the theme takes the palette it is given', () {
    final tinted = TintPalette.of(
      const TintPreferences(style: TintStyle.tinted, hue: 120, level: 100),
    );
    expect(AppTheme.light().colorScheme.secondary, const Color(0xFFD9A032));
    expect(
      AppTheme.light(palette: tinted).colorScheme.secondary,
      tinted.accent,
    );
    expect(AppTheme.dark(palette: tinted).colorScheme.primary, tinted.accent);
    expect(AppTheme.light(palette: tinted).colorScheme.primary, tinted.primary);
  });

  test('the nav chrome takes the tint, and stays clear at level 0', () {
    expect(navGlass(false), same(kNavGlassLight));
    AppColors.palette = TintPalette.of(
      const TintPreferences(style: TintStyle.tinted, hue: 300, level: 0),
    );
    expect(navGlass(false), same(kNavGlassLight));
    expect(navGlass(true, standard: true), same(kNavGlassStandardDark));
    final tinted = TintPalette.of(
      const TintPreferences(style: TintStyle.tinted, hue: 300, level: 100),
    );
    AppColors.palette = tinted;
    expect(navGlass(false).glassColor, tinted.chromeTintLight);
    expect(navGlass(true).glassColor, tinted.chromeTintDark);
    expect(navGlass(true).rimLight, kNavGlassDark.rimLight);
    expect(navGlass(false, standard: true).glassColor, tinted.chromeTintLight);
    expect(AppColors.accentGround(true), tinted.accentGroundDark);
    expect(accentFrost(false).glassColor, tinted.accentVeilLight);
  });
}
