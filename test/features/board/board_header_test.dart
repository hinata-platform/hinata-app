/// The glass controls both boards wear at their head.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/glass_filter_bar.dart';
import 'package:hinata/core/widgets/glass_switch_chip.dart';
import 'package:hinata/core/widgets/hive_widgets.dart' show SegmentItem;
import 'package:hinata/features/board/board_header.dart';
import 'package:hinata/features/board/board_swimlanes.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    );
  }

  GlassPill pillIn(WidgetTester tester, Finder of) => tester.widget<GlassPill>(
    find.descendant(of: of, matching: find.byType(GlassPill)),
  );

  group('the filter pill', () {
    testWidgets('is plain glass while nothing is filtered', (tester) async {
      await pump(tester, BoardFilterPill(count: 0, onTap: (_) {}));

      expect(pillIn(tester, find.byType(BoardFilterPill)).active, isFalse);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('washes amber and counts the criteria in force', (
      tester,
    ) async {
      // A board cut down to one person's cards must not look like a board with
      // nothing else on it.
      await pump(tester, BoardFilterPill(count: 2, onTap: (_) {}));

      expect(pillIn(tester, find.byType(BoardFilterPill)).active, isTrue);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('hands the popover its own rectangle to hang from', (
      tester,
    ) async {
      // On a phone the shell's app bar draws the pill, where no key the page
      // holds can find it.
      Rect? anchor;
      await pump(
        tester,
        BoardFilterPill(count: 0, onTap: (rect) => anchor = rect),
      );

      await tester.tap(find.byType(BoardFilterPill));

      expect(anchor, tester.getRect(find.byType(GlassPill)));
    });
  });

  group('the docked row', () {
    Widget host(
      TextEditingController controller,
      List<String> queries, {
      bool canSearch = true,
    }) {
      var searching = false;
      return StatefulBuilder(
        builder: (context, setState) => SizedBox(
          width: 390,
          height: kBoardDockHeight,
          child: BoardHeaderDock(
            switcher: const Text('views'),
            tools: const [Text('tools')],
            canSearch: canSearch,
            searching: searching,
            searchController: controller,
            onSearchChanged: queries.add,
            onSearchOpen: () => setState(() => searching = true),
            onSearchClose: () => setState(() => searching = false),
          ),
        ),
      );
    }

    testWidgets('trades its tools for the search field and back', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final queries = <String>[];
      await pump(tester, host(controller, queries));

      expect(find.text('tools'), findsOneWidget);
      expect(find.byType(GlassSearchField), findsNothing);

      await tester.tap(find.byType(GlassSearchButton));
      await tester.pumpAndSettle();

      expect(find.byType(GlassSearchField), findsOneWidget);
      expect(find.text('tools'), findsNothing);

      await tester.enterText(find.byType(TextField), 'login');
      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pumpAndSettle();

      // A field that is gone cannot say what it still filters by, so closing
      // it lets go of the words.
      expect(find.text('tools'), findsOneWidget);
      expect(controller.text, isEmpty);
      expect(queries, ['login', '']);
    });

    testWidgets('offers no search where the view has nothing to search', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pump(tester, host(controller, [], canSearch: false));

      expect(find.byType(GlassSearchButton), findsNothing);
      expect(find.text('tools'), findsOneWidget);
    });
  });

  group('the view switch', () {
    testWidgets('moves to another view; the one on screen is no button', (
      tester,
    ) async {
      final picked = <int>[];
      await pump(
        tester,
        BoardViewSwitch(
          items: const [
            SegmentItem(label: 'Board', icon: LucideIcons.squareKanban),
            SegmentItem(label: 'Timeline', icon: LucideIcons.waypoints),
          ],
          selected: 0,
          onChanged: picked.add,
        ),
      );

      final chips = tester
          .widgetList<GlassSwitchChip>(find.byType(GlassSwitchChip))
          .toList();
      expect(chips.first.onTap, isNull);

      await tester.tap(find.text('Timeline'));

      expect(picked, [1]);
    });
  });

  group('the group-by pill', () {
    testWidgets('is washed amber while the board is grouped', (tester) async {
      await pump(
        tester,
        BoardGroupByButton(value: BoardGrouping.epic, onChanged: (_) {}),
      );

      expect(pillIn(tester, find.byType(BoardGroupByButton)).active, isTrue);
    });

    testWidgets('is plain glass while it is not', (tester) async {
      await pump(
        tester,
        BoardGroupByButton(value: BoardGrouping.none, onChanged: (_) {}),
      );

      expect(pillIn(tester, find.byType(BoardGroupByButton)).active, isFalse);
    });
  });
}
