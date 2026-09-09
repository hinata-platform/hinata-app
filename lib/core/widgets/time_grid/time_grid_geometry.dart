/// The arithmetic behind the grid: where a time sits, what a position means,
/// and how blocks that share hours share the width.
///
/// Separate from the widget because it is the part worth testing on its own —
/// a packing bug shows up as two blocks drawn on top of each other, which no
/// widget test asserts by accident.
library;

import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'time_grid_model.dart';

/// The vertical padding a block draws its lines inside, and the line box of
/// the title and of the line under it.
///
/// Written down rather than left to the font, and set as an explicit `height`
/// on both styles, because the block's *minimum* height is derived from these
/// numbers. A line that turned out taller than the box reserved for it is a
/// bottom overflow on every short entry.
const double kTimeGridBlockPadV = 3;
const double kTimeGridBlockTitleLine = 14;
const double kTimeGridBlockSubLine = 12;

/// How short a block may be drawn: one title line and its padding.
///
/// A one-minute entry is still worth grabbing, so a block never draws thinner
/// than a finger can find — and never thinner than the one line it always
/// shows. At an hour extent of 60 a quarter-hour entry is fifteen points tall
/// and was given eighteen; its two lines of text needed thirty-two.
///
/// This floor is why packing cannot go by spans alone — see
/// [TimeGridMetrics.minBlockExtent].
const double kTimeGridBlockMinHeight =
    2 * kTimeGridBlockPadV + kTimeGridBlockTitleLine;

/// The air between a block and the edge of the column it sits in.
///
/// Named because two things draw into a column — a packed block and the
/// preview a drag paints — and a preview inset differently from the block it
/// becomes is a jump at the moment the finger lifts.
const double kTimeGridColumnGutter = 3;

/// How tall an hour is and which hours are drawn.
class TimeGridMetrics {
  const TimeGridMetrics({
    this.hourExtent = 56,
    this.firstHour = 0,
    this.lastHour = 24,
  }) : assert(firstHour >= 0 && lastHour <= 24 && firstHour < lastHour);

  /// Pixels per hour. The zoom: 56 reads comfortably, 28 fits a working day.
  final double hourExtent;

  /// The window of the day that is drawn, in whole hours.
  final int firstHour;
  final int lastHour;

  int get hourCount => lastHour - firstHour;
  double get canvasHeight => hourCount * hourExtent;

  /// How much of the day a block occupies on screen, however little of it the
  /// entry actually lasted.
  ///
  /// A block is never painted thinner than [kTimeGridBlockMinHeight], so at
  /// this zoom every one of them covers at least this much time whatever the
  /// record says — twenty-two minutes at the calendar's default extent.
  ///
  /// Packing has to be told, because the two halves of "does this collide"
  /// were being answered on different scales: [packOverlaps] compared spans
  /// and the painter compared pixels. Five one-minute entries logged two
  /// minutes apart share no minute at all and were drawn straight through each
  /// other — which is exactly what a stopwatch produces, one start and stop at
  /// a time.
  ///
  /// Whole minutes, rounded **up**, and that is what makes the result provable
  /// rather than merely better: [offsetOf] measures in whole minutes and drops
  /// the seconds, so a floor of 21 min 26 s would let a block start 0.4 points
  /// above where the one before it stops. Rounded up to the next minute, a lane
  /// that the packer calls free is a lane the painter leaves empty.
  Duration get minBlockExtent =>
      Duration(minutes: (kTimeGridBlockMinHeight / hourExtent * 60).ceil());

  /// Where [at] falls on the canvas, measured from the top of [day]'s column.
  ///
  /// Clamped to the canvas: an entry that starts before the drawn window is
  /// pinned to its top edge rather than positioned off it, so a block always
  /// begins somewhere a reader can see and grab.
  double offsetOf(DateTime at, DateTime day) {
    final minutes = at.difference(_dayStart(day)).inMinutes - firstHour * 60;
    return (minutes / 60 * hourExtent).clamp(0.0, canvasHeight);
  }

  /// What the canvas position [offset] means on [day], rounded to the nearest
  /// [step].
  DateTime timeAt(double offset, DateTime day, {Duration? step}) {
    final minutes =
        (offset.clamp(0.0, canvasHeight) / hourExtent * 60).round() +
        firstHour * 60;
    final at = _dayStart(day).add(Duration(minutes: minutes));
    return step == null ? at : snap(at, step);
  }

  /// [at] rounded to the nearest [step] — what a drag lands on.
  static DateTime snap(DateTime at, Duration step) {
    final unit = math.max(1, step.inMinutes);
    final minutes = at.hour * 60 + at.minute;
    final snapped = (minutes / unit).round() * unit;
    return DateTime(at.year, at.month, at.day).add(Duration(minutes: snapped));
  }

  static DateTime _dayStart(DateTime day) =>
      DateTime(day.year, day.month, day.day);
}

/// One block's place among the blocks it shares hours with.
class TimeGridSlot {
  const TimeGridSlot({
    required this.item,
    required this.column,
    required this.columns,
  });

  final TimeGridItem item;

  /// Which of [columns] side-by-side lanes this block occupies.
  final int column;

  /// How many lanes the cluster it belongs to was split into.
  final int columns;
}

/// Lays overlapping blocks out side by side.
///
/// Two passes. First the items are cut into clusters — runs that overlap
/// transitively, so A/B and B/C put all three in one cluster even when A and C
/// do not touch. Then each item in a cluster takes the first lane whose last
/// block has already ended, and the cluster's width is however many lanes that
/// needed.
///
/// The alternative — one lane per item — narrows a day with three overlapping
/// entries to a third of the column for every block on it, including the ones
/// that overlap nothing.
///
/// "Overlap" means *on screen*, not on the clock: [minExtent] is the time a
/// block takes up however short it was (see [TimeGridMetrics.minBlockExtent]),
/// and two blocks that would be painted through each other are laid out side
/// by side even where their spans never touch.
///
/// Required, with no default. `Duration.zero` is the packing this call was
/// written to replace — correct only for a surface that draws a block at its
/// true length, which nothing does — and a default is how a later caller gets
/// the old behaviour back without meaning to.
List<TimeGridSlot> packOverlaps(
  Iterable<TimeGridItem> items, {
  required Duration minExtent,
}) {
  /// Where [item] stops covering the column — its end, or the floor if it was
  /// shorter than one.
  DateTime paintedEnd(TimeGridItem item) {
    final floor = item.start.add(minExtent);
    return item.end.isAfter(floor) ? item.end : floor;
  }

  final sorted = items.toList()
    ..sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      if (byStart != 0) return byStart;
      // The longer block first, so it takes the leftmost lane and the short
      // ones stack to its right instead of splitting it.
      final byEnd = b.end.compareTo(a.end);
      return byEnd != 0 ? byEnd : a.id.compareTo(b.id);
    });

  final slots = <TimeGridSlot>[];
  // The lane each item takes is decided on the way through; the width it is
  // drawn at is only known once the cluster has ended. So a cluster is
  // collected with its lanes and written out together.
  var cluster = <({TimeGridItem item, int lane})>[];
  var lanes = <DateTime>[];
  DateTime? clusterEnd;

  void flush() {
    if (cluster.isEmpty) return;
    for (final placed in cluster) {
      slots.add(
        TimeGridSlot(
          item: placed.item,
          column: placed.lane,
          columns: lanes.length,
        ),
      );
    }
    cluster = [];
    lanes = [];
    clusterEnd = null;
  }

  for (final item in sorted) {
    final covered = paintedEnd(item);
    final end = clusterEnd;
    if (end != null && !item.start.isBefore(end)) {
      flush();
    }
    var lane = lanes.indexWhere((busyUntil) => !busyUntil.isAfter(item.start));
    if (lane < 0) {
      lanes.add(covered);
      lane = lanes.length - 1;
    } else {
      lanes[lane] = covered;
    }
    cluster.add((item: item, lane: lane));
    clusterEnd = clusterEnd == null || covered.isAfter(clusterEnd!)
        ? covered
        : clusterEnd;
  }
  flush();
  return slots;
}

/// Where a packed block is painted, in the canvas's own coordinates.
///
/// The one place the rectangle is worked out, because it is the other half of
/// [packOverlaps]: the floor applied here is the floor that has to be packed
/// against, and two copies of that number drift apart into blocks drawn
/// through each other.
///
/// [dayIndex] is the column [slot] belongs to and [day] the date it draws —
/// the caller has both, and asking it saves resolving one from the other.
Rect blockRectOf(
  TimeGridSlot slot, {
  required TimeGridMetrics metrics,
  required DateTime day,
  required int dayIndex,
  required double columnWidth,
}) {
  final top = metrics.offsetOf(slot.item.start, day);
  final bottom = metrics.offsetOf(slot.item.end, day);
  // The gutter at the column's edges, and two points between lanes so
  // neighbouring blocks read as two rather than as one split by a hairline.
  final laneWidth = (columnWidth - 2 * kTimeGridColumnGutter) / slot.columns;
  final left =
      dayIndex * columnWidth + kTimeGridColumnGutter + slot.column * laneWidth;
  return Rect.fromLTRB(
    left,
    top,
    left + laneWidth - 2,
    math.max(bottom, top + kTimeGridBlockMinHeight),
  );
}
