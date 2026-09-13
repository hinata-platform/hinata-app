import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/sprint/modals/glass_modal.dart';

void main() {
  Future<void> pumpFooter(WidgetTester tester, double width) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: GlassModalFooter(
                  confirmLabel: 'OK',
                  onConfirm: () {},
                  hint: const Text('Ask for older days'),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('a narrow footer puts its hint on a row above the buttons', (
    tester,
  ) async {
    await pumpFooter(tester, 360);

    expect(
      tester.getBottomLeft(find.text('Ask for older days')).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.text('OK')).dy),
    );
  });

  testWidgets('a wide footer keeps its hint beside the buttons', (
    tester,
  ) async {
    await pumpFooter(tester, 640);

    expect(
      tester.getCenter(find.text('Ask for older days')).dy,
      moreOrLessEquals(tester.getCenter(find.text('OK')).dy, epsilon: 2),
    );
  });
}
