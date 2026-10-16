import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/contrast.dart';
import 'package:hinata/core/theme/hue_colors.dart';
import 'package:hinata/core/theme/tint_palette.dart';

void main() {
  group('TintPalette.standard', () {
    test('is today\'s brand, byte for byte', () {
      final p = TintPalette.standard;
      expect(p.accent, const Color(0xFFD9A032));
      expect(p.accentStrong, const Color(0xFFB9831F));
      expect(p.accentLine, const Color(0xFFE4CE96));
      expect(p.accentDeep, const Color(0xFF946A16));
      expect(p.accentText, const Color(0xFF7A5410));
      expect(p.accentSoftLight, const Color(0xFFF3E9D2));
      expect(p.accentSoftDark, const Color(0x29D9A032));
      expect(p.primary, const Color(0xFF2D2B55));
      expect(p.primaryDeep, const Color(0xFF1E1C3A));
      expect(p.rail, const Color(0xFF211F3D));
      expect(p.rail2, const Color(0xFF1A1830));
      expect(p.railInk, const Color(0xFFC9C7E0));
      expect(p.railFaint, const Color(0xFF8A88A7));
      expect(p.onAccent, const Color(0xFF2A2410));
      expect(p.accentGroundLight.colors, const [
        Color(0xFFE7B24A),
        Color(0xFFD9A032),
        Color(0xFFB9831F),
      ]);
      expect(p.accentGroundDark.colors, const [
        Color(0xFFFFC452),
        Color(0xFFFFBC3B),
        Color(0xFFDE9D25),
      ]);
      expect(p.accentVeilLight, const Color(0x1FD9A032));
      expect(p.accentVeilDark, const Color(0x59FFBC3B));
      // Clear glass, as today.
      expect(p.chromeTintLight.a, 0);
      expect(p.chromeTintDark.a, 0);
    });

    test('is what DEFAULT style and level 0 glass resolve to', () {
      expect(
        identical(
          TintPalette.of(const TintPreferences(style: TintStyle.defaultStyle)),
          TintPalette.standard,
        ),
        isTrue,
      );
      final clear = TintPalette.of(
        const TintPreferences(style: TintStyle.tinted, hue: 200, level: 0),
      );
      expect(clear.chromeTintLight.a, 0);
      expect(clear.chromeTintDark.a, 0);
    });
  });

  group('every pair meets its minimum', () {
    for (var level = 0; level <= 100; level += 5) {
      test('level $level, all 360 hues', () {
        for (var hue = 0; hue < 360; hue++) {
          final p = TintPalette.of(
            TintPreferences(style: TintStyle.tinted, hue: hue, level: level),
          );
          for (final pair in kTintContrastPairs(p)) {
            final ratio = contrastRatio(pair.fg, pair.bg);
            expect(
              ratio,
              greaterThanOrEqualTo(pair.min),
              reason: '${pair.name} at hue $hue level $level: $ratio',
            );
          }
        }
      });
    }
  });

  test('chrome tint keeps the ink readable in both themes at full level', () {
    for (var hue = 0; hue < 360; hue += 3) {
      final p = TintPalette.of(
        TintPreferences(style: TintStyle.tinted, hue: hue, level: 100),
      );
      final light = Color.alphaBlend(p.chromeTintLight, AppColors.canvasLight);
      final dark = Color.alphaBlend(p.chromeTintDark, AppColors.canvasDark);
      expect(
        contrastRatio(AppColors.inkLight, light),
        greaterThanOrEqualTo(4.5),
      );
      expect(contrastRatio(AppColors.inkDark, dark), greaterThanOrEqualTo(4.5));
      expect(p.chromeTintLight.a, greaterThan(0));
      expect(p.chromeTintDark.a, greaterThan(0));
    }
  });

  test('gamut edge hues fit their chroma', () {
    for (final hue in [200.0, 265.0]) {
      final c = fitChroma(0.742, 0.137, hue);
      expect(c, lessThanOrEqualTo(0.137));
      expect(inSrgbGamut(0.742, c, hue), isTrue);
    }
    expect(inSrgbGamut(0.742, 0.4, 265), isFalse);
  });

  test('palette is cached per rounded pair', () {
    const a = TintPreferences(style: TintStyle.tinted, hue: 33, level: 50);
    expect(identical(TintPalette.of(a), TintPalette.of(a)), isTrue);
    expect(
      identical(
        TintPalette.of(a),
        TintPalette.of(
          const TintPreferences(style: TintStyle.tinted, hue: 34, level: 50),
        ),
      ),
      isFalse,
    );
  });
}
