import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/sprint/modals/glass_modal.dart';

/// A field that shows a choice and opens it beside itself: a screen reader
/// hears its name and the choice once, as a button it can activate.
void main() {
  testWidgets('it is a button a screen reader opens', (tester) async {
    final semantics = tester.ensureSemantics();
    final opened = <Rect?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlassChoiceField(
            label: 'Worum geht es?',
            value: 'Spam',
            onOpen: opened.add,
          ),
        ),
      ),
    );

    final field = find.bySemanticsLabel('Worum geht es?');
    expect(
      tester.getSemantics(field),
      isSemantics(
        isButton: true,
        hasTapAction: true,
        label: 'Worum geht es?',
        value: 'Spam',
      ),
    );

    tester.semantics.tap(find.semantics.byLabel('Worum geht es?'));
    await tester.pump();
    expect(opened, hasLength(1));
    semantics.dispose();
  });
}
