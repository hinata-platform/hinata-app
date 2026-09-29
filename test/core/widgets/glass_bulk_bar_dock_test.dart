import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/responsive/responsive.dart';
import 'package:hinata/core/widgets/glass_bulk_bar.dart';

/// Where the bulk-selection bar floats.
///
/// On an iPhone the compact shell publishes the nav pill's top edge, measured
/// from the window edge and so already spanning the home indicator. The page's
/// `bottomGutter` counts that indicator once more for scrolling content, and a
/// bar placed from the gutter hung a whole indicator's height above the nav.
/// Measured from the published edge the gap is 12 everywhere; without a nav the
/// gutter (the safe area alone) is the right thing to clear.
void main() {
  const window = Size(390, 844);
  const bar = Key('bar');

  setUp(ShellInsets.reset);
  tearDown(ShellInsets.reset);

  Future<void> pumpDock(WidgetTester tester, {required double gutter}) async {
    tester.view
      ..physicalSize = window
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          // What the compact shell injects for content: the nav's footprint
          // plus the home indicator.
          data: MediaQueryData(
            size: window,
            padding: EdgeInsets.only(bottom: gutter),
          ),
          child: const Stack(
            children: [
              SizedBox.expand(),
              GlassBulkBarDock(
                child: SizedBox(key: bar, width: 200, height: 48),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('sits 12 above the nav pill the shell published', (tester) async {
    // Pill top edge 96 above the window edge (62 of pill and gap plus a 34
    // home indicator); the gutter adds the indicator again on top of that.
    ShellInsets.publishBottom(Object(), 96);
    await pumpDock(tester, gutter: 96 + 34);

    final rect = tester.getRect(find.byKey(bar));
    expect(window.height - rect.bottom, 96 + 12);
  });

  testWidgets('sits 12 above the safe area where there is no nav', (
    tester,
  ) async {
    await pumpDock(tester, gutter: 34);

    final rect = tester.getRect(find.byKey(bar));
    expect(window.height - rect.bottom, 34 + 12);
  });

  testWidgets('follows the nav as the shell publishes a new edge', (
    tester,
  ) async {
    ShellInsets.publishBottom(Object(), 96);
    await pumpDock(tester, gutter: 130);
    ShellInsets.reset();
    await tester.pump();

    final rect = tester.getRect(find.byKey(bar));
    expect(window.height - rect.bottom, 130 + 12);
  });
}
