/// The glass dropdown, and the one thing about it that is not visual.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/glass_popup_menu.dart';

void main() {
  Future<void> pumpMenu(
    WidgetTester tester, {
    required ValueChanged<bool> onOpenChanged,
    required ValueChanged<String> onSelected,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GlassPopupMenu<String>(
              value: 'eins',
              onSelected: onSelected,
              onOpenChanged: onOpenChanged,
              items: const [
                GlassMenuItem<String>(value: 'eins', label: 'Eins'),
                GlassMenuItem<String>(value: 'zwei', label: 'Zwei'),
              ],
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('reports when it is open, and when it is not', (tester) async {
    // What this is for: an anchor that shares the screen with something
    // floating of its own — the editor's selection overlay points at the same
    // words the menu opens over — and nothing else can know when to step
    // aside.
    final events = <bool>[];
    await pumpMenu(tester, onOpenChanged: events.add, onSelected: (_) {});

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    expect(events, [true]);

    await tester.tap(find.text('Zwei'));
    await tester.pumpAndSettle();
    expect(events, [true, false]);
  });

  testWidgets('reports the close even when nothing was chosen', (tester) async {
    // Dismissed on the barrier. Whatever stepped aside has to be told to come
    // back, or it never returns.
    final events = <bool>[];
    var picked = 0;
    await pumpMenu(
      tester,
      onOpenChanged: events.add,
      onSelected: (_) => picked++,
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(events, [true, false]);
    expect(picked, 0);
  });

  testWidgets('a submenu row opens a card whose rows report their value', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GlassPopupMenu<String>(
              value: '',
              onSelected: (value) => picked = value,
              itemsBuilder: (_) => const [
                GlassMenuItem<String>(
                  value: '',
                  label: 'Export',
                  submenu: [
                    GlassMenuItem<String>(value: 'pdf', label: 'PDF'),
                    GlassMenuNote<String>(label: 'Nur lesen', caption: true),
                  ],
                ),
                GlassMenuItem<String>(value: 'clone', label: 'Clone'),
              ],
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    expect(find.text('PDF'), findsNothing);

    // Choosing the row opens its card instead of answering.
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Nur lesen'), findsOneWidget);

    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    expect(picked, 'pdf');
    expect(find.text('PDF'), findsNothing);
  });

  testWidgets('the page takes taps again as soon as the menu starts closing', (
    tester,
  ) async {
    // The spring behind the menu runs on, sub-pixel, for most of a second
    // after the glass has folded back. The page must not wait for it.
    var pageTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 0,
                bottom: 0,
                child: TextButton(
                  onPressed: () => pageTaps++,
                  child: const Text('page'),
                ),
              ),
              Positioned(
                right: 20,
                top: 20,
                child: GlassPopupMenu<String>(
                  value: '',
                  onSelected: (_) {},
                  items: const [
                    GlassMenuItem<String>(value: 'a', label: 'Eins'),
                  ],
                  child: const Text('trigger'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eins'));
    // The spring starts on the next frame; 200 ms on, the glass has passed the
    // point where the package drops its own dismiss barrier (about 150 ms),
    // and is still folding back.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('page'));
    expect(pageTaps, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('opens at its anchor under a notch, not a safe area lower', (
    tester,
  ) async {
    // An iPhone with a Dynamic Island: 59 pt of top inset, 34 pt at the
    // bottom. The package keeps the menu out of that inset itself; adding it
    // again pushed every menu 59 pt below the control that opened it.
    final dpr = tester.view.devicePixelRatio;
    tester.view.padding = FakeViewPadding(top: 59 * dpr, bottom: 34 * dpr);
    addTearDown(tester.view.resetPadding);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                right: 20,
                top: 74,
                child: GlassPopupMenu<String>(
                  value: '',
                  onSelected: (_) {},
                  items: const [
                    GlassMenuItem<String>(value: 'a', label: 'Eins'),
                    GlassMenuItem<String>(value: 'b', label: 'Zwei'),
                  ],
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(child: Text('trigger')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    // The menu lies over the control it came from: its first row starts at
    // the anchor's top plus the menu's own inner padding.
    final firstRow = tester.getRect(find.text('Eins'));
    expect(firstRow.top, lessThan(74 + 40));
  });
}
