import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/hover_builder.dart';
import 'package:hinata/features/sprint/modals/glass_modal.dart';

void main() {
  testWidgets('a glass segment lights up under a mouse and shows the hand', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlassSegmented(
            labels: const ['Alpha', 'Beta'],
            selected: 0,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    Color? fill() => tester
        .widgetList<AnimatedContainer>(
          find.ancestor(
            of: find.text('Beta'),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .first;

    expect(fill(), isNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Beta')));
    await tester.pumpAndSettle();

    expect(fill(), hoverWash());
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );

    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(fill(), isNull);
  });
}
