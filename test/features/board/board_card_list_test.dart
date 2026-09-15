/// A column's cards read on as they are scrolled, and a page that did not come
/// is asked for again once someone scrolls them.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/board/board_card_list.dart';

/// A column the way the wall drives one: asked for more, it reads, and a
/// moment later holds ten more cards, or marks the page as failed.
class _Column extends StatefulWidget {
  const _Column({
    required this.initialCount,
    required this.total,
    this.laneMode = false,
    this.failing = false,
  });

  final int initialCount;
  final int total;
  final bool laneMode;
  final bool failing;

  @override
  State<_Column> createState() => _ColumnState();
}

class _ColumnState extends State<_Column> {
  late int count = widget.initialCount;
  late bool failing = widget.failing;
  bool loading = false;
  bool failed = false;
  int asks = 0;

  void _loadMore() {
    asks++;
    setState(() {
      loading = true;
      failed = false;
    });
    Future<void>.delayed(const Duration(milliseconds: 10), () {
      if (!mounted) return;
      setState(() {
        loading = false;
        if (failing) {
          failed = true;
        } else {
          count = math.min(count + 10, widget.total);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) => BoardCardList(
    count: count,
    laneMode: widget.laneMode,
    loadingMore: loading,
    onLoadMore: count < widget.total ? _loadMore : null,
    itemBuilder: (context, index) =>
        SizedBox(height: 100, child: Text('card $index')),
  );
}

void main() {
  /// Lays [column] out 400 px tall, the way a column's list takes the room its
  /// column leaves it.
  Future<_ColumnState> pump(WidgetTester tester, _Column column) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 400,
              child: Column(children: [Flexible(child: column)]),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.state<_ColumnState>(find.byType(_Column));
  }

  Future<void> answer(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
  }

  ScrollPosition positionOf(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position;

  testWidgets(
    'a column its cards do not fill asks for more once, as soon as it is laid out',
    (tester) async {
      final column = await pump(
        tester,
        const _Column(initialCount: 2, total: 4),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await answer(tester);

      expect(column.asks, 1);
      expect(column.count, 4);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(BoardReadOn), findsNothing);
    },
  );

  testWidgets(
    'a column its cards fill asks for more only near their end, once',
    (tester) async {
      final column = await pump(
        tester,
        const _Column(initialCount: 30, total: 100),
      );
      expect(column.asks, 0);

      final position = positionOf(tester);
      position.jumpTo(1500);
      await tester.pump();
      expect(column.asks, 0, reason: 'still far from the end');
      // Two steps of one gesture, before the column could rebuild.
      position
        ..jumpTo(2400)
        ..jumpTo(2500);
      await tester.pump();

      expect(column.asks, 1);
      await answer(tester);
    },
  );

  testWidgets(
    'a page that did not come is not asked for on its own, only once the column is scrolled again',
    (tester) async {
      final column = await pump(
        tester,
        const _Column(initialCount: 30, total: 50, failing: true),
      );
      // Close to the end of the cards, though not past what the list holds.
      positionOf(tester).jumpTo(2600);
      await tester.pump();
      expect(column.asks, 1);

      await answer(tester);
      expect(column.failed, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      expect(column.asks, 1, reason: 'nobody scrolled');

      column.failing = false;
      await tester.drag(find.byType(ListView), const Offset(0, 60));
      await tester.pump();
      expect(column.asks, 2);

      await answer(tester);
      expect(column.failed, isFalse);
      expect(column.count, 40);
    },
  );

  testWidgets('in a lane the list reads nothing on its own', (tester) async {
    final column = await pump(
      tester,
      const _Column(initialCount: 2, total: 50, laneMode: true),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(column.asks, 0);
    expect(find.byType(BoardReadOn), findsNothing);
  });
}
