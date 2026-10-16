import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:hinata/features/account/account_widgets.dart';

/// The selector behind the style tiles and the Light/Dark/System pills
/// (HIN-150). The old `_ThemeSelector` was a bare GestureDetector: no focus,
/// no keyboard, the active segment told apart by colour alone.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  Future<void> pump(
    WidgetTester tester,
    ValueChanged<String> onChanged, {
    TileSelectorLayout layout = TileSelectorLayout.pill,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TileSelector<String>(
            value: 'a',
            layout: layout,
            onChanged: onChanged,
            options: const [
              TileOption(value: 'a', label: 'Alpha'),
              TileOption(value: 'b', label: 'Beta'),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('is reachable by Tab and toggles with Space', (tester) async {
    String? chosen;
    await pump(tester, (v) => chosen = v);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(chosen, 'b');
  });

  testWidgets('shows a focus ring and a check on the active option', (
    tester,
  ) async {
    await pump(tester, (_) {});
    expect(find.byIcon(Icons.check), findsNothing);
    // The active option carries a check glyph, not only a colour.
    expect(
      find.descendant(
        of: find.byType(TileSelector<String>),
        matching: find.byType(Icon),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = tester.widget<TileSelector<String>>(
      find.byType(TileSelector<String>),
    );
    expect(focused, isNotNull);
    expect(
      tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).any((box) {
        final d = box.decoration;
        return d is BoxDecoration &&
            d.border != null &&
            d.border!.top.color == AppColors.focusRing;
      }),
      isTrue,
    );
  });

  testWidgets('announces as mutually exclusive buttons with selection', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, (_) {});
    expect(
      tester.getSemantics(find.text('Alpha')),
      isSemantics(
        label: 'Alpha',
        isButton: true,
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
        isFocusable: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('hover shows a wash that stays visible and never dips grey', (
    tester,
  ) async {
    await pump(tester, (_) {});
    // The fill of the unselected option's pill, read from what is painted.
    Color fill() {
      final box = tester
          .widgetList<DecoratedBox>(
            find.ancestor(
              of: find.text('Beta'),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((b) => b.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.borderRadius != null && d.color != null);
      return Color.alphaBlend(box.color!, AppColors.surface);
    }

    final rest = fill();
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('Beta')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final midway = fill();
    await tester.pumpAndSettle();
    final hovered = fill();

    double lum(Color c) => c.computeLuminance();
    // Seen on the card: a wash at least as strong as a list row's hover.
    expect(lum(rest) - lum(hovered), greaterThan(0.02));
    // On its way there it passes between rest and hover, never through a
    // darker grey: animating from Colors.transparent (transparent black)
    // flashed grey for a moment, then left a wash nobody could see.
    expect(lum(midway), lessThanOrEqualTo(lum(rest)));
    expect(lum(midway), greaterThanOrEqualTo(lum(hovered)));
    // Hover highlights follow the desktop's pointer mode.
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
