import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_theme.dart';
import 'field_border.dart';

/// How much of the app's paper a form on glass stands on.
///
/// A form is dense — captions, values, a counter, a hint — and it floats over
/// whatever the app shows behind it. On the thin glass fill alone its fields
/// read as grey on grey. So a form stands on a thick wash of the app's own
/// paper (iOS calls it the thick material); the rim, the soft edge and the
/// shadow keep it glass.
///
/// The phone sheet covers the app edge to edge and has nothing but the app
/// behind it, so it takes the thicker wash. The dialog floats over a dimmed,
/// blurred app that is already calm, and at the sheet's thickness it read as
/// a solid card — it keeps enough of the glass to show it is glass.
double glassFormWashAlpha({required bool dark, bool dialog = false}) =>
    dialog ? (dark ? 0.62 : 0.64) : (dark ? 0.84 : 0.88);

/// The one look of a form field on glass: no fill, a rim of translucent ink,
/// and a caption strong enough to read.
///
/// Every field in a glass form — a text field, a picker button, a person
/// field — is drawn from these values, so a form never shows a white box next
/// to a clear one. The fill stays out on purpose: an opaque field is a hole in
/// the glass, and in the dark theme it was a dark hole.
abstract final class GlassFieldStyle {
  static BorderRadius get radius =>
      BorderRadius.circular(AppTheme.radiusControl);

  /// The rim at rest.
  static Color get rim => AppColors.fieldRim;

  /// The caption above a value ("Tag", "Art der Abwesenheit").
  static TextStyle get caption => TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    color: AppColors.inkSoft,
  );

  /// A chosen value.
  static TextStyle get value => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );

  /// What a field says while nothing is chosen.
  static TextStyle get placeholder => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.inkSoft,
  );

  /// The rim as a box border, for fields that are buttons.
  static BoxDecoration get decoration => BoxDecoration(
    borderRadius: radius,
    border: Border.all(color: rim),
  );

  /// [base] with the glass field look laid over it — the theme a glass form
  /// hands its text fields, so each of them is transparent without saying so.
  static InputDecorationThemeData inputTheme(InputDecorationThemeData base) {
    HiveFieldBorder rimOf(Color color, [double width = 1]) => HiveFieldBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: color, width: width),
    );
    return base.copyWith(
      filled: false,
      fillColor: Colors.transparent,
      border: rimOf(rim),
      enabledBorder: rimOf(rim),
      disabledBorder: rimOf(rim.withValues(alpha: rim.a * 0.5)),
      focusedBorder: rimOf(AppColors.accent, 1.5),
      errorBorder: rimOf(AppColors.danger),
      focusedErrorBorder: rimOf(AppColors.danger, 1.5),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w500,
        color: AppColors.inkSoft,
      ),
      floatingLabelStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.inkSoft,
      ),
      hintStyle: TextStyle(color: AppColors.inkSoft),
      helperStyle: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
      counterStyle: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
    );
  }
}

/// Gives every text field below it the glass field look.
///
/// Laid in by the glass presenters (dialog, sheet, popover), so no form has to
/// remember it. A call site that sets its own `border` or `filled` still wins —
/// which is why the forms in this app do not.
class GlassFormTheme extends StatelessWidget {
  const GlassFormTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: GlassFieldStyle.inputTheme(
          theme.inputDecorationTheme,
        ),
      ),
      child: child,
    );
  }
}
