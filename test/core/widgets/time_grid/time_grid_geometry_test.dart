import 'dart:math' show Random;
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/time_grid/time_grid_geometry.dart';
import 'package:hinata/core/widgets/time_grid/time_grid_model.dart';

/// The arithmetic the calendar is drawn from. A mistake here is two blocks on
/// top of each other or an entry an hour from where it happened — neither of
/// which a widget test notices, because both render perfectly well.
void main() {
  final day = DateTime(2026, 9, 7);

  TimeGridItem span(String id, int fromHour, int toHour, {int fromMin = 0}) =>
      TimeGridItem(
        id: id,
        start: DateTime(2026, 9, 7, fromHour, fromMin),
        end: DateTime(2026, 9, 7, toHour),
        title: id,
      );

  group('where a time lands', () {
    const metrics = TimeGridMetrics(hourExtent: 60);

    test('an hour is an hour tall, from the top of the day', () {
      expect(metrics.offsetOf(DateTime(2026, 9, 7, 0), day), 0);
      expect(metrics.offsetOf(DateTime(2026, 9, 7, 9), day), 540);
      expect(metrics.offsetOf(DateTime(2026, 9, 7, 9, 30), day), 570);
      expect(metrics.canvasHeight, 24 * 60);
    });

    test('a drawn window starts at its own first hour, not at midnight', () {
      const working = TimeGridMetrics(
        hourExtent: 60,
        firstHour: 8,
        lastHour: 20,
      );

      expect(working.offsetOf(DateTime(2026, 9, 7, 8), day), 0);
      expect(working.offsetOf(DateTime(2026, 9, 7, 12), day), 240);
      expect(working.canvasHeight, 12 * 60);
    });

    test(
      'a span outside the window is pinned to the edge, not drawn off it',
      () {
        const working = TimeGridMetrics(
          hourExtent: 60,
          firstHour: 8,
          lastHour: 20,
        );

        // A night shift would otherwise be positioned above the canvas, where
        // nothing can be read or grabbed.
        expect(working.offsetOf(DateTime(2026, 9, 7, 3), day), 0);
        expect(
          working.offsetOf(DateTime(2026, 9, 7, 23), day),
          working.canvasHeight,
        );
      },
    );

    test('a position reads back as the time it was drawn from', () {
      for (final at in [
        DateTime(2026, 9, 7, 0),
        DateTime(2026, 9, 7, 9, 30),
        DateTime(2026, 9, 7, 17, 15),
      ]) {
        expect(metrics.timeAt(metrics.offsetOf(at, day), day), at);
      }
    });

    test('a drag lands on the step, not between two of them', () {
      const step = Duration(minutes: 15);

      expect(
        metrics.timeAt(
          metrics.offsetOf(DateTime(2026, 9, 7, 9, 7), day),
          day,
          step: step,
        ),
        DateTime(2026, 9, 7, 9),
      );
      expect(
        metrics.timeAt(
          metrics.offsetOf(DateTime(2026, 9, 7, 9, 8), day),
          day,
          step: step,
        ),
        DateTime(2026, 9, 7, 9, 15),
      );
    });

    test('the bottom of the canvas is the end of the drawn window', () {
      // Not "23:59 of this day": the end of a full day is the next midnight,
      // and an entry that runs to it ends there. What matters is that dragging
      // past the bottom cannot reach into the day after — the offset is clamped
      // before it is ever read as a time.
      expect(
        metrics.timeAt(
          metrics.canvasHeight + 500,
          day,
          step: const Duration(minutes: 15),
        ),
        DateTime(2026, 9, 8),
      );

      const working = TimeGridMetrics(
        hourExtent: 60,
        firstHour: 8,
        lastHour: 20,
      );
      expect(
        working.timeAt(working.canvasHeight + 500, day),
        DateTime(2026, 9, 7, 20),
      );
    });
  });

  group('blocks that share hours share the width', () {
    test('one block alone has the column to itself', () {
      final slots = packOverlaps([span('a', 9, 10)], minExtent: Duration.zero);

      expect(slots.single.column, 0);
      expect(slots.single.columns, 1);
    });

    test('two that do not touch each other both take the full width', () {
      final slots = packOverlaps([
        span('a', 9, 10),
        span('b', 10, 11),
      ], minExtent: Duration.zero);

      expect(slots.map((s) => s.columns), everyElement(1));
    });

    test('two that overlap take half each', () {
      final slots = packOverlaps([
        span('a', 9, 11),
        span('b', 10, 12),
      ], minExtent: Duration.zero);

      expect(slots.map((s) => s.columns), everyElement(2));
      expect(slots.map((s) => s.column).toSet(), {0, 1});
    });

    test('a chain of overlaps is one cluster, even at its ends', () {
      // a overlaps b and b overlaps c, but a and c never touch. Laid out in
      // pairs, b would be drawn at two different widths at once.
      //
      // The width is two rather than three: c starts after a has ended, so it
      // takes the lane a left rather than opening its own. All three still
      // share one width, which is what makes them read as one cluster.
      final slots = packOverlaps([
        span('a', 9, 11),
        span('b', 10, 12),
        span('c', 11, 13, fromMin: 30),
      ], minExtent: Duration.zero);

      expect(slots.map((s) => s.columns), everyElement(2));
      final byId = {for (final s in slots) s.item.id: s.column};
      expect(byId['a'], 0);
      expect(byId['b'], 1);
      expect(byId['c'], 0);
    });

    test('three that genuinely overlap take a third each', () {
      final slots = packOverlaps([
        span('a', 9, 12),
        span('b', 10, 13),
        span('c', 11, 14),
      ], minExtent: Duration.zero);

      expect(slots.map((s) => s.columns), everyElement(3));
      expect(slots.map((s) => s.column).toSet(), {0, 1, 2});
    });

    test('a lane is reused once its block has ended', () {
      // a 9–12 keeps lane 0 all morning; b 9–10 and c 10–11 take turns in lane
      // 1 rather than opening a third.
      final slots = packOverlaps([
        span('a', 9, 12),
        span('b', 9, 10),
        span('c', 10, 11),
      ], minExtent: Duration.zero);

      expect(slots.map((s) => s.columns), everyElement(2));
      final byId = {for (final s in slots) s.item.id: s.column};
      expect(byId['a'], 0);
      expect(byId['b'], 1);
      expect(byId['c'], 1);
    });

    test('a cluster does not widen the blocks after it', () {
      final slots = packOverlaps([
        span('a', 9, 11),
        span('b', 9, 11),
        span('c', 14, 15),
      ], minExtent: Duration.zero);

      final byId = {for (final s in slots) s.item.id: s};
      expect(byId['a']!.columns, 2);
      expect(byId['c']!.columns, 1, reason: 'the afternoon is not crowded');
    });

    test('the longer block takes the leading lane', () {
      // Otherwise a one-minute entry starting at the same moment splits the
      // long one and takes the left half of the morning.
      final slots = packOverlaps([
        span('short', 9, 10),
        TimeGridItem(
          id: 'long',
          start: DateTime(2026, 9, 7, 9),
          end: DateTime(2026, 9, 7, 17),
          title: 'long',
        ),
      ], minExtent: Duration.zero);

      final byId = {for (final s in slots) s.item.id: s.column};
      expect(byId['long'], 0);
      expect(byId['short'], 1);
    });

    test('nothing in, nothing out', () {
      expect(packOverlaps(const [], minExtent: Duration.zero), isEmpty);
      expect(
        packOverlaps(const [], minExtent: const Duration(minutes: 22)),
        isEmpty,
      );
    });

    test('the layout does not depend on the order it was handed', () {
      final forwards = packOverlaps([
        span('a', 9, 11),
        span('b', 10, 12),
        span('c', 14, 15),
      ], minExtent: Duration.zero);
      final backwards = packOverlaps([
        span('c', 14, 15),
        span('b', 10, 12),
        span('a', 9, 11),
      ], minExtent: Duration.zero);

      String describe(List<TimeGridSlot> slots) =>
          (slots.map((s) => '${s.item.id}:${s.column}/${s.columns}').toList()
                ..sort())
              .join(',');
      expect(describe(forwards), describe(backwards));
    });
  });

  group('blocks are packed by what is painted, not by what was logged', () {
    // The calendar's own zoom. A block is never drawn thinner than one line of
    // text, so at 56 points an hour each of them covers 22 minutes of column
    // however long the entry actually was.
    const metrics = TimeGridMetrics();

    TimeGridItem minute(String id, int hour, int min, {int lasting = 1}) =>
        TimeGridItem(
          id: id,
          start: DateTime(2026, 9, 9, hour, min),
          end: DateTime(2026, 9, 9, hour, min + lasting),
          title: id,
        );

    /// What the grid paints for [items], in one column.
    List<Rect> painted(List<TimeGridItem> items, {TimeGridMetrics? at}) {
      final m = at ?? metrics;
      return [
        for (final slot in packOverlaps(items, minExtent: m.minBlockExtent))
          blockRectOf(
            slot,
            metrics: m,
            day: DateTime(2026, 9, 9),
            dayIndex: 0,
            columnWidth: 280,
          ),
      ];
    }

    /// The property the whole exercise is about: nothing is drawn through
    /// anything else. Reported with the pair, so a failure names the two.
    void expectNoneOverlap(List<Rect> rects) {
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(
            rects[i].overlaps(rects[j]),
            isFalse,
            reason: '${rects[i]} is drawn through ${rects[j]}',
          );
        }
      }
    }

    test('the floor is a whole number of minutes, rounded up', () {
      // 20 points of block over 56 points of hour is 21 min 26 s, and
      // `offsetOf` would round that back down to 21 — half a point of overlap.
      expect(metrics.minBlockExtent, const Duration(minutes: 22));
      expect(
        const TimeGridMetrics(hourExtent: 60).minBlockExtent,
        const Duration(minutes: 20),
      );
      // Zoomed in far enough, a short entry is drawn at its own length and the
      // floor stops costing anything.
      expect(
        const TimeGridMetrics(hourExtent: 600).minBlockExtent,
        const Duration(minutes: 2),
      );
    });

    test('a stopwatch morning is drawn side by side, not on top of itself', () {
      // The case as it was reported: five entries started and stopped one after
      // another within ten minutes. Not one of them overlaps another on the
      // clock; every one of them overlapped on screen.
      final entries = [
        minute('a', 15, 51, lasting: 6),
        minute('b', 15, 58),
        minute('c', 16, 0, lasting: 2),
        minute('d', 16, 3),
        minute('e', 16, 5),
      ];

      final slots = packOverlaps(entries, minExtent: metrics.minBlockExtent);
      expect(slots.map((s) => s.column).toSet(), {
        0,
        1,
        2,
        3,
        4,
      }, reason: 'a lane each, because each covers the next one\'s minutes');
      expect(slots.map((s) => s.columns), everyElement(5));
      expectNoneOverlap(painted(entries));
    });

    test('spans that only just clear the floor keep the full width', () {
      // 22 minutes apart at this zoom is exactly the floor: the second starts
      // where the first stops being drawn, so neither has to give up width.
      final entries = [minute('a', 9, 0), minute('b', 9, 22)];

      expect(painted(entries).map((r) => r.width).toSet(), hasLength(1));
      expect(
        packOverlaps(entries, minExtent: metrics.minBlockExtent),
        everyElement(
          isA<TimeGridSlot>().having((s) => s.columns, 'columns', 1),
        ),
      );
      expectNoneOverlap(painted(entries));
    });

    test('an ordinary day is laid out exactly as it was before', () {
      // The floor must not cost a calendar of meetings anything: back-to-back
      // hours still have the column to themselves.
      final day = [
        TimeGridItem(
          id: 'standup',
          start: DateTime(2026, 9, 9, 9),
          end: DateTime(2026, 9, 9, 10),
          title: 'standup',
        ),
        TimeGridItem(
          id: 'pairing',
          start: DateTime(2026, 9, 9, 10),
          end: DateTime(2026, 9, 9, 12),
          title: 'pairing',
        ),
      ];

      expect(
        packOverlaps(
          day,
          minExtent: metrics.minBlockExtent,
        ).map((s) => s.columns),
        everyElement(1),
      );
      expectNoneOverlap(painted(day));
    });

    test('nothing is drawn through anything else, whatever the day holds', () {
      // The property, over a day nobody would design by hand: 120 entries at
      // pseudo-random minutes and lengths, from a fixed seed so a failure can
      // be reproduced. Both zooms, because the floor is a function of it.
      final random = Random(20260909);
      final items = [
        for (var i = 0; i < 120; i++)
          () {
            final startMinute = random.nextInt(24 * 60);
            // Mostly the short entries a stopwatch leaves behind, with the
            // occasional meeting-length block among them.
            final length = random.nextInt(10) == 0
                ? 30 + random.nextInt(120)
                : 1 + random.nextInt(4);
            final start = DateTime(
              2026,
              9,
              9,
            ).add(Duration(minutes: startMinute));
            return TimeGridItem(
              id: 'i$i',
              start: start,
              // Clipped to the day, the way the grid hands its columns over.
              end:
                  start
                      .add(Duration(minutes: length))
                      .isAfter(DateTime(2026, 9, 10))
                  ? DateTime(2026, 9, 10)
                  : start.add(Duration(minutes: length)),
              title: 'i$i',
            );
          }(),
      ];

      for (final zoom in [
        const TimeGridMetrics(),
        const TimeGridMetrics(hourExtent: 28),
        const TimeGridMetrics(hourExtent: 120),
      ]) {
        expectNoneOverlap(painted(items, at: zoom));
      }
    });

    test('every entry keeps a place of its own', () {
      // Side by side is only an answer if all of them are still there: the
      // packing may narrow a block, never drop one.
      final entries = [for (var i = 0; i < 8; i++) minute('e$i', 11, i)];

      expect(
        packOverlaps(
          entries,
          minExtent: metrics.minBlockExtent,
        ).map((s) => s.item.id).toSet(),
        {for (var i = 0; i < 8; i++) 'e$i'},
      );
    });
  });
}
