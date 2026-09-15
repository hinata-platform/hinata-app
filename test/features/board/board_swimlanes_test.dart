/// Grouped into lanes, a board draws every card it holds at once and scrolls
/// as one, so it reads on once the lanes come close to their end.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/board/board_swimlanes.dart';

void main() {
  const columns = [
    BoardColumnView(name: 'Open', states: ['Open'], issues: []),
    BoardColumnView(name: 'Done', states: ['Done'], issues: []),
  ];

  /// Lays out [lanes] lanes with columns 300 px tall on a board 400 px tall, and
  /// returns what the lanes asked for: each time, whether it may retry.
  Future<List<bool>> pump(WidgetTester tester, {required int lanes}) async {
    final asks = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 800,
              height: 400,
              child: BoardSwimlanes(
                columns: columns,
                lanes: [
                  for (var i = 0; i < lanes; i++)
                    BoardLane(
                      key: 'lane$i',
                      header: Text('lane $i'),
                      issues: const [],
                    ),
                ],
                columnBuilder: (column, issues, lane, width) =>
                    const SizedBox(height: 300),
                onNearEnd: ({required retry}) => asks.add(retry),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return asks;
  }

  /// The scroll that moves the lanes up and down.
  ScrollPosition lanesOf(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  testWidgets('lanes that do not fill the board read on once laid out', (
    tester,
  ) async {
    final asks = await pump(tester, lanes: 1);

    expect(asks, isNotEmpty);
    expect(asks, everyElement(isFalse));
  });

  testWidgets('lanes that fill the board read on only close to their end', (
    tester,
  ) async {
    final asks = await pump(tester, lanes: 10);
    expect(asks, isEmpty);

    final position = lanesOf(tester);
    position.jumpTo(1000);
    await tester.pump();
    expect(asks, isEmpty, reason: 'still far from the end');

    position.jumpTo(position.maxScrollExtent - 100);
    await tester.pump();

    expect(asks, isNotEmpty);
    expect(asks, everyElement(isFalse));
  });

  testWidgets(
    'someone scrolling close to the end may ask again for a page that did not come',
    (tester) async {
      final asks = await pump(tester, lanes: 10);
      final position = lanesOf(tester);
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      asks.clear();

      await tester.dragFrom(const Offset(400, 200), const Offset(0, 80));
      await tester.pump();

      expect(asks, contains(true));
    },
  );
}
