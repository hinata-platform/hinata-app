import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/time_grid/time_grid.dart';
import 'package:hinata/core/widgets/time_grid/time_grid_geometry.dart';
import 'package:hinata/core/widgets/time_grid/time_grid_model.dart';

/// The grid as a reader meets it: what is drawn, what a long press does, and
/// what it hands back.
///
/// The arithmetic has its own tests; this is about the widget honouring it —
/// that a block lands on its hours, that a drag on empty canvas reports the
/// span it swept, and that a layer which is not interactive stays put.
void main() {
  final monday = DateTime(2026, 9, 7);
  final week = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];

  TimeGridItem entry(
    String id,
    int fromHour,
    int toHour, {
    DateTime? day,
    bool movable = true,
  }) {
    final on = day ?? monday;
    return TimeGridItem(
      id: id,
      start: DateTime(on.year, on.month, on.day, fromHour),
      end: DateTime(on.year, on.month, on.day, toHour),
      title: id,
      movable: movable,
    );
  }

  Widget host({
    required List<TimeGridLayer> layers,
    List<DateTime>? days,
    void Function(TimeGridSpan)? onCreate,
    void Function(TimeGridItem, TimeGridSpan)? onMoved,
    void Function(TimeGridItem)? onTap,
    Size size = const Size(900, 700),
  }) => MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SizedBox(
          width: size.width,
          height: size.height,
          child: TimeGrid(
            days: days ?? [monday],
            layers: layers,
            // Fixed, so a test never depends on the day it runs on.
            now: DateTime(2026, 9, 7, 10, 30),
            metrics: const TimeGridMetrics(hourExtent: 60),
            onCreate: onCreate,
            onMoved: onMoved,
            onTap: onTap,
          ),
        ),
      ),
    ),
  );

  TimeGridLayer blocks(List<TimeGridItem> items) =>
      TimeGridLayer(id: 'entries', items: items);

  testWidgets('a block is drawn where its hours are', (tester) async {
    await tester.pumpWidget(host(layers: [blocks([entry('a', 9, 11)])]));
    await tester.pumpAndSettle();

    expect(find.text('a'), findsOneWidget);
    // Two hours at sixty pixels an hour. The grid opens scrolled to 8, so the
    // block's own height is what this can state without depending on scroll.
    final box = tester.getSize(
      find.ancestor(of: find.text('a'), matching: find.byType(Container)).first,
    );
    expect(box.height, 120);
  });

  testWidgets('a day and a week draw the columns they were given', (
    tester,
  ) async {
    await tester.pumpWidget(host(layers: [blocks([entry('a', 9, 11)])]));
    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);

    await tester.pumpWidget(
      host(layers: [blocks([entry('a', 9, 11)])], days: week),
    );
    await tester.pumpAndSettle();
    // Seven headings, one per day of the week.
    for (final day in week) {
      expect(find.text('${day.day}'), findsOneWidget);
    }
  });

  testWidgets('tapping a block hands the block back', (tester) async {
    TimeGridItem? tapped;
    await tester.pumpWidget(
      host(
        layers: [blocks([entry('a', 9, 11)])],
        onTap: (item) => tapped = item,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('a'));
    await tester.pumpAndSettle();

    expect(tapped?.id, 'a');
  });

  testWidgets('a long press and a drag on empty canvas sweeps out a span', (
    tester,
  ) async {
    TimeGridSpan? created;
    await tester.pumpWidget(
      host(layers: [blocks(const [])], onCreate: (span) => created = span),
    );
    await tester.pumpAndSettle();

    // Down on the canvas, hold, then drag an hour's worth downwards.
    final canvas = tester.getRect(find.byType(TimeGrid));
    final from = Offset(canvas.left + kTimeGridGutter + 40, canvas.top + 200);
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.end.difference(created!.start), const Duration(hours: 1));
  });

  testWidgets('a plain drag without the long press does not create anything', (
    tester,
  ) async {
    // Inside a scroll view a pan never wins the arena on touch, so the gesture
    // is deliberately long-press-first. A drag that skips it must scroll, not
    // silently write an entry.
    TimeGridSpan? created;
    await tester.pumpWidget(
      host(layers: [blocks(const [])], onCreate: (span) => created = span),
    );
    await tester.pumpAndSettle();

    final canvas = tester.getRect(find.byType(TimeGrid));
    await tester.dragFrom(
      Offset(canvas.left + kTimeGridGutter + 40, canvas.top + 200),
      const Offset(0, 60),
    );
    await tester.pumpAndSettle();

    expect(created, isNull);
  });

  testWidgets('a block that may not be moved is not moved', (tester) async {
    TimeGridItem? moved;
    await tester.pumpWidget(
      host(
        layers: [
          blocks([entry('fixed', 9, 11, movable: false)]),
        ],
        onMoved: (item, span) => moved = item,
      ),
    );
    await tester.pumpAndSettle();

    final at = tester.getCenter(find.text('fixed'));
    final gesture = await tester.startGesture(at);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(moved, isNull);
  });

  testWidgets('an all-day layer rides in the band, not on the hour canvas', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        layers: [
          TimeGridLayer(
            id: 'untimed',
            label: 'no clock',
            placement: TimeGridPlacement.band,
            items: [entry('retro', 0, 0)],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('no clock'), findsOneWidget);
    expect(find.text('retro'), findsOneWidget);
    // Above the hour canvas: the band sits in the header, which is not scrolled
    // vertically, so it is near the top of the widget whatever the scroll is.
    final grid = tester.getRect(find.byType(TimeGrid));
    expect(
      tester.getCenter(find.text('retro')).dy,
      lessThan(grid.top + kTimeGridHeader + kTimeGridBandRow + 4),
    );
  });

  testWidgets('an empty grid still draws its axis and headings', (
    tester,
  ) async {
    await tester.pumpWidget(host(layers: const []));
    await tester.pumpAndSettle();

    expect(find.byType(TimeGrid), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
  });
}
