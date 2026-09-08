import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/glass_filter_bar.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The one docked row a page is allowed, and the search that borrows it.
///
/// The rule behind this widget: the blurred band above a page holds the app
/// bar's own title row plus one more. A search field and a row of filters is
/// three lines, so the field arrives only when it is asked for — and leaving it
/// has to clear the query, or the list stays cut down with nothing on screen to
/// say why.
void main() {
  late TextEditingController controller;
  setUp(() => controller = TextEditingController());
  tearDown(() => controller.dispose());

  Widget host({
    required bool searching,
    required VoidCallback onClose,
    ValueChanged<String>? onChanged,
  }) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SizedBox(
        height: kGlassDockRow,
        child: GlassSearchDock(
          searching: searching,
          hint: 'Search entries',
          controller: controller,
          onChanged: onChanged ?? (_) {},
          onClose: onClose,
          controls: Row(
            children: [
              GlassSearchButton(tooltip: 'Search', onTap: () {}),
              const SizedBox(width: 8),
              const GlassCountPill(label: '12 events'),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('the row shows the controls until a search is asked for', (
    tester,
  ) async {
    await tester.pumpWidget(host(searching: false, onClose: () {}));
    await tester.pumpAndSettle();

    expect(find.byType(GlassSearchButton), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('and gives the whole row to the field once it is', (
    tester,
  ) async {
    await tester.pumpWidget(host(searching: true, onClose: () {}));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Search entries'), findsOneWidget);
    expect(
      find.byType(GlassSearchButton),
      findsNothing,
      reason: 'the button it came from has given up its place',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).autofocus,
      isTrue,
      reason: 'a search mode you asked for is one you can type into',
    );
  });

  testWidgets('closing it clears the query and tells the page', (tester) async {
    var closed = 0;
    final changes = <String>[];
    controller.text = 'parser';
    await tester.pumpWidget(
      host(searching: true, onClose: () => closed++, onChanged: changes.add),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();

    expect(controller.text, isEmpty);
    expect(changes, ['']);
    expect(closed, 1);
  });

  testWidgets('a field left empty does not report a change on the way out', (
    tester,
  ) async {
    var closed = 0;
    final changes = <String>[];
    await tester.pumpWidget(
      host(searching: true, onClose: () => closed++, onChanged: changes.add),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();

    expect(changes, isEmpty, reason: 'nothing was filtered, nothing to reload');
    expect(closed, 1);
  });
}
