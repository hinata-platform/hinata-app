import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/theme/tint_palette.dart';
import 'package:hinata/core/widgets/hue_slider.dart';

/// The two sliders of the tint (HIN-150). Flutter's Slider brings keyboard,
/// focus and semantics; what is pinned here is that a step is five degrees,
/// that a reader hears a colour name and not a percentage, and that the hit
/// area is a thumb's worth.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  testWidgets('hue steps five degrees per arrow key and speaks its value key', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var hue = 150;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => HueSlider(
              hue: hue,
              level: 100,
              onChanged: (v) => setState(() => hue = v),
            ),
          ),
        ),
      ),
    );
    expect(_spokenValue(tester), contains('account.tint.hueValue'));
    // Tab, not tap: a tap would move the thumb to the pointer first.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(hue, 155);
    final box = tester.getSize(find.byType(HueSlider));
    expect(box.height, greaterThanOrEqualTo(48));
    handle.dispose();
  });

  testWidgets(
    'level speaks its value key, and the hint names clear glass at zero',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LevelSlider(hue: 79, level: 0, onChanged: (_) {}),
          ),
        ),
      );
      final value = _spokenValue(tester);
      expect(value, contains('account.tint.levelValue'));
      handle.dispose();
      // The hint the formatter interpolates (tests render raw keys).
      expect(LevelSlider.hintKey(0), 'account.tint.levelClear');
      expect(LevelSlider.hintKey(50), 'account.tint.levelMid');
      expect(LevelSlider.hintKey(100), 'account.tint.levelStrong');
    },
  );

  test('the spectrum track caches its stops per level', () {
    final a = SpectrumTrackShape.stopsFor(100);
    final b = SpectrumTrackShape.stopsFor(100);
    expect(identical(a, b), isTrue);
    expect(a.length, greaterThan(12));
    expect(identical(a, SpectrumTrackShape.stopsFor(50)), isFalse);
  });

  test('the spectrum shows the colour the tint will be', () {
    // One stop every ten degrees: index 3 is 30 degrees, the red.
    final red = SpectrumTrackShape.stopsFor(100)[3];
    expect(red.r, greaterThanOrEqualTo(0.95));
    expect(red.g, lessThanOrEqualTo(0.35));
    expect(
      red,
      TintPalette.of(
        const TintPreferences(style: TintStyle.tinted, hue: 30, level: 100),
      ).accent,
    );
  });
}

/// The value a reader hears for the one slider on screen.
String _spokenValue(WidgetTester tester) {
  final root = tester
      .renderObject(find.byType(Scaffold))
      .owner!
      .semanticsOwner!
      .rootSemanticsNode!;
  String? found;
  void walk(SemanticsNode node) {
    if (node.value.isNotEmpty && found == null) found = node.value;
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(root);
  return found ?? '';
}
