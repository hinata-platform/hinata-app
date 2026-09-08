import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/i18n/i18n.dart';
import 'package:hinata/features/sprint/modals/glass_modal.dart';

/// The footer every glass dialog and sheet ends with — and the last thing a
/// reader looks at before they commit to something.
///
/// All three of its children used to be flexible (the leading `Spacer`
/// included), which reads like "shrink if you must" and is not what a Flex
/// does: the row was divided in three and each button capped at a third of it.
/// On a phone that third is about 110 points, the confirm button wants 135, and
/// the word a reader has to trust arrived as "Speic…" — on every sheet in the
/// app, in every language.
///
/// Nothing here asserts a pixel width. The harness renders i18n keys rather
/// than translations, in a test font, so the numbers are nothing like the ones
/// on a device — which is exactly why the widths below are *measured first* and
/// the assertions are about proportion: given a row that can fit the buttons,
/// is the confirm label still whole?
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required double width,
    required String confirmLabel,
    Widget? hint,
  }) async {
    tester.view.physicalSize = Size(width, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: GlassModalFooter(
              confirmLabel: confirmLabel,
              hint: hint,
              onConfirm: () {},
            ),
          ),
        ),
      ),
    );
  }

  /// Whether [text] had to drop characters to fit the box it was given.
  bool isTruncated(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

  /// The width the footer needs before anything has to give: the two buttons
  /// side by side, plus the gap and the container's own padding.
  Future<double> comfortable(WidgetTester tester, String confirmLabel) async {
    await pump(tester, width: 1400, confirmLabel: confirmLabel);
    // By predicate, not by type: `FilledButton.icon` builds a private subclass
    // and `find.byType` matches the runtime type exactly.
    final buttons = find.byWidgetPredicate(
      (widget) => widget is ButtonStyleButton,
    );
    final total =
        tester.getSize(buttons.at(0)).width +
        tester.getSize(buttons.at(1)).width;
    return total + 8 + 44;
  }

  // First in the file on purpose: the asset-backed i18next delegate only
  // resolves in a file's first widget test, and this is the one case that
  // wants the real words rather than the keys the harness otherwise renders.
  testWidgets('"Speichern" is whole on a phone, in German', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: I18n.supportedLocales,
        localizationsDelegates: I18n.delegates(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: GlassModalFooter(
              confirmLabel: 'Speichern',
              onConfirm: () {},
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Abbrechen'), findsOneWidget);
    expect(isTruncated(tester, 'Speichern'), isFalse);
    expect(isTruncated(tester, 'Abbrechen'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the confirm label stays whole in a footer that fits', (
    tester,
  ) async {
    const label = 'Speichern';
    final width = await comfortable(tester, label);

    await pump(tester, width: width, confirmLabel: label);

    expect(isTruncated(tester, label), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hint never costs the confirm button its label', (
    tester,
  ) async {
    const label = 'Speichern';
    final width = await comfortable(tester, label);

    await pump(
      tester,
      width: width,
      confirmLabel: label,
      hint: const Text(
        'Ein ziemlich langer Hinweis, der die ganze Zeile für sich '
        'beanspruchen würde, wenn man ihn ließe.',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );

    expect(isTruncated(tester, label), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a footer too narrow for both shortens cancel, not confirm', (
    tester,
  ) async {
    const label = 'Speichern';
    final width = await comfortable(tester, label);

    // Two thirds of what the pair needs: something has to give, and it is the
    // button that is not asking anyone to commit to anything.
    await pump(tester, width: width * 0.66, confirmLabel: label);

    expect(isTruncated(tester, label), isFalse);
    expect(
      isTruncated(tester, 'common.cancel'),
      isTrue,
      reason: 'cancel is the one that yields — otherwise the row overflows',
    );
    expect(tester.takeException(), isNull);
  });
}
