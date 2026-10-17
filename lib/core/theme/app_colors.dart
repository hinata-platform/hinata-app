import 'package:flutter/material.dart';

import 'tint_palette.dart';

/// Hinata "Hive" design tokens — redesign 2026.
/// Navy nav-rail · warm-paper workspace · honey-amber signature accent in the
/// standard brand; since HIN-150 a person's tint can replace navy and honey.
///
/// Neutral surface/ink tokens are theme-aware: they resolve against the
/// currently active [brightness] (driven from the app's [ThemeMode] in
/// `app.dart`). Brand and accent tokens read the active [palette] (HIN-150):
/// the standard brand unless the person has tinted the app, and the same in
/// light and dark so the signature reads identically in both modes. Status
/// hues stay constant: they mean something.
///
/// Hex values are derived from an oklch model (constant L/C, varied hue) so
/// status & accent tints stay perceptually harmonious. The brand honey
/// `#D9A032` measures oklch(0.742, 0.137, 79), the navy `#2D2B55`
/// oklch(0.314, 0.074, 284); [TintPalette] derives a tint from those.
abstract final class AppColors {
  // ---- active brightness (drives the neutral getters below) ----
  // Set once per frame from the resolved theme in `app.dart`'s MaterialApp
  // builder. Defaults to light so the very first build (and any non-widget
  // access) is well-defined.
  static Brightness brightness = Brightness.light;
  static bool get _dark => brightness == Brightness.dark;

  // ---- active palette (drives the brand and accent getters) ----
  // A static like [brightness], and for the same reason: some 800 reading
  // sites have no BuildContext. Set beside it in `app.dart`. A
  // ThemeExtension remains a possible later step.
  static TintPalette palette = TintPalette.standard;

  /// One key for a widget memo that bakes colours in: changes when either
  /// the brightness or the palette does. Exact, not a hash: two palettes
  /// never share an id.
  static int get themeKey => palette.id * 2 + brightness.index;

  // ---- brand (from the palette; navy in the standard brand) ----
  static Color get primary => palette.primary; // primary action
  static Color get primaryDeep => palette.primaryDeep;

  // ---- ink / text (theme-aware) ----
  static const inkLight = Color(0xFF23223F);
  static const inkDark = Color(0xFFECEBF3);
  static Color get ink => _dark ? inkDark : inkLight; // primary text

  // The three tiers are set by contrast, measured with check_contrast.py
  // (HIN-110) against every surface they are read on: canvas, card, the muted
  // and the pastel cards, the amber wash. The quietest tier still clears
  // 4.5:1 there (WCAG 1.4.3): hints, timestamps and placeholders are text
  // people have to read. Light paper leaves room for only so many greys above
  // 4.5:1, so secondary sits a clear step darker than hints, and the hierarchy
  // between them also rides on size and weight, not on fading text out.
  static const inkSoftLight = Color(0xFF4F4E62); // 7.3:1 on canvas
  static const inkSoftDark = Color(0xFFA8A6C2);
  static Color get inkSoft => _dark ? inkSoftDark : inkSoftLight; // secondary

  static const inkFaintLight = Color(0xFF666583); // 5.0:1 canvas, 4.6:1 amber
  static const inkFaintDark = Color(0xFF8C8AA1); // 4.7:1 on the muted surface
  static Color get inkFaint => _dark ? inkFaintDark : inkFaintLight; // hints

  // ---- workspace surfaces (theme-aware) ----
  static const canvasLight = Color(0xFFF4F3EF); // warm paper
  static const canvasDark = Color(0xFF131119); // warm-tinted near-black
  static Color get canvas => _dark ? canvasDark : canvasLight; // app background

  static const canvas2Light = Color(0xFFEFEEE8);
  static const canvas2Dark = Color(0xFF0E0D14);
  static Color get canvas2 => _dark ? canvas2Dark : canvas2Light; // recessed

  /// A stretch a surface pushes back — today, a weekend column on the
  /// calendar's hour canvas.
  ///
  /// Translucent on purpose, and the reason it is not simply [canvas2]. These
  /// surfaces are drawn on glass, and an opaque fill stops the window's own
  /// backdrop dead: the weekend came out as a black slab in the dark theme and
  /// a grey one in the light, with a hard seam down Saturday morning where the
  /// aurora behind it was cut off. A tint recedes and lets the same backdrop
  /// carry on through — the ink over it does the rest of the work.
  static const recessLight = Color(0x14211F3D);
  static const recessDark = Color(0x38080610);
  static Color get recess => _dark ? recessDark : recessLight;

  /// A stretch nothing can be written to — a day behind the lock date, a period
  /// already handed in.
  ///
  /// Not [recess] and not a multiple of it, because the two themes need opposite
  /// answers. Measured on the calendar canvas against the adjacent open day: in
  /// the light theme this is 1.97 to the weekend's 1.34, which is what makes a
  /// freeze read as the stronger of the two statements rather than as a second
  /// weekend. In the dark theme darkening has no headroom at all — the canvas is
  /// already near black, and *pure black* over it moves the contrast by a fifth —
  /// so the veil is a pale one there and the weekend keeps the dark. The padlock
  /// beside the date is what names either of them; the wash only has to be seen.
  static const closedLight = Color(0x59211F3D);
  static const closedDark = Color(0x29FFFFFF);
  static Color get closed => _dark ? closedDark : closedLight;

  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF1C1B25);
  static Color get surface => _dark ? surfaceDark : surfaceLight; // cards

  static const surfaceMutedLight = Color(0xFFFAF9F6);
  static const surfaceMutedDark = Color(0xFF232231);
  static Color get surfaceMuted => _dark ? surfaceMutedDark : surfaceMutedLight;

  static const hairlineLight = Color(0xFFE7E5DE);
  static const hairlineDark = Color(0xFF2E2D3B);
  static Color get hairline => _dark ? hairlineDark : hairlineLight; // borders

  static const hairline2Light = Color(0xFFEFEDE6);
  static const hairline2Dark = Color(0xFF27262F);
  static Color get hairline2 => _dark ? hairline2Dark : hairline2Light;

  // The rim of a form field on glass. Translucent ink rather than a solid
  // hairline: a field has no fill of its own, so its rim is the only thing
  // that says where it is, and a fixed grey vanishes on whatever the glass
  // happens to show behind it. Ink at a fifth takes its contrast from the
  // surface it sits on.
  static const fieldRimLight = Color(0x3323223F);
  static const fieldRimDark = Color(0x38FFFFFF);
  static Color get fieldRim => _dark ? fieldRimDark : fieldRimLight;

  // ---- nav rail (deep in both themes; navy in the standard brand) ----
  static Color get rail => palette.rail;
  static Color get rail2 => palette.rail2;
  static Color get railInk => palette.railInk;
  static Color get railFaint => palette.railFaint; // 4.6:1 on the rail

  // ---- signature accent (honey, hue 79, in the standard brand) ----
  static Color get accent => palette.accent; // oklch(.742 .137 79)
  static Color get accentStrong => palette.accentStrong; // oklch(.648 .126 77)
  static Color get accentLine => palette.accentLine; // oklch(.856 .077 89)
  // White text on honey (the "today" chip of HIN-118): [accentStrong] reaches
  // only 3.3:1 under white, this deeper honey 4.85:1 (WCAG 1.4.3).
  static Color get accentDeep => palette.accentDeep;
  // Accent text on the accent wash in the light theme, where [accentStrong]
  // is too light to read on its own tint.
  static Color get accentText => palette.accentText;

  // Soft accent fill (active pill / unread highlight). Theme-aware: an opaque
  // pale tint in light, a translucent accent wash on dark surfaces.
  static Color get accentSoftLight => palette.accentSoftLight;
  static Color get accentSoftDark => palette.accentSoftDark;
  static Color get accentSoft => _dark ? accentSoftDark : accentSoftLight;

  /// The focus indicator (WCAG 1.4.11, 3:1 on every surface it sits on). Not
  /// [accent]: honey on white reaches 2.3:1, and that holds for any hue at
  /// its lightness, so focus takes the text shade in light and the accent in
  /// dark.
  static Color get focusRing =>
      _dark ? palette.focusRingDark : palette.focusRingLight;

  /// A border that carries a state (selected, active): 3:1 on the surface.
  /// [accentLine] is decorative and reaches 1.6:1.
  static Color get stateBorder =>
      _dark ? palette.stateBorderDark : palette.stateBorderLight;

  /// The ink on an accent-coloured glass surface.
  static Color get onAccent => palette.onAccent;

  /// The accent ground a glass primary action floats on.
  static LinearGradient accentGround(bool dark) =>
      dark ? palette.accentGroundDark : palette.accentGroundLight;

  /// The accent veil that sits on that ground.
  static Color accentVeil(bool dark) =>
      dark ? palette.accentVeilDark : palette.accentVeilLight;

  /// The tint the nav chrome takes; transparent in the standard brand.
  static Color chromeTint(bool dark) =>
      dark ? palette.chromeTintDark : palette.chromeTintLight;

  // ---- workflow status (varied hue, constant L/C ~ oklch .6 .13) ----
  static const stBacklog = Color(0xFF7E81AE); // hue 255, muted slate
  static const stTodo = Color(0xFF5B86D6); // hue 250
  static const stProgress = Color(0xFFC58A22); // hue 70 (honey)
  static const stReview = Color(0xFF9A6BD0); // hue 300
  static const stDone = Color(0xFF2FA06E); // hue 155

  // ---- priority ----
  static const priUrgent = Color(0xFFD9544B); // hue 22
  static const priHigh = Color(0xFFD98A2B); // hue 45
  static const priNormal = Color(0xFF5B86D6); // hue 250
  static const priLow = Color(0xFF8887A2); // muted; 3:1 as an icon (1.4.11)

  // ---- semantic ----
  static const danger = Color(0xFFD9544B);
  static const dangerSoft = Color(0xFFFBE7E4);

  /// Danger as small text: [danger] itself reaches 3.9:1 on white and 4.3:1 on
  /// the dark surface, short of 4.5 for body text (HIN-119, measured).
  static Color get dangerInk =>
      _dark ? const Color(0xFFEC7F77) : const Color(0xFFB23A32);
  static const success = Color(0xFF2FA06E);

  /// Success as small text: [success] reaches 3.3:1 on white. The dark
  /// surface already clears 4.5:1 with it.
  static Color get successInk => _dark ? success : const Color(0xFF257C56);
  static const warning = Color(0xFFD9A032);

  /// A bar between the warning share and the limit (HIN-151). [warning]
  /// itself reaches only 2.1:1 on the paper canvas, short of the 3:1 a
  /// graphic needs (WCAG 1.4.11); this deeper amber reaches 3.8:1 on the
  /// canvas and 3.7:1 in a recessed track. The dark surfaces already clear it
  /// with [warning] (8.0:1).
  static Color get warningBar =>
      _dark ? warning : const Color(0xFFA86F05);

  /// Warning as small text: 5.3:1 on the canvas, 5.9:1 on white. Dark takes a
  /// lighter amber than [warning]: on a frosted glass surface over the dark
  /// ambient [warning] reached only 4.2:1, this one 5.0:1 (measured, HIN-151).
  static Color get warningInk =>
      _dark ? const Color(0xFFEFC163) : const Color(0xFF8A5A00);

  // ---- compatibility aliases (migrate screens progressively) ----
  static Color get textPrimary => ink;
  static Color get textSecondary => inkSoft;
  static const textOnDark = Colors.white;
  @Deprecated('use primary')
  static Color get navy => primary;
  @Deprecated('use primaryDeep')
  static Color get navyDeep => primaryDeep;
  static const lavender = stReview; // closest purple equivalent
  static Color get background => canvas;
  static Color get backgroundEnd => canvas2;

  // Brand-tinted foreground for icons/labels sitting ON a theme surface. The
  // raw [primary] is a dark colour and is unreadable on dark surfaces, so
  // this lifts to the rail ink in dark mode.
  static Color get brandInk => _dark ? railInk : primary;

  // Accent foreground for the *active* state — an icon or label on
  // [accentSoft] or on a plain theme surface. In light that is [accentText]:
  // [accentStrong] reaches only 3.0:1 on the canvas and 2.8:1 on the accent
  // wash, the deeper shade 6.1:1 and 5.6:1 (HIN-110, measured on honey; the
  // palette solves the same targets for any tint). On dark, where
  // [accentSoft] is only a faint wash over a near-black surface, the brighter
  // [accent] reads.
  static Color get accentInk => _dark ? palette.accentInkDark : accentText;

  // The wash behind weekends and holidays in the team absence calendar
  // (HIN-118). In dark mode the recessed canvas is nearly black against a card
  // and turned a month into stripes; a breath of white reads as "not a working
  // day" without shouting it.
  static Color get dayOffWash => _dark ? const Color(0x0BFFFFFF) : canvas2Light;

  // Pastel card tints — light & warm on light, muted & dark (white-text safe)
  // on dark, so colourful cards keep their hue without losing legibility.
  static const pastelBlue = Color(0xFFE9EEF8);
  static const pastelLavender = Color(0xFFEFEBF8);
  static const pastelPeach = Color(0xFFF3E9D2); // = accentSoftLight
  static const pastelMint = Color(0xFFE4F2EC);
  static const pastels = [pastelBlue, pastelLavender, pastelPeach, pastelMint];
  static const pastelsDark = [
    Color(0xFF20263A), // blue-slate
    Color(0xFF272138), // lavender
    Color(0xFF2E2716), // amber-brown
    Color(0xFF16291F), // green
  ];
  static Color pastelFor(int index) =>
      (_dark ? pastelsDark : pastels)[index % pastels.length];
  // old accent names → new semantic equivalents
  static const accentPurple = stReview;
  static const accentBlue = stTodo;
  static const accentTeal = stDone;

  /// Maps a workflow state to its signature colour. Accepts both canonical
  /// codes (`IN_PROGRESS`) and human/display variants (`In Progress`, `in-progress`)
  /// by normalising case and any space/underscore/hyphen separators first — so a
  /// column whose `states` carry display names still tints to the theme colour
  /// instead of silently falling through to the backlog slate.
  static Color stateColor(String state) =>
      switch (state.toUpperCase().replaceAll(RegExp(r'[\s_-]+'), '')) {
        'TODO' => stTodo,
        'INPROGRESS' => stProgress,
        'INREVIEW' => stReview,
        'DONE' => stDone,
        'BACKLOG' => stBacklog,
        _ => stBacklog,
      };

  static Color priorityColor(String priority) =>
      switch (priority.toUpperCase()) {
        // Backend Issue.Priority enum.
        'SHOWSTOPPER' || 'CRITICAL' => priUrgent,
        'MAJOR' => priHigh,
        'NORMAL' => priNormal,
        'MINOR' || 'TRIVIAL' => priLow,
        // Legacy aliases.
        'URGENT' => priUrgent,
        'HIGH' => priHigh,
        'LOW' => priLow,
        _ => priLow,
      };

  /// Soft tint of any base color for badge / chip backgrounds (~oklch .96 tint).
  static Color soft(Color base) =>
      Color.alphaBlend(base.withValues(alpha: 0.12), surface);
}
