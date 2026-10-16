import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'field_border.dart';
import 'glass_buttons.dart';
import 'app_type.dart';
import 'tint_palette.dart';

/// Hinata "Hive" Material theme — redesign 2026.
///
/// Key shifts from the old pastel-glassmorphism theme:
///   • Tighter radii: cards 14 (was 28), controls 10 — crisp, not bubbly.
///   • Hairline borders + a whisper of shadow instead of heavy soft cards.
///   • Warm-paper canvas (#F4F3EF) instead of lavender-grey.
///   • Sora is reserved for display/headings; IBM Plex Sans drives dense UI,
///     IBM Plex Mono renders issue IDs & numeric metrics.
///   • Honey-amber accent used for highlights/active/focus.
abstract final class AppTheme {
  static const radiusCard = 14.0;
  static const radiusControl = 10.0;
  static const radiusPill = 999.0;

  /// The corners of every overlay, in one place to tweak.
  ///
  /// [radiusDialog]: modal dialogs, confirmations, pickers in a dialog,
  /// bottom sheets, the search palette and side panels.
  /// [radiusPopover]: what opens beside the thing that was clicked, the
  /// anchored popovers, menus, filter panels and suggestion lists.
  /// Rounder than the cards (14) on purpose: glass that floats over the page
  /// reads as a separate layer, as in iOS 27.
  static const radiusDialog = 34.0;
  static const radiusPopover = 26.0;

  static const fontBrand = 'Sora'; // headings, wordmark
  static const fontUi = 'IBMPlexSans'; // body / dense UI
  static const fontMono = 'IBMPlexMono'; // ids, metrics

  static ThemeData light({TintPalette? palette}) =>
      _build(Brightness.light, palette ?? TintPalette.standard);
  static ThemeData dark({TintPalette? palette}) =>
      _build(Brightness.dark, palette ?? TintPalette.standard);

  /// Builds the Material theme for [brightness] and [palette]. Neutral
  /// surface/ink values are read from the explicit per-theme [AppColors]
  /// constants and the brand values from the palette handed in (NOT the
  /// runtime `AppColors.<token>` getters) so each [ThemeData] is
  /// deterministic regardless of what is active when it's constructed.
  static ThemeData _build(Brightness brightness, TintPalette palette) {
    final dark = brightness == Brightness.dark;

    final canvas = dark ? AppColors.canvasDark : AppColors.canvasLight;
    final surface = dark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final surfaceMuted = dark
        ? AppColors.surfaceMutedDark
        : AppColors.surfaceMutedLight;
    final ink = dark ? AppColors.inkDark : AppColors.inkLight;
    final inkSoft = dark ? AppColors.inkSoftDark : AppColors.inkSoftLight;
    final inkFaint = dark ? AppColors.inkFaintDark : AppColors.inkFaintLight;
    final hairline = dark ? AppColors.hairlineDark : AppColors.hairlineLight;
    final hairline2 = dark ? AppColors.hairline2Dark : AppColors.hairline2Light;
    final accentSoft = dark ? palette.accentSoftDark : palette.accentSoftLight;
    final focusRing = dark ? palette.focusRingDark : palette.focusRingLight;

    final scheme = ColorScheme.fromSeed(
      seedColor: palette.primary,
      brightness: brightness,
      primary: dark ? palette.accent : palette.primary,
      secondary: palette.accent,
      surface: surface,
      error: AppColors.danger,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontUi,
    );
    final text = base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontFamily: fontBrand,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: ink,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontFamily: fontBrand,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        );

    HiveFieldBorder border(Color c, [double w = 1]) => HiveFieldBorder(
      borderRadius: BorderRadius.circular(radiusControl),
      borderSide: BorderSide(color: c, width: w),
    );

    return base.copyWith(
      scaffoldBackgroundColor: canvas,
      textTheme: text,
      dividerColor: hairline,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: hairline),
        ),
        margin: EdgeInsets.zero,
      ),
      // Capsules lit from above, one source for all three: [GlassButtons].
      filledButtonTheme: FilledButtonThemeData(
        style: GlassButtons.filled(brightness, palette),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: GlassButtons.outlined(brightness),
      ),
      textButtonTheme: TextButtonThemeData(
        style: GlassButtons.text(brightness, palette),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: border(hairline),
        enabledBorder: border(hairline),
        // The focus ring, not the accent: honey on white is 2.3:1 (1.4.11).
        focusedBorder: border(focusRing, 1.5),
        hintStyle: TextStyle(color: inkFaint),
        // The label rides inside the field (see [HiveFieldBorder]), so it wants
        // the size and weight of a caption rather than of a second value.
        floatingLabelStyle: TextStyle(
          fontSize: AppType.body,
          fontWeight: FontWeight.w600,
          color: inkSoft,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceMuted,
        side: BorderSide(color: hairline2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        labelStyle: TextStyle(color: inkSoft, fontSize: AppType.caption),
      ),
      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
      // The few Material dialogs and menus left (an AlertDialog, a
      // DropdownButton) wear the overlay corners of the glass ones.
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusDialog)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radiusDialog),
          ),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusPopover)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accentSoft,
        labelTextStyle: WidgetStatePropertyAll(
          text.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: palette.rail,
        indicatorColor: const Color(0x14FFFFFF),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.primaryDeep,
        // The surface is deep navy in both themes, so the content must stay
        // light — otherwise dark mode inherits a dark on-surface text colour and
        // the message reads near-invisible.
        contentTextStyle: const TextStyle(
          color: Color(0xFFECEBF3),
          fontFamily: fontUi,
          fontSize: AppType.label,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: palette.accent,
        behavior: SnackBarBehavior.floating,
        width: 360,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusControl),
        ),
      ),
    );
  }
}
