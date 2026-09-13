import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/hive_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('a button without an icon shows its label alone', (tester) async {
    await tester.pumpWidget(
      host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GhostButton(label: 'Cancel', onPressed: () {}),
            PrimaryButton(label: 'Save', onPressed: () {}),
          ],
        ),
      ),
    );

    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('a button keeps the icon it is given', (tester) async {
    await tester.pumpWidget(
      host(
        PrimaryButton(label: 'New', icon: LucideIcons.plus, onPressed: () {}),
      ),
    );

    expect(find.byIcon(LucideIcons.plus), findsOneWidget);
  });
}
