/// The pickers' wheels move with every pointer and take typed values.
///
/// Before, the wheel was a plain scrolling list: a mouse is no drag device on a
/// desktop, and its scroll physics snapped every notch of a mouse wheel back
/// to the row it came from, so on a Mac the time could not be set at all.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/sprint/modals/glass_modal.dart';

void main() {
  late Object? picked;

  Future<void> openTimePicker(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1200, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    picked = null;
    await tester.pumpWidget(
      MaterialApp(
        // Above the navigator, so the modal reads it too: a 24-hour clock.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => picked = await showGlassTimePicker(
                context,
                initial: const TimeOfDay(hour: 9, minute: 0),
                title: 'Start',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  /// The minute wheel: the one that shows `00` in its selected row.
  Finder minuteWheel() => find
      .ancestor(
        of: find.text('00').last,
        matching: find.byType(GestureDetector),
      )
      .first;

  testWidgets('a mouse drag turns the wheel', (tester) async {
    await openTimePicker(tester);

    // Two rows up is two minutes on.
    await tester.drag(
      minuteWheel(),
      const Offset(0, -80),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await confirm(tester);

    expect(picked, const TimeOfDay(hour: 9, minute: 2));
  });

  testWidgets('a finger drag turns the wheel', (tester) async {
    await openTimePicker(tester);

    await tester.drag(minuteWheel(), const Offset(0, -120));
    await tester.pumpAndSettle();
    await confirm(tester);

    expect(picked, const TimeOfDay(hour: 9, minute: 3));
  });

  testWidgets('each notch of a mouse wheel is a row', (tester) async {
    await openTimePicker(tester);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final at = tester.getCenter(minuteWheel());
    for (var notch = 0; notch < 3; notch++) {
      // Twenty pixels: less than half a row, which the old wheel snapped back.
      await tester.sendEventToBinding(pointer.hover(at));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    await confirm(tester);

    expect(picked, const TimeOfDay(hour: 9, minute: 3));
  });

  testWidgets('the arrow keys step a focused wheel', (tester) async {
    await openTimePicker(tester);

    // A tap on the selected row focuses the wheel without moving it.
    await tester.tapAt(tester.getCenter(minuteWheel()));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await confirm(tester);

    expect(picked, const TimeOfDay(hour: 9, minute: 2));
  });

  testWidgets('a typed time takes its colon and turns the wheels', (
    tester,
  ) async {
    await openTimePicker(tester);

    final field = find.byType(TextField);
    await tester.enterText(field, '');
    for (final key in ['2', '1', '4', '5']) {
      final text = tester.widget<TextField>(field).controller!.text + key;
      await tester.enterText(field, text);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(field).controller!.text, '21:45');
    await confirm(tester);
    expect(picked, const TimeOfDay(hour: 21, minute: 45));
  });

  testWidgets('enter in the field confirms the picker', (tester) async {
    await openTimePicker(tester);

    await tester.enterText(find.byType(TextField), '0730');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(picked, const TimeOfDay(hour: 7, minute: 30));
  });

  testWidgets('the duration picker takes a typed duration', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    int? minutes;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => minutes = await showGlassDurationPicker(
                context,
                initialMinutes: 60,
                title: 'Duration',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '1:45');
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(minutes, 105);
  });
}
