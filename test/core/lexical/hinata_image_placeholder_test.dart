import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/lexical/hinata_document.dart';

/// The stand-in for an image that is not shown (HIN-181): a mail gives a logo
/// a 64 px cell, and the placeholder has to fit there and anywhere smaller,
/// without an overflow. Raw i18n keys render.
void main() {
  const src = 'https://www.vodafone.de/images/logo.png';

  Widget cell(Size? size, {double scale = 1}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(800, 600),
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: size == null
              ? SizedBox(
                  width: 390,
                  child: Builder(
                    builder: (context) => hinataImagePlaceholder(context, src),
                  ),
                )
              : SizedBox.fromSize(
                  size: size,
                  child: Builder(
                    builder: (context) => hinataImagePlaceholder(context, src),
                  ),
                ),
        ),
      ),
    ),
  );

  for (final scale in [1.0, 2.0]) {
    for (final size in const [
      Size(40, 40),
      Size(120, 24),
      Size(64, 64),
      Size(10, 10),
      Size(300, 60),
      Size(600, 80),
      Size(600, 300),
    ]) {
      testWidgets('fits a ${size.width}x${size.height} cell at text x$scale', (
        tester,
      ) async {
        await tester.pumpWidget(cell(size, scale: scale));

        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a small cell shows only the icon, and says why to a reader', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(cell(const Size(64, 64)));

    expect(find.text('md.imageFailed'), findsNothing);
    expect(find.bySemanticsLabel('md.imageFailed'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a roomy cell says what failed and where from', (tester) async {
    await tester.pumpWidget(cell(null));

    expect(tester.takeException(), isNull);
    expect(find.text('md.imageFailed'), findsOneWidget);
    expect(find.text(src), findsOneWidget);
  });
}
