/// OKLCH → sRGB color helpers for the project-settings palette.
///
/// The design system specifies label / workflow / accent colors as oklch hues
/// (a single integer 0–360 at fixed lightness/chroma). Flutter has no native
/// oklch, so this converts oklch → OKLab → linear sRGB → gamma sRGB. The fixed
/// L/C presets mirror the HTML reference (`project_settings.css`):
///   dot/badge ink  = oklch(0.60 0.14 H)
///   soft fill      = oklch(0.97 0.025 H)
///   border         = oklch(0.86 0.07 H)
///   strong ink     = oklch(0.40 0.12 H)
///   accent swatch  = oklch(0.62 0.13 H)
library;

import 'dart:math' as math;
import 'dart:ui';

import 'app_colors.dart';

/// Named accent palette (hue + display name), in design swatch order.
const List<({int hue, String name})> kProjectHues = [
  (hue: 70, name: 'Honey'),
  (hue: 250, name: 'Indigo'),
  (hue: 300, name: 'Violet'),
  (hue: 200, name: 'Teal'),
  (hue: 155, name: 'Green'),
  (hue: 20, name: 'Coral'),
  (hue: 330, name: 'Pink'),
  (hue: 45, name: 'Amber'),
];

/// Distinct, evenly-spread label hues (cycled when adding labels).
const List<int> kLabelHues = [70, 250, 300, 200, 155, 20, 330, 45];

/// Default workflow-state hues by canonical name (Open…Done).
/// 'Backlog' is kept for projects created with the legacy default workflow.
const Map<String, int> kDefaultStateHues = {
  'Backlog': 255,
  'Open': 250,
  'In Progress': 70,
  'In Parking': 255,
  'In Review': 300,
  'Done': 155,
};

String hueName(int hue) {
  for (final c in kProjectHues) {
    if (c.hue == hue) return c.name;
  }
  return 'Custom';
}

/// Core oklch → [Color] conversion (alpha forced opaque).
Color oklch(double l, double c, double hueDeg) {
  final h = hueDeg * math.pi / 180.0;
  final a = c * math.cos(h);
  final b = c * math.sin(h);

  // OKLab → LMS (cubed)
  final lp = l + 0.3963377774 * a + 0.2158037573 * b;
  final mp = l - 0.1055613458 * a - 0.0638541728 * b;
  final sp = l - 0.0894841775 * a - 1.2914855480 * b;
  final lc = lp * lp * lp;
  final mc = mp * mp * mp;
  final sc = sp * sp * sp;

  // LMS → linear sRGB
  final r = 4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc;
  final g = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc;
  final bl = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc;

  return Color.fromARGB(255, _channel(r), _channel(g), _channel(bl));
}

int _channel(double linear) {
  final v = linear <= 0.0031308
      ? 12.92 * linear
      : 1.055 * math.pow(linear, 1 / 2.4) - 0.055;
  return (v.clamp(0.0, 1.0) * 255).round();
}

/// Saturated dot / badge ink for a hue.
Color hueColor(int hue) => oklch(0.60, 0.14, hue.toDouble());

/// Strong, readable text color tinted to a hue.
Color hueInk(int hue) => oklch(0.40, 0.12, hue.toDouble());

/// Soft chip background tint. In dark mode a flat-light fill would glow, so we
/// use a translucent wash of the hue over the active surface instead.
Color hueSoft(int hue) => AppColors.brightness == Brightness.dark
    ? hueColor(hue).withValues(alpha: 0.22)
    : oklch(0.97, 0.025, hue.toDouble());

/// Hairline border tint for a hue (light mode); muted in dark mode.
Color hueBorder(int hue) => AppColors.brightness == Brightness.dark
    ? hueColor(hue).withValues(alpha: 0.40)
    : oklch(0.86, 0.07, hue.toDouble());

/// Readable on-tint text color for a soft chip in either mode.
Color hueChipText(int hue) => AppColors.brightness == Brightness.dark
    ? oklch(0.85, 0.10, hue.toDouble())
    : hueInk(hue);

/// Accent swatch color (oklch 0.62 0.13 H) — used for the project-color picker.
Color hueSwatch(int hue) => oklch(0.62, 0.13, hue.toDouble());

/// `#RRGGBB` for an accent hue, for persisting the project's color field.
String hexForHue(int hue) {
  final c = hueSwatch(hue);
  return '#'
      '${(c.r * 255).round().toRadixString(16).padLeft(2, '0')}'
      '${(c.g * 255).round().toRadixString(16).padLeft(2, '0')}'
      '${(c.b * 255).round().toRadixString(16).padLeft(2, '0')}';
}

/// Nearest palette hue to a stored hex accent (round-trips [hexForHue]).
int hueForHex(String hex) {
  final target = colorFromHex(hex);
  int best = kProjectHues.first.hue;
  double bestDist = double.infinity;
  for (final c in kProjectHues) {
    final s = hueSwatch(c.hue);
    final dr = (s.r - target.r);
    final dg = (s.g - target.g);
    final db = (s.b - target.b);
    final dist = dr * dr + dg * dg + db * db;
    if (dist < bestDist) {
      bestDist = dist;
      best = c.hue;
    }
  }
  return best;
}

/// Parses `#RRGGBB` / `RRGGBB` to a [Color]; falls back to a neutral grey.
Color colorFromHex(String hex) {
  final raw = hex.replaceAll('#', '').trim();
  if (raw.length == 6) {
    final value = int.tryParse(raw, radix: 16);
    if (value != null) return Color(0xFF000000 | value);
  }
  return const Color(0xFF9A99B0);
}
