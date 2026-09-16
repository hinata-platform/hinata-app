/// What a glass dialog costs while it opens and closes.
///
/// The panel is a glass surface sampling the backdrop, and the scrim below it
/// is a full-screen [BackdropFilter] over the same backdrop. A gaussian whose
/// sigma changes cannot be reused between frames, and the sigma used to change
/// on every frame of the transition — a second full-screen blur, recomputed
/// twenty times on the way in and twenty more on the way out, for a ramp the
/// eye has stopped following after the first few frames.
///
/// So the blur reaches full strength early and then holds, in whole pixels.
/// Neither is visible; both are the difference between a dialog that opens and
/// one that thinks about it. These tests are the guard on that, because it is
/// exactly the kind of property that comes back the next time somebody tidies
/// the scrim.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/sprint/modals/glass_modal.dart';

void main() {
  /// The scrim's sigma this frame, or null while it paints no blur at all.
  double? sigma(WidgetTester tester) {
    final filters = tester
        .widgetList<BackdropFilter>(find.byType(BackdropFilter))
        .map((widget) => widget.filter)
        .whereType<ui.ImageFilter>()
        .toList();
    if (filters.isEmpty) return null;
    // `ImageFilter.blur` prints its sigmas; there is no accessor for them.
    final match = RegExp(
      r'blur\(([0-9.]+)',
    ).firstMatch(filters.first.toString());
    return match == null ? null : double.parse(match.group(1)!);
  }

  /// Every sigma the scrim stood at, frame by frame, while [run] plays out.
  Future<List<double?>> track(
    WidgetTester tester,
    Future<void> Function() run,
  ) async {
    final seen = <double?>[];
    await run();
    // Well past either duration; the loop stops recording once nothing moves.
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      seen.add(sigma(tester));
    }
    return seen;
  }

  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1200, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showGlassModal<void>(
                context,
                builder: (_) => const Text('body'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the blur settles long before the dialog has finished opening', (
    tester,
  ) async {
    await open(tester);
    final seen = await track(tester, () async {
      await tester.tap(find.text('open'));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    final values = seen.whereType<double>().toList();
    expect(values, isNotEmpty, reason: 'the scrim never blurred');

    // Whole pixels: a repeated sigma is an ImageFilter that compares equal, and
    // an equal filter is a repaint the render object skips.
    for (final value in values) {
      expect(value, value.roundToDouble(), reason: 'fractional sigma $value');
    }

    // A handful of distinct values across the whole transition, not one per
    // frame — and the last stretch of it stands still.
    expect(values.toSet().length, lessThanOrEqualTo(8));
    expect(values.last, values[values.length ~/ 2], reason: 'still climbing');
  });

  testWidgets('closing is quicker than opening', (tester) async {
    await open(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsOneWidget);

    var frames = 0;
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pump();
    while (find.text('body').evaluate().isNotEmpty && frames < 40) {
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
    }
    await tester.pumpAndSettle();

    expect(find.text('body'), findsNothing);
    // 130 ms at 16 ms a frame. Opening takes 180; a dialog you have dismissed
    // should not keep you waiting as long as one you asked for.
    expect(frames, lessThanOrEqualTo(9));
  });
}
