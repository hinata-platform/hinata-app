/// The arithmetic behind the grid: where a time sits, what a position means,
/// and how blocks that share hours share the width.
///
/// Separate from the widget because it is the part worth testing on its own —
/// a packing bug shows up as two blocks drawn on top of each other, which no
/// widget test asserts by accident.
library;

import 'dart:math' as math;

import 'time_grid_model.dart';

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

  /// Where [at] falls on the canvas, measured from the top of [day]'s column.
  ///
  /// Clamped to the canvas: an entry that starts before the drawn window is
  /// pinned to its top edge rather than positioned off it, so a block always
  /// begins somewhere a reader can see and grab.
  double offsetOf(DateTime at, DateTime day) {
    final minutes = at.difference(_dayStart(day)).inMinutes - firstHour * 60;
    return (minutes / 60 * hourExtent).clamp(0.0, canvasHeight);
  }

  /// What the canvas position [offset] means on [day], rounded down to [step].
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
List<TimeGridSlot> packOverlaps(Iterable<TimeGridItem> items) {
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
    final end = clusterEnd;
    if (end != null && !item.start.isBefore(end)) {
      flush();
    }
    var lane = lanes.indexWhere((busyUntil) => !busyUntil.isAfter(item.start));
    if (lane < 0) {
      lanes.add(item.end);
      lane = lanes.length - 1;
    } else {
      lanes[lane] = item.end;
    }
    cluster.add((item: item, lane: lane));
    clusterEnd = clusterEnd == null || item.end.isAfter(clusterEnd!)
        ? item.end
        : clusterEnd;
  }
  flush();
  return slots;
}
