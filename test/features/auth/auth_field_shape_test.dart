import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:hinata/core/theme/field_border.dart';
import 'package:hinata/features/auth/auth_shell.dart';

/// The sign-in fields are the one place in Hinata that keeps the outlined
/// shape: one line tall, the label riding on the rim.
///
/// Everywhere else a field carries its label inside itself, which reserves a
/// second line for it. On a sign-in card that turns a field holding one word
/// into a slab, and the published app does not look like that.
void main() {
  Future<InputDecorationThemeData> themeInside(
    WidgetTester tester, {
    required bool dark,
  }) async {
    late InputDecorationThemeData inside;
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: Scaffold(
          body: AuthGlassCard(
            child: Builder(
              builder: (context) {
                inside = Theme.of(context).inputDecorationTheme;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return inside;
  }

  testWidgets('the card hands its fields an outlined rim', (tester) async {
    for (final dark in [false, true]) {
      final inside = await themeInside(tester, dark: dark);
      expect(inside.border, isA<OutlineInputBorder>());
      expect(inside.enabledBorder, isA<OutlineInputBorder>());
      expect(inside.focusedBorder, isA<OutlineInputBorder>());
      expect(inside.errorBorder, isA<OutlineInputBorder>());
      // And not the app-wide shape, which is what made them two lines tall.
      expect(inside.border, isNot(isA<HiveFieldBorder>()));
      // The caption style belongs to a label that sits inside a field. On the
      // rim it would print the label at a caption's size and weight.
      expect(inside.floatingLabelStyle, isNull);
      // The fill is the app's, so the card still looks like the rest of it.
      expect(inside.filled, isTrue);
    }
  });

  testWidgets('everywhere else keeps the label inside the field', (
    tester,
  ) async {
    // The guard on the other side: this is a local opt-out, not a change of
    // the app's field shape.
    expect(
      AppTheme.light().inputDecorationTheme.border,
      isA<HiveFieldBorder>(),
    );
  });
}
