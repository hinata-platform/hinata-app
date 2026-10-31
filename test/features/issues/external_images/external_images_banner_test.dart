import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/issues/external_images/external_images_banner.dart';

/// The question a mail program asks before it shows a sender's images
/// (HIN-181). Raw i18n keys render.
void main() {
  Widget band({
    String? sender = 'vodafone.com',
    VoidCallback? onLoadOnce,
    VoidCallback? onTrust,
    double scale = 1,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        body: ExternalImagesBanner(
          sender: sender,
          onLoadOnce: onLoadOnce ?? () {},
          onTrust: onTrust ?? () {},
        ),
      ),
    ),
  );

  testWidgets('offers to load once or to trust the sender', (tester) async {
    var once = false;
    var trusted = false;
    await tester.pumpWidget(
      band(onLoadOnce: () => once = true, onTrust: () => trusted = true),
    );

    expect(find.text('issues.externalImages.blocked'), findsOneWidget);
    await tester.tap(find.text('issues.externalImages.loadOnce'));
    await tester.tap(find.text('issues.externalImages.trust'));
    expect(once, isTrue);
    expect(trusted, isTrue);
    for (final button in [OutlinedButton, FilledButton]) {
      expect(
        tester.getSize(find.byType(button)).height,
        greaterThanOrEqualTo(48),
      );
    }
  });

  testWidgets('without a sender there is nobody to trust', (tester) async {
    await tester.pumpWidget(band(sender: null));

    expect(find.text('issues.externalImages.loadOnce'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('wraps instead of clipping at twice the text size', (
    tester,
  ) async {
    await tester.pumpWidget(band(scale: 2));

    expect(tester.takeException(), isNull);
  });
}
