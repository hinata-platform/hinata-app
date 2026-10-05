import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/time/time_module_screen.dart';

/// The module keeps every view it opened built behind the one on screen, with
/// its tickers stopped. A tooltip is painted in the app's overlay but animated
/// by its own view — so one left fading out in a view that was just hidden
/// must finish fading, not stay burnt in over the next one (HIN-110).
void main() {
  Widget module(int index) => MaterialApp(
    home: Scaffold(
      body: IndexedStack(
        index: index,
        sizing: StackFit.expand,
        children: [
          TimeViewBranch(
            visible: index == 0,
            child: const Align(
              alignment: Alignment.topLeft,
              child: Tooltip(
                message: 'Stundenzettel',
                child: SizedBox(key: ValueKey('chip'), width: 40, height: 40),
              ),
            ),
          ),
          TimeViewBranch(visible: index == 1, child: const SizedBox.expand()),
        ],
      ),
    ),
  );

  testWidgets('a tooltip of a view that is hidden is hidden with it', (
    tester,
  ) async {
    await tester.pumpWidget(module(0));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(600, 500));
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('chip'))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Stundenzettel'), findsOneWidget);

    // The click that goes to the next view: the branch is hidden and its
    // tickers stop while the tooltip is still fading out.
    await mouse.down(tester.getCenter(find.byKey(const ValueKey('chip'))));
    await mouse.up();
    await tester.pumpWidget(module(1));
    await mouse.moveTo(const Offset(600, 500));
    await tester.pump(const Duration(seconds: 2));

    // The hidden branch kept ticking long enough for the fade to finish:
    // nothing of the tooltip is left, on screen or off it.
    expect(find.text('Stundenzettel', skipOffstage: false), findsNothing);
  });

  testWidgets('a hidden view stops ticking after the grace', (tester) async {
    await tester.pumpWidget(module(0));
    await tester.pumpWidget(module(1));
    bool ticking() => TickerMode.valuesOf(
      tester.element(find.byKey(const ValueKey('chip'), skipOffstage: false)),
    ).enabled;
    expect(ticking(), isTrue);
    await tester.pump(TimeViewBranch.grace);
    expect(ticking(), isFalse);
  });
}
