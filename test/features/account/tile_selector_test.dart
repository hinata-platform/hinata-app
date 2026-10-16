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
}
