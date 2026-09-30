import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/folded_hint.dart';
import 'package:hinata/core/widgets/info_circle_button.dart';

/// Long explanations stay one tap away instead of filling the page: a hint
/// shows while it fits on one line and folds behind an "i" once it does not.
/// The decision is measured at the width and text scale the hint really gets.
void main() {
  const short = 'Gilt für neue Fristen.';
  const long =
      'Ob die Organisation in Kalendertagen oder Werktagen rechnet: für neue '
      'relative Fristen und als Standard für Benachrichtigungszeiten.';
  const style = TextStyle(fontSize: 12);

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double width = 300,
    double scale = 1,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );

  group('FoldedHint', () {
    testWidgets('shows a hint that fits in full, without an "i"', (
      tester,
    ) async {
      await pump(tester, const FoldedHint(short, style: style));
      expect(find.text(short), findsOneWidget);
      expect(find.byType(InfoRing), findsNothing);
    });

    testWidgets('folds a longer hint to one line and opens it on tap', (
      tester,
    ) async {
      await pump(
        tester,
        const FoldedHint(long, style: style, title: 'Zählweise'),
      );
      expect(find.byType(InfoRing), findsOneWidget);
      final line = tester.widget<Text>(find.text(long));
      expect(line.maxLines, 1);
      expect(line.overflow, TextOverflow.ellipsis);
      expect(tester.getSize(find.byType(FoldedHint)).height, lessThan(40));

      await tester.tap(find.byType(FoldedHint));
      await tester.pumpAndSettle();
      expect(find.text('Zählweise'), findsOneWidget);
      expect(find.text(long), findsNWidgets(2));
    });

    testWidgets('folds a fitting hint at 200 % text', (tester) async {
      await pump(tester, const FoldedHint(short, style: style), scale: 2);
      expect(find.byType(InfoRing), findsOneWidget);
    });
  });

  group('TitledHint', () {
    Widget titled(String hint) => TitledHint(
      title: 'Zählweise',
      titleStyle: const TextStyle(fontSize: 15),
      hint: hint,
      hintStyle: style,
    );

    testWidgets('keeps a one-line hint under the title', (tester) async {
      await pump(tester, titled(short));
      expect(find.text('Zählweise'), findsOneWidget);
      expect(find.text(short), findsOneWidget);
      expect(find.byType(InfoCircleButton), findsNothing);
    });

    testWidgets('moves a longer hint behind an "i" beside the title', (
      tester,
    ) async {
      await pump(tester, titled(long));
      expect(find.text(long), findsNothing);
      expect(find.byType(InfoCircleButton), findsOneWidget);

      await tester.tap(find.byType(InfoCircleButton));
      await tester.pumpAndSettle();
      expect(find.text(long), findsOneWidget);
    });

    testWidgets('is just the title without a hint', (tester) async {
      await pump(tester, titled(''));
      expect(find.text('Zählweise'), findsOneWidget);
      expect(find.byType(InfoCircleButton), findsNothing);
    });
  });
}
