import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kDoubleTapMinTime, kDoubleTapTimeout;
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
    // The grid opens on the working day; a test about hours outside it has to
    // say so or the block it means is scrolled out of reach.
    int initialScrollHour = 8,
    bool showHeadings = true,
    double minColumnWidth = kTimeGridMinColumn,
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
            initialScrollHour: initialScrollHour,
            showHeadings: showHeadings,
            minColumnWidth: minColumnWidth,
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
    await tester.pumpWidget(
      host(
        layers: [
          blocks([entry('a', 9, 11)]),
        ],
      ),
    );
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
    await tester.pumpWidget(
      host(
        layers: [
          blocks([entry('a', 9, 11)]),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);

    await tester.pumpWidget(
      host(
        layers: [
          blocks([entry('a', 9, 11)]),
        ],
        days: week,
      ),
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

  testWidgets('dragging half of a night shift moves the whole entry', (
    tester,
  ) async {
    // The clipping is geometry. A drag computes from the item's own span, so
    // handing it the half that was grabbed made an eight-hour entry save as six
    // — silently, in a working-time record. A stopped overnight timer produces
    // exactly this entry; it is not only HIN-44's problem.
    TimeGridItem? moved;
    TimeGridSpan? span;
    final night = TimeGridItem(
      id: 'night',
      start: DateTime(2026, 9, 7, 22),
      end: DateTime(2026, 9, 8, 6),
      title: 'night shift',
      movable: true,
    );
    await tester.pumpWidget(
      host(
        days: week,
        layers: [
          blocks([night]),
        ],
        initialScrollHour: 0,
        onMoved: (item, dropped) {
          moved = item;
          span = dropped;
        },
      ),
    );
    await tester.pumpAndSettle();

    // The Tuesday half — 00:00–06:00, the one whose clipped duration is wrong.
    final halves = tester.widgetList<Text>(find.text('night shift')).length;
    expect(halves, 2);
    final tuesday = tester.getCenter(find.text('night shift').last);
    final gesture = await tester.startGesture(tuesday);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(moved?.id, 'night');
    // The entry the caller gets back carries its own span, not the column's.
    expect(moved!.end.difference(moved!.start), const Duration(hours: 8));
    expect(span!.end.difference(span!.start), const Duration(hours: 8));
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
        layers: [
          blocks([entry('a', 9, 11)]),
        ],
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
    await gesture.moveBy(
      const Offset(220, 60),
    ); // two columns over, an hour down
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.start.day, created!.end.day);
    expect(created!.end.difference(created!.start), const Duration(hours: 1));
  });

  testWidgets('a finger that drags without holding first scrolls, not creates', (
    tester,
  ) async {
    // Inside a scroll view a pan never wins the arena on touch — its slop is
    // twice the scrollable's — so the touch gesture is deliberately
    // long-press-first. A drag that skips it must scroll, not silently write an
    // entry. The mouse is the opposite case and is the test below.
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

  testWidgets('a mouse sweeps out a span without holding first', (
    tester,
  ) async {
    // The web with a mouse had no create gesture at all: pressing and holding
    // half a second before dragging is something nobody does with a mouse, and
    // a tap only says where. A precise pointer has a one-pixel slop, so a plain
    // pan wins the arena here that a finger's never could.
    TimeGridSpan? created;
    await tester.pumpWidget(
      host(layers: [blocks(const [])], onCreate: (span) => created = span),
    );
    await tester.pumpAndSettle();

    final canvas = tester.getRect(find.byType(TimeGrid));
    final gesture = await tester.startGesture(
      Offset(canvas.left + kTimeGridGutter + 40, canvas.top + 200),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.end.difference(created!.start), const Duration(hours: 1));
  });

  testWidgets('a mouse drag on a block moves it, and does not create', (
    tester,
  ) async {
    TimeGridItem? moved;
    TimeGridSpan? created;
    await tester.pumpWidget(
      host(
        layers: [
          blocks([entry('a', 9, 10)]),
        ],
        onMoved: (item, span) => moved = item,
        onCreate: (span) => created = span,
      ),
    );
    await tester.pumpAndSettle();

    final block = tester.getCenter(find.text('a'));
    final gesture = await tester.startGesture(
      block,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(moved?.id, 'a');
    expect(created, isNull);
  });

  testWidgets('a double tap on empty canvas asks for an hour at that time', (
    tester,
  ) async {
    // An hour, not the step: fifteen minutes is the grain a sweep rounds to and
    // a useless length to open an editor on.
    TimeGridSpan? created;
    await tester.pumpWidget(
      host(layers: [blocks(const [])], onCreate: (span) => created = span),
    );
    await tester.pumpAndSettle();

    final canvas = tester.getRect(find.byType(TimeGrid));
    final at = Offset(canvas.left + kTimeGridGutter + 40, canvas.top + 120);
    await tester.tapAt(at);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(at);
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.end.difference(created!.start), const Duration(hours: 1));
  });

  testWidgets('one tap on empty canvas creates nothing', (tester) async {
    // The easiest gesture on the grid to make by accident. An editor that opens
    // by itself reads as a bug, not as an offer.
    TimeGridSpan? created;
    await tester.pumpWidget(
      host(layers: [blocks(const [])], onCreate: (span) => created = span),
    );
    await tester.pumpAndSettle();

    final canvas = tester.getRect(find.byType(TimeGrid));
    await tester.tapAt(
      Offset(canvas.left + kTimeGridGutter + 40, canvas.top + 120),
    );
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();

    expect(created, isNull);
  });

  testWidgets('a tap on a block opens it without waiting on a second', (
    tester,
  ) async {
    // Two recognizers in one arena would make every tap sit out the
    // double-tap window first. One serial recognizer reports each tap as it
    // happens, so this fires on the frame after the finger lifts.
    TimeGridItem? tapped;
    await tester.pumpWidget(
      host(
        layers: [
          blocks([entry('a', 9, 11)]),
        ],
        onTap: (item) => tapped = item,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('a'));
    await tester.pump();
    // One frame after the finger lifts, not one double-tap window later.
    expect(tapped?.id, 'a');

    // The serial recognizer is still listening for a second tap; let it give up
    // so the test does not end on a pending timer.
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('a press that never moves asks for an hour where it was', (
    tester,
  ) async {
    TimeGridSpan? created;
    await tester.pumpWidget(
      host(layers: [blocks(const [])], onCreate: (span) => created = span),
    );
    await tester.pumpAndSettle();

    final canvas = tester.getRect(find.byType(TimeGrid));
    final gesture = await tester.startGesture(
      Offset(canvas.left + kTimeGridGutter + 40, canvas.top + 200),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.end.difference(created!.start), const Duration(hours: 1));
  });

  testWidgets('a short entry draws without overflowing its block', (
    tester,
  ) async {
    // A quarter-hour entry is fifteen points tall at this hour extent and is
    // floored to twenty; two lines of text are thirty-two. The difference used
    // to be painted across the entry as a striped overflow bar.
    await tester.pumpWidget(
      host(
        layers: [
          TimeGridLayer(
            id: 'entries',
            items: [
              TimeGridItem(
                id: 'short',
                start: DateTime(2026, 9, 7, 18, 45),
                end: DateTime(2026, 9, 7, 19),
                title: 'Standup',
                subtitle: 'Development',
              ),
            ],
          ),
        ],
        initialScrollHour: 18,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Standup'), findsOneWidget);
    // The second line is dropped rather than squeezed: there is room for one
    // whole line and no more, and half a line of type is not information.
    expect(find.text('Development'), findsNothing);
  });

  testWidgets('an entry with room for both lines shows both', (tester) async {
    await tester.pumpWidget(
      host(
        layers: [
          TimeGridLayer(
            id: 'entries',
            items: [
              TimeGridItem(
                id: 'long',
                start: DateTime(2026, 9, 7, 9),
                end: DateTime(2026, 9, 7, 11),
                title: 'Pairing',
                subtitle: 'Development',
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Pairing'), findsOneWidget);
    expect(find.text('Development'), findsOneWidget);
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
            items: [entry('first', 0, 0), entry('second', 0, 0)],
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
            items: [for (var i = 0; i < 6; i++) entry('item$i', 0, 0)],
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

  testWidgets('the count opens what it stands for', (tester) async {
    // The count used to be a label and nothing else: the strip said a day held
    // four more entries and offered no way at all to reach them, at every
    // window size, because the ceiling is on rows rather than on width.
    TimeGridItem? opened;
    await tester.pumpWidget(
      host(
        layers: [
          TimeGridLayer(
            id: 'untimed',
            placement: TimeGridPlacement.band,
            items: [for (var i = 0; i < 6; i++) entry('item$i', 0, 0)],
          ),
        ],
        onTap: (item) => opened = item,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('+4'));
    await tester.pumpAndSettle();

    // The whole day, not the tail: a reader who taps "+4" wants the day, not a
    // remainder to reconcile against the chips above.
    expect(find.text('item5'), findsOneWidget, reason: 'in the popover');
    expect(
      find.text('item0'),
      findsNWidgets(2),
      reason: 'chip and popover row',
    );

    await tester.tap(find.text('item5'));
    await tester.pumpAndSettle();

    expect(opened?.id, 'item5', reason: 'the same callback a chip reports on');
    expect(find.text('item5'), findsNothing, reason: 'the popover closed');
  });

  testWidgets('a layer nobody can open counts without offering a menu', (
    tester,
  ) async {
    // The chips of a read-only layer are inert, and the count beside them has
    // to be too: a popover whose every row silently does nothing is worse than
    // no popover.
    await tester.pumpWidget(
      host(
        layers: [
          TimeGridLayer(
            id: 'untimed',
            placement: TimeGridPlacement.band,
            items: [for (var i = 0; i < 6; i++) entry('item$i', 0, 0)],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('+4'));
    await tester.pumpAndSettle();

    expect(find.text('item5'), findsNothing);
  });

  testWidgets('short entries in a row are not drawn through each other', (
    tester,
  ) async {
    // The reported case, measured on the pixels rather than on the arithmetic:
    // five entries started and stopped one after another inside a quarter of an
    // hour. None of them overlaps another on the clock, and every one of them
    // overlapped on screen — a block is never painted thinner than one line of
    // text, so at this zoom each covers twenty minutes of column.
    TimeGridItem short(String id, int hour, int minute, {int lasting = 1}) =>
        TimeGridItem(
          id: id,
          start: DateTime(2026, 9, 7, hour, minute),
          end: DateTime(2026, 9, 7, hour, minute + lasting),
          title: id,
          movable: true,
        );

    final entries = [
      short('a', 15, 51, lasting: 6),
      short('b', 15, 58),
      short('c', 16, 0, lasting: 2),
      short('d', 16, 3),
      short('e', 16, 5),
    ];

    await tester.pumpWidget(
      host(layers: [blocks(entries)], initialScrollHour: 15),
    );
    await tester.pumpAndSettle();

    final drawn = {
      for (final item in entries)
        item.id: tester.getRect(
          find
              .ancestor(
                of: find.text(item.id),
                matching: find.byType(Container),
              )
              .first,
        ),
    };

    for (final a in entries) {
      for (final b in entries) {
        if (a.id.compareTo(b.id) >= 0) continue;
        expect(
          drawn[a.id]!.overlaps(drawn[b.id]!),
          isFalse,
          reason:
              '${a.id} at ${drawn[a.id]} is drawn through '
              '${b.id} at ${drawn[b.id]}',
        );
      }
    }
    // And each of them is still worth grabbing.
    expect(
      drawn.values.map((rect) => rect.height),
      everyElement(greaterThanOrEqualTo(kTimeGridBlockMinHeight)),
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

  TimeGridItem untimed(String id, DateTime day) => TimeGridItem(
    id: id,
    start: DateTime(day.year, day.month, day.day),
    end: DateTime(day.year, day.month, day.day),
    title: id,
    minutes: 60,
  );

  TimeGridLayer band(List<TimeGridItem> items) => TimeGridLayer(
    id: 'untimed',
    label: 'all day',
    placement: TimeGridPlacement.band,
    items: items,
  );

  group('the band is sized by the days on screen', () {
    testWidgets('a day with an untimed entry gets the strip', (tester) async {
      await tester.pumpWidget(
        host(
          layers: [
            band([untimed('note', monday)]),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('all day'), findsOneWidget);
      expect(find.text('note'), findsOneWidget);
    });

    testWidgets('a day with none does not, even when another day has one', (
      tester,
    ) async {
      // The phone's calendar holds a fortnight and draws one day of it, so a
      // layer that is not empty says nothing about the day on screen. A strip
      // labelled "all day" with nothing in it is a claim about that day which
      // is not true — and it costs a row of the hour canvas to make.
      await tester.pumpWidget(
        host(
          days: [monday],
          layers: [
            band([untimed('note', monday.add(const Duration(days: 3)))]),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('all day'), findsNothing);
      expect(find.text('note'), findsNothing);
    });
  });

  testWidgets('a day can be drawn without the grid writing its date', (
    tester,
  ) async {
    // The phone draws one day under a week strip that already names it, and
    // writes it out in full underneath — a heading over the single column would
    // be the third time in four centimetres.
    await tester.pumpWidget(
      host(
        layers: [
          blocks([entry('a', 9, 11)]),
        ],
        showHeadings: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('7'), findsNothing);
    expect(find.text('a'), findsOneWidget, reason: 'the hours are still drawn');
  });

  testWidgets('a canvas that fits leaves the horizontal drag to its parent', (
    tester,
  ) async {
    // A single day inside a pager is exactly this case, and a scroller with
    // nowhere to go still wins the gesture arena against its parent — which
    // would eat the swipe to the next day.
    await tester.pumpWidget(
      host(
        layers: [
          blocks([entry('a', 9, 11)]),
        ],
        minColumnWidth: 0,
      ),
    );
    await tester.pumpAndSettle();

    final scrollers = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .where((view) => view.scrollDirection == Axis.horizontal);
    expect(scrollers, isNotEmpty);
    expect(
      scrollers.map((view) => view.physics),
      everyElement(isA<NeverScrollableScrollPhysics>()),
    );
  });

  testWidgets('a canvas wider than the page keeps its own horizontal scroll', (
    tester,
  ) async {
    // The other half of the rule: seven columns at the minimum width do not fit
    // a phone, and there the grid has to scroll sideways itself.
    await tester.pumpWidget(
      host(
        layers: [
          blocks([entry('a', 9, 11)]),
        ],
        days: week,
        size: const Size(402, 700),
      ),
    );
    await tester.pumpAndSettle();

    final body = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .where((view) => view.scrollDirection == Axis.horizontal)
        .last;
    expect(body.physics, isNot(isA<NeverScrollableScrollPhysics>()));
  });
}
