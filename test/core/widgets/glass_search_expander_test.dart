import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/glass_filter_bar.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The search a page head carries.
///
/// A head is a title, a switcher and a button on one line, so the field is not
/// there until it is asked for. Two things have to hold for that to be honest:
/// leaving the search has to clear it — a field that is gone cannot say what it
/// is still filtering by — and the closed pill has to show that something is
/// still in force, for the window that was wide, had something typed into it,
/// and then narrowed.
void main() {
  late TextEditingController controller;
  late List<String> changes;

  setUp(() {
    controller = TextEditingController();
    changes = [];
  });

  tearDown(() => controller.dispose());

  Widget host({double width = 700}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: _Host(controller: controller, onChanged: changes.add),
        ),
      ),
    ),
  );

  testWidgets('it is a pill until it is asked for', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byType(GlassSearchButton), findsOneWidget);
    expect(find.byType(GlassSearchField), findsNothing);

    await tester.tap(find.byType(GlassSearchButton));
    await tester.pumpAndSettle();

    expect(find.byType(GlassSearchField), findsOneWidget);
    expect(find.byType(GlassSearchButton), findsNothing);
  });

  testWidgets('closing it clears what was typed', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byType(GlassSearchButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hin');
    await tester.pumpAndSettle();
    expect(changes, ['hin']);

    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();

    // The page is told the query is gone before it is told the search is over,
    // so it never repaints a filtered list with no field to explain it.
    expect(changes.last, '');
    expect(controller.text, '');
    expect(find.byType(GlassSearchButton), findsOneWidget);
  });

  /// A page head: a title that takes what is left, then the actions, hard
  /// against the trailing edge.
  Widget head({required double width, bool open = true}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: Row(
            key: const Key('head'),
            children: [
              const Expanded(child: Text('Projects')),
              _Host(
                // A fresh state per case: the host latches `open` at init, so
                // reusing the element would leave the search as it was.
                key: ValueKey(open),
                controller: controller,
                onChanged: changes.add,
                open: open,
              ),
              const SizedBox(key: Key('button'), width: 180, height: 42),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('the actions stay against the edge, open or closed', (
    tester,
  ) async {
    // The search is an ordinary child of the head's Row, never a flex one. A
    // flex child is handed its share of the free space whether it fills it or
    // not, and MainAxisAlignment.start leaves the unused part *after* it — so
    // flexing would park the search in a reserved gap and push everything
    // beside it away from the edge the actions belong to.
    for (final open in [false, true]) {
      await tester.pumpWidget(head(width: 780, open: open));
      await tester.pumpAndSettle();

      final row = tester.getRect(find.byKey(const Key('head')));
      final search = tester.getRect(
        open ? find.byType(GlassSearchField) : find.byType(GlassSearchButton),
      );
      final button = tester.getRect(find.byKey(const Key('button')));
      expect(
        search.right,
        lessThanOrEqualTo(button.left),
        reason: 'open: $open',
      );
      expect(
        button.right,
        moreOrLessEquals(row.right, epsilon: 0.5),
        reason: 'open: $open',
      );
    }
  });

  testWidgets('in a head it asks for width and settles for what is left', (
    tester,
  ) async {
    await tester.pumpWidget(head(width: 780));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(GlassSearchField)).width, lessThan(360));

    // The case a fixed width breaks: a window barely past the phone breakpoint
    // still has a title, a button and now a field on one line.
    await tester.pumpWidget(head(width: 420));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(GlassSearchField)).width, greaterThan(0));
  });

  testWidgets('a query left in force keeps the pill lit', (tester) async {
    controller.text = 'hin';
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final pill = tester.widget<GlassSearchButton>(
      find.byType(GlassSearchButton),
    );
    expect(pill.active, isTrue);
  });
}

/// The page around the field: it owns whether the search is open, exactly as a
/// screen does.
class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.controller,
    required this.onChanged,
    this.open = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  /// Whether the search starts open, for the cases that are about the field
  /// rather than about opening it.
  final bool open;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool _searching = widget.open;

  @override
  Widget build(BuildContext context) => GlassSearchExpander(
    searching: _searching,
    hint: 'search',
    controller: widget.controller,
    onChanged: widget.onChanged,
    onOpen: () => setState(() => _searching = true),
    onClose: () => setState(() => _searching = false),
  );
}
