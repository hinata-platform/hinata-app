import 'package:flutter/painting.dart';

import '../models/account_models.dart';
import 'app_colors.dart';
import 'contrast.dart';
import 'hue_colors.dart';

/// Every brand and accent step the app paints, derived from one tint
/// (HIN-150): a hue and a level. [standard] is today's brand, byte for byte;
/// a tinted palette is computed from the measured oklch of those constants
/// (honey `#D9A032` = oklch(0.742, 0.137, 79), navy `#2D2B55` =
/// oklch(0.314, 0.074, 284)) with the hue swapped and the chroma scaled.
///
/// Steps that carry text, a focus ring, a state border or the glass tint are
/// *solved*: the lightness (or the alpha) is bisected until the step reaches
/// its target contrast, so the targets hold for every hue. Steps with a fixed
/// lightness are pinned by the property test over all hues and levels
/// (`kTintContrastPairs` is the one list both read).
///
/// Built on a change only, never in `build()`: [of] caches per rounded
/// `(hue, level)`.
class TintPalette {
  TintPalette._({
    required this.accent,
    required this.accentStrong,
    required this.accentLine,
    required this.accentDeep,
    required this.accentText,
    required this.accentInkDark,
    required this.accentSoftLight,
    required this.accentSoftDark,
    required this.onAccent,
    required this.focusRingLight,
    required this.focusRingDark,
    required this.stateBorderLight,
    required this.stateBorderDark,
    required this.accentGroundLight,
    required this.accentGroundDark,
    required this.accentVeilLight,
    required this.accentVeilDark,
    required this.chromeTintLight,
    required this.chromeTintDark,
    required this.primary,
    required this.primaryDeep,
    required this.rail,
    required this.rail2,
    required this.railInk,
    required this.railFaint,
  });

  /// Distinct per instance, exact rather than hashed, for memo keys.
  final int id = _nextId++;
  static int _nextId = 0;

  /// The signature accent (honey in the standard brand).
  final Color accent;
  final Color accentStrong;
  final Color accentLine;

  /// Deep enough for white text (4.6:1).
  final Color accentDeep;

  /// Accent as text on light paper and on the accent wash.
  final Color accentText;

  /// Accent as text in the dark theme, on the dark surface and on the accent
  /// wash. The accent itself where it reads; a lighter shade of it where a
  /// vivid accent (a real red) does not reach 4.5:1 on its own wash.
  final Color accentInkDark;
  final Color accentSoftLight;
  final Color accentSoftDark;

  /// The ink on an accent-coloured glass surface.
  final Color onAccent;
  final Color focusRingLight;
  final Color focusRingDark;
  final Color stateBorderLight;
  final Color stateBorderDark;
  final LinearGradient accentGroundLight;
  final LinearGradient accentGroundDark;
  final Color accentVeilLight;
  final Color accentVeilDark;

  /// The tint the nav chrome takes; fully transparent in the standard brand
  /// and at level 0.
  final Color chromeTintLight;
  final Color chromeTintDark;

  /// The primary (navy in the standard brand): the rail, the ink on a filled
  /// button, the brand mark.
  final Color primary;
  final Color primaryDeep;
  final Color rail;
  final Color rail2;
  final Color railInk;
  final Color railFaint;

  /// Today's brand, exactly.
  static final standard = TintPalette._(
    accent: const Color(0xFFD9A032),
    accentStrong: const Color(0xFFB9831F),
    accentLine: const Color(0xFFE4CE96),
    accentDeep: const Color(0xFF946A16),
    accentText: const Color(0xFF7A5410),
    accentInkDark: const Color(0xFFD9A032),
    accentSoftLight: const Color(0xFFF3E9D2),
    accentSoftDark: const Color(0x29D9A032),
    onAccent: const Color(0xFF2A2410),
    focusRingLight: const Color(0xFF7A5410),
    focusRingDark: const Color(0xFFD9A032),
    stateBorderLight: const Color(0xFFB9831F),
    stateBorderDark: const Color(0xFFD9A032),
    accentGroundLight: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFE7B24A), Color(0xFFD9A032), Color(0xFFB9831F)],
    ),
    accentGroundDark: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFC452), Color(0xFFFFBC3B), Color(0xFFDE9D25)],
    ),
    accentVeilLight: const Color(0x1FD9A032),
    accentVeilDark: const Color(0x59FFBC3B),
    chromeTintLight: const Color(0x00FFFFFF),
    chromeTintDark: const Color(0x00FFFFFF),
    primary: const Color(0xFF2D2B55),
    primaryDeep: const Color(0xFF1E1C3A),
    rail: const Color(0xFF211F3D),
    rail2: const Color(0xFF1A1830),
    railInk: const Color(0xFFC9C7E0),
    railFaint: const Color(0xFF8A88A7),
  );

  /// The palette for [prefs]: [standard] for the default style, else a
  /// cached derivation.
  static TintPalette of(TintPreferences prefs) {
    if (prefs.style == TintStyle.defaultStyle) return standard;
    final key = (prefs.hue.clamp(0, 359), prefs.level.clamp(0, 100));
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final built = _derive(key.$1, key.$2);
    _cache[key] = built;
    if (_cache.length > _cacheSize) _cache.remove(_cache.keys.first);
    return built;
  }

  static final _cache = <(int, int), TintPalette>{};
  static const _cacheSize = 32;

  /// Where the honey's measured chroma sits, scaled by the level: 0.4 at level
  /// 0 (pale, nearly grey), 1.0 at level 100.
  static double chromaScale(int level) => 0.4 + 0.6 * level / 100;

  /// How opaque the glass tint may be at most, before the ink has its say.
  static const maxChromeTintAlpha = 0.45;

  static TintPalette _derive(int hue, int level) {
    final h = hue.toDouble();
    final vivid = _vividAccent(hue, level);
    // Every other step takes the accent's chroma relative to the honey's
    // (0.137), so a vivid red carries its strength into its washes and inks;
    // the gamut fit trims whatever sRGB cannot show.
    final c = vivid.chroma / 0.137;
    Color fit(double l, double chroma) => oklchFit(l, chroma * c, h);

    final accent = oklchFit(vivid.lightness, vivid.chroma, h);
    final accentStrong = _darkestOrLightest(
      chroma: 0.126 * c,
      hue: h,
      // Solved against the light surface only: the predicate must be one
      // directional for the bisection, and at the L this lands on the dark
      // surface is far clearer (the test still pins both).
      reaches: (color) => contrastRatio(color, AppColors.surfaceLight) >= 3.0,
      lightest: true,
    );
    final accentLine = fit(0.856, 0.077);
    final accentSoftLight = fit(0.936, 0.032);
    final accentSoftDark = accent.withValues(alpha: 0x29 / 255);
    final accentDeep = _darkestOrLightest(
      chroma: 0.107 * c,
      hue: h,
      reaches: (color) => contrastRatio(const Color(0xFFFFFFFF), color) >= 4.6,
      lightest: true,
    );
    final accentText = _darkestOrLightest(
      chroma: 0.093 * c,
      hue: h,
      reaches: (color) =>
          contrastRatio(color, accentSoftLight) >= 5.6 &&
          contrastRatio(color, AppColors.canvasLight) >= 6.0,
      lightest: true,
    );
    // The inks that sit on the accent: as light as the honey's, darker where
    // a deeper accent (a real red sits at L 0.66) would otherwise drop them
    // under 4.5:1.
    final accentInkDark = _readsOnDark(accent)
        ? accent
        : _darkestOrLightest(
            chroma: vivid.chroma,
            hue: h,
            reaches: _readsOnDark,
            lightest: false,
          );
    final onAccent = _atMost(
      0.26,
      chroma: 0.034 * c,
      hue: h,
      reaches: (color) => contrastRatio(color, accent) >= 4.5,
    );
    final primary = _atMost(
      0.314,
      chroma: 0.074,
      hue: h,
      reaches: (color) =>
          contrastRatio(color, accent) >= 4.5 &&
          contrastRatio(const Color(0xFFFFFFFF), color) >= 4.5,
    );
    final primaryDeep = _atMost(
      0.246,
      chroma: 0.056,
      hue: h,
      reaches: (color) => contrastRatio(accent, color) >= 4.5,
    );
    final rail = oklchFit(0.258, 0.055, h);
    final rail2 = oklchFit(0.225, 0.046, h);
    final railInk = oklchFit(0.839, 0.035, h);
    final railFaint = _darkestOrLightest(
      chroma: 0.046,
      hue: h,
      reaches: (color) => contrastRatio(color, rail) >= 4.6,
      lightest: false,
    );

    final groundLight = [fit(0.78, 0.14), accent, accentStrong];
    // The same ground lifted for a dark page: every channel a fifth brighter,
    // saturation untouched (measured in HIN-110: the glass renders a ground
    // about 22% darker over a dark page).
    final groundDark = [for (final stop in groundLight) _lift(stop, 1 / 0.78)];

    final chromeTintLight = _chromeTint(
      tint: accent,
      ink: AppColors.inkLight,
      canvas: AppColors.canvasLight,
      level: level,
    );
    final chromeTintDark = _chromeTint(
      tint: groundDark[1],
      ink: AppColors.inkDark,
      canvas: AppColors.canvasDark,
      level: level,
    );

    return TintPalette._(
      accent: accent,
      accentStrong: accentStrong,
      accentLine: accentLine,
      accentDeep: accentDeep,
      accentText: accentText,
      accentInkDark: accentInkDark,
      accentSoftLight: accentSoftLight,
      accentSoftDark: accentSoftDark,
      onAccent: onAccent,
      focusRingLight: accentText,
      focusRingDark: accent,
      stateBorderLight: accentStrong,
      stateBorderDark: accent,
      accentGroundLight: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: groundLight,
      ),
      accentGroundDark: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: groundDark,
      ),
      accentVeilLight: accent.withValues(alpha: 0x1F / 255),
      accentVeilDark: groundDark[1].withValues(alpha: 0x59 / 255),
      chromeTintLight: chromeTintLight,
      chromeTintDark: chromeTintDark,
      primary: primary,
      primaryDeep: primaryDeep,
      rail: rail,
      rail2: rail2,
      railInk: railInk,
      railFaint: railFaint,
    );
  }

  /// How far the accent's chroma may go: a real red needs 0.22 and more, the
  /// honey sits at 0.15. A cap keeps the loudest hues (magenta, cyan) from
  /// turning into neon.
  static const accentChromaCap = 0.22;

  /// The accent's lightness never rises above the honey's: lighter tints
  /// read as pastel on paper.
  static const accentMaxLightness = 0.742;

  /// The accent is read as text on the dark surface; this is its floor
  /// there. On its own wash (the active pill) it owes the plain 4.5.
  static const accentMinContrastOnDark = 4.6;

  static final _vividCache =
      <(int, int), ({double lightness, double chroma})>{};

  /// The most saturated accent the hue allows at [level]: the lightness at
  /// or below [accentMaxLightness] where the gamut-fitted chroma, up to
  /// [accentChromaCap] scaled by the level, is largest while the colour still
  /// reads at [accentMinContrastOnDark] on the dark surface. At a fixed
  /// lightness of 0.742 a red can only be salmon; sRGB's red lives at 0.63.
  /// Of equally saturated choices the lighter one wins, which keeps the
  /// yellows and the honey where they were.
  static ({double lightness, double chroma}) _vividAccent(int hue, int level) =>
      _vividCache.putIfAbsent((hue, level), () {
        final h = hue.toDouble();
        final cap = accentChromaCap * chromaScale(level);
        var bestL = accentMaxLightness;
        var bestC = -1.0;
        for (var step = 0; step <= 40; step++) {
          final l = accentMaxLightness - step * 0.005;
          final c = fitChroma(l, cap, h);
          if (contrastRatio(oklch(l, c, h), AppColors.surfaceDark) <
              accentMinContrastOnDark) {
            continue;
          }
          // Strictly greater: walking down from the top, ties keep the
          // lighter colour.
          if (c > bestC + 0.0005) {
            bestC = c;
            bestL = l;
          }
        }
        if (bestC < 0) bestC = fitChroma(bestL, cap, h);
        return (lightness: bestL, chroma: bestC);
      });

  /// Whether [ink] reads as text in the dark theme: on the dark surface, and
  /// on the accent wash laid over the dark surface and the dark canvas (the
  /// active pill, where it is the label).
  static bool _readsOnDark(Color ink) {
    final accent = ink;
    if (contrastRatio(accent, AppColors.surfaceDark) <
        accentMinContrastOnDark) {
      return false;
    }
    final wash = accent.withValues(alpha: 0x29 / 255);
    return contrastRatio(
              accent,
              Color.alphaBlend(wash, AppColors.surfaceDark),
            ) >=
            4.5 &&
        contrastRatio(accent, Color.alphaBlend(wash, AppColors.canvasDark)) >=
            4.5;
  }

  /// The lightest colour at [chroma] and [hue], no lighter than [cap], for
  /// which [reaches] holds.
  static Color _atMost(
    double cap, {
    required double chroma,
    required double hue,
    required bool Function(Color) reaches,
  }) {
    final atCap = oklchFit(cap, chroma, hue);
    if (reaches(atCap)) return atCap;
    return _darkestOrLightest(
      chroma: chroma,
      hue: hue,
      reaches: reaches,
      lightest: true,
    );
  }

  /// The colour the hue slider's track shows for [hue] at [level]: exactly
  /// the accent a tint of that hue would get.
  static Color accentFor(int hue, int level) {
    final v = _vividAccent(hue % 360, level.clamp(0, 100));
    return oklchFit(v.lightness, v.chroma, hue.toDouble());
  }

  /// The lightest (or darkest) oklch colour at [chroma] and [hue] for which
  /// [reaches] holds, by bisection on L in twelve steps (2.4e-4, finer than
  /// eight bits). Lightest: the predicate holds below some L and fails above;
  /// darkest: the other way round.
  static Color _darkestOrLightest({
    required double chroma,
    required double hue,
    required bool Function(Color) reaches,
    required bool lightest,
  }) {
    var lo = 0.05;
    var hi = 0.95;
    for (var i = 0; i < 12; i++) {
      final mid = (lo + hi) / 2;
      final ok = reaches(oklchFit(mid, chroma, hue));
      if (lightest ? ok : !ok) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return oklchFit(lightest ? lo : hi, chroma, hue);
  }

  static Color _lift(Color color, double factor) => Color.fromARGB(
    255,
    (color.r * factor * 255).round().clamp(0, 255),
    (color.g * factor * 255).round().clamp(0, 255),
    (color.b * factor * 255).round().clamp(0, 255),
  );

  /// [tint] at the largest alpha up to `maxChromeTintAlpha · level / 100` at
  /// which [ink] still reads at 4.5:1 on the tint composited over [canvas].
  static Color _chromeTint({
    required Color tint,
    required Color ink,
    required Color canvas,
    required int level,
  }) {
    final wanted = maxChromeTintAlpha * level / 100;
    if (wanted <= 0) return const Color(0x00FFFFFF);
    bool readable(double alpha) =>
        contrastRatio(
          ink,
          Color.alphaBlend(tint.withValues(alpha: alpha), canvas),
        ) >=
        4.5;
    if (readable(wanted)) return tint.withValues(alpha: wanted);
    var lo = 0.0;
    var hi = wanted;
    for (var i = 0; i < 10; i++) {
      final mid = (lo + hi) / 2;
      if (readable(mid)) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return tint.withValues(alpha: lo);
  }
}

/// A foreground on a background with the minimum contrast it owes.
class ContrastPair {
  const ContrastPair(this.name, this.fg, this.bg, this.min);
  final String name;
  final Color fg;
  final Color bg;
  final double min;
}

/// Every contrast the palette promises, as one list the test reads. The
/// minimums are the design's targets (HIN-110 measurements), not WCAG's
/// floors; a change here is a design decision.
List<ContrastPair> kTintContrastPairs(TintPalette p) {
  const white = Color(0xFFFFFFFF);
  final softOverSurfaceDark = Color.alphaBlend(
    p.accentSoftDark,
    AppColors.surfaceDark,
  );
  final softOverCanvasDark = Color.alphaBlend(
    p.accentSoftDark,
    AppColors.canvasDark,
  );
  return [
    ContrastPair('accent on surfaceDark', p.accent, AppColors.surfaceDark, 4.5),
    ContrastPair(
      'accentInkDark on surfaceDark',
      p.accentInkDark,
      AppColors.surfaceDark,
      4.5,
    ),
    ContrastPair(
      'accentInkDark on accentSoftDark/surfaceDark',
      p.accentInkDark,
      softOverSurfaceDark,
      4.5,
    ),
    ContrastPair(
      'accentInkDark on accentSoftDark/canvasDark',
      p.accentInkDark,
      softOverCanvasDark,
      4.5,
    ),
    ContrastPair('accent on primaryDeep', p.accent, p.primaryDeep, 4.5),
    ContrastPair(
      'accentStrong on surfaceLight',
      p.accentStrong,
      AppColors.surfaceLight,
      3.0,
    ),
    ContrastPair(
      'accentStrong on surfaceDark',
      p.accentStrong,
      AppColors.surfaceDark,
      3.0,
    ),
    ContrastPair('white on accentDeep', white, p.accentDeep, 4.6),
    ContrastPair(
      'accentText on accentSoftLight',
      p.accentText,
      p.accentSoftLight,
      5.6,
    ),
    ContrastPair(
      'accentText on canvasLight',
      p.accentText,
      AppColors.canvasLight,
      6.0,
    ),
    ContrastPair('onAccent on accent', p.onAccent, p.accent, 4.5),
    ContrastPair(
      'focusRingLight on canvasLight',
      p.focusRingLight,
      AppColors.canvasLight,
      3.0,
    ),
    ContrastPair(
      'focusRingLight on surfaceLight',
      p.focusRingLight,
      AppColors.surfaceLight,
      3.0,
    ),
    ContrastPair(
      'focusRingLight on accentSoftLight',
      p.focusRingLight,
      p.accentSoftLight,
      3.0,
    ),
    ContrastPair(
      'focusRingDark on canvasDark',
      p.focusRingDark,
      AppColors.canvasDark,
      3.0,
    ),
    ContrastPair(
      'focusRingDark on surfaceDark',
      p.focusRingDark,
      AppColors.surfaceDark,
      3.0,
    ),
    ContrastPair(
      'focusRingDark on accentSoftDark',
      p.focusRingDark,
      softOverSurfaceDark,
      3.0,
    ),
    ContrastPair(
      'stateBorderLight on surfaceLight',
      p.stateBorderLight,
      AppColors.surfaceLight,
      3.0,
    ),
    ContrastPair(
      'stateBorderDark on surfaceDark',
      p.stateBorderDark,
      AppColors.surfaceDark,
      3.0,
    ),
    ContrastPair('white on primary', white, p.primary, 4.5),
    ContrastPair('primary on accent', p.primary, p.accent, 4.5),
    ContrastPair(
      'primary on canvasLight',
      p.primary,
      AppColors.canvasLight,
      4.5,
    ),
    ContrastPair('railInk on rail', p.railInk, p.rail, 7.0),
    ContrastPair(
      'railInk on surfaceDark',
      p.railInk,
      AppColors.surfaceDark,
      4.5,
    ),
    ContrastPair('railInk on canvasDark', p.railInk, AppColors.canvasDark, 4.5),
    ContrastPair('railFaint on rail', p.railFaint, p.rail, 4.6),
    ContrastPair(
      'inkLight on chromeTintLight/canvasLight',
      AppColors.inkLight,
      Color.alphaBlend(p.chromeTintLight, AppColors.canvasLight),
      4.5,
    ),
    ContrastPair(
      'inkDark on chromeTintDark/canvasDark',
      AppColors.inkDark,
      Color.alphaBlend(p.chromeTintDark, AppColors.canvasDark),
      4.5,
    ),
  ];
}
