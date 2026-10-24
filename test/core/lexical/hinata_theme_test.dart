import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/lexical/hinata_theme.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/contrast.dart';
import 'package:hinata/core/theme/tint_palette.dart';

void main() {
  tearDown(() {
    AppColors.brightness = Brightness.light;
    AppColors.palette = TintPalette.standard;
  });

  // A tick box is a control: 3:1 to every page it sits on, and its tick 3:1 to
  // the filled box (WCAG 1.4.11).
  group('tick box contrast', () {
    final palettes = {
      'standard': TintPalette.standard,
      for (var hue = 0; hue < 360; hue += 15)
        'hue $hue': TintPalette.of(
          TintPreferences(style: TintStyle.tinted, hue: hue, level: 100),
        ),
    };

    for (final brightness in Brightness.values) {
      test(brightness.name, () {
        AppColors.brightness = brightness;
        final pages = {
          'canvas': AppColors.canvas,
          'surface': AppColors.surface,
          'surfaceMuted': AppColors.surfaceMuted,
        };
        for (final MapEntry(key: tint, value: palette) in palettes.entries) {
          AppColors.palette = palette;
          final marker = hinataMarkerPalette();
          for (final MapEntry(key: page, value: ground) in pages.entries) {
            final rim = contrastRatio(marker.border, ground);
            expect(rim, greaterThanOrEqualTo(3), reason: 'rim on $page, $tint');
            final box = contrastRatio(marker.accent, ground);
            expect(box, greaterThanOrEqualTo(3), reason: 'box on $page, $tint');
          }
          final tick = contrastRatio(marker.surface, marker.accent);
          expect(tick, greaterThanOrEqualTo(3), reason: 'tick, $tint');
        }
      });
    }
  });
}
