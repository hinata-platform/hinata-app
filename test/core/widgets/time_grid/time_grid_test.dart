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

  testWidgets('a span across midnight is drawn in both days', (tester) async {
    // Placed only in its start's column, a night shift was drawn from 22:00 to
    // the bottom of the canvas and the rest appeared nowhere. HIN-44 is shift
    // planning, where this is the ordinary case rather than the edge.
    await tester.pumpWidget(
      host(
        days: week,
        layers: [
          blocks([
            TimeGridItem(
              id: 'night',
              start: DateTime(2026, 9, 7, 22),
              end: DateTime(2026, 9, 8, 6),
              title: 'night shift',
            ),
          ]),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // One block per day it touches, and both are the same entry.
    expect(find.text('night shift'), findsNWidgets(2));
  });

  testWidgets('a block that ends exactly at midnight stays in its own day', (
    tester,
  ) async {
    // The boundary either way: 22:00–24:00 belongs to the 7th alone, and must
    // not open an empty sliver on the 8th.
    await tester.pumpWidget(
      host(
        days: week,
        layers: [
          blocks([
            TimeGridItem(
              id: 'late',
              start: DateTime(2026, 9, 7, 22),
              end: DateTime(2026, 9, 8),
              title: 'late shift',
            ),
          ]),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('late shift'), findsOneWidget);
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

  testWidgets('a sweep that changes its mind keeps the point it started from', (
    tester,
  ) async {
    // The anchor used to be read back off the span the sweep was writing, so it
    // followed the highest point the finger reached: sweep up, come back down,
    // and the span stayed pinned to the top instead of shrinking.
    TimeGridSpan? created;
    await tester.pumpWidget(
      host(layers: [blocks(const [])], onCreate: (span) => created = span),
    );
    await tester.pumpAndSettle();

    final canvas = tester.getRect(find.byType(TimeGrid));
    final from = Offset(canvas.left + kTimeGridGutter + 40, canvas.top + 300);
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, -120)); // two hours up
    await tester.pump();
    await gesture.moveBy(const Offset(0, 60)); // one hour back down
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.end.difference(created!.start), const Duration(hours: 1));
  });

  testWidgets('a sweep that wanders sideways stays in its own day', (
    tester,
  ) async {
    // Anchored on one day and read on another, the two ends straddle midnight:
    // the grid draws a block it cannot place and the editor is handed a span
    // nobody swept.
    TimeGridSpan? created;
    await tester.pumpWidget(
      host(
        layers: [blocks(const [])],
        days: week,
        onCreate: (span) => created = span,
      ),
    );
    await tester.pumpAndSettle();

    final canvas = tester.getRect(find.byType(TimeGrid));
    final gesture = await tester.startGesture(
      Offset(canvas.left + kTimeGridGutter + 40, canvas.top + 300),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(220, 60)); // two columns over, an hour down
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.start.day, created!.end.day);
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

  testWidgets('several all-day items on one day are rows, not a pile', (
    tester,
  ) async {
    // One row per *layer* drew them all in the same place: the strip looked
    // like a single entry with the rest invisible underneath it, which is
    // exactly what four demo entries on one day produced.
    await tester.pumpWidget(
      host(
        layers: [
          TimeGridLayer(
            id: 'untimed',
            label: 'no clock',
            placement: TimeGridPlacement.band,
            items: [
              entry('first', 0, 0),
              entry('second', 0, 0),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    expect(
      tester.getCenter(find.text('second')).dy -
          tester.getCenter(find.text('first')).dy,
      kTimeGridBandRow,
      reason: 'one row apart, not on top of each other',
    );
  });

  testWidgets('past the ceiling the strip counts what it cannot show', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        layers: [
          TimeGridLayer(
            id: 'untimed',
            placement: TimeGridPlacement.band,
            items: [
              for (var i = 0; i < 6; i++) entry('item$i', 0, 0),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Two chips and a count of the other four: the number on screen is never a
    // lie about how much is there.
    expect(find.text('item0'), findsOneWidget);
    expect(find.text('item1'), findsOneWidget);
    expect(find.text('+4'), findsOneWidget);
    expect(find.text('item2'), findsNothing);
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
