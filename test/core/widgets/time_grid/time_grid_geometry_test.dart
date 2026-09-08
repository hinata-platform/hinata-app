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
      final slots = packOverlaps([span('a', 9, 10)]);

      expect(slots.single.column, 0);
      expect(slots.single.columns, 1);
    });

    test('two that do not touch each other both take the full width', () {
      final slots = packOverlaps([span('a', 9, 10), span('b', 10, 11)]);

      expect(slots.map((s) => s.columns), everyElement(1));
    });

    test('two that overlap take half each', () {
      final slots = packOverlaps([span('a', 9, 11), span('b', 10, 12)]);

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
      ]);

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
      ]);

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
      ]);

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
      ]);

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
      ]);

      final byId = {for (final s in slots) s.item.id: s.column};
      expect(byId['long'], 0);
      expect(byId['short'], 1);
    });

    test('nothing in, nothing out', () {
      expect(packOverlaps(const []), isEmpty);
    });

    test('the layout does not depend on the order it was handed', () {
      final forwards = packOverlaps([
        span('a', 9, 11),
        span('b', 10, 12),
        span('c', 14, 15),
      ]);
      final backwards = packOverlaps([
        span('c', 14, 15),
        span('b', 10, 12),
        span('a', 9, 11),
      ]);

      String describe(List<TimeGridSlot> slots) =>
          (slots.map((s) => '${s.item.id}:${s.column}/${s.columns}').toList()
                ..sort())
              .join(',');
      expect(describe(forwards), describe(backwards));
    });
  });
}
