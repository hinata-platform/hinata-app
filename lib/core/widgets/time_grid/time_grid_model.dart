/// What a [TimeGrid] draws, and where.
///
/// Deliberately not tied to a work item. The grid is shared: the calendar draws
/// time entries on it today, and the stages after this one draw absences,
/// holidays and subscribed calendar events on the same surface — as does shift
/// planning (HIN-44), which is why this lives in `core/widgets` rather than in
/// the time feature. Anything that can name a span and a title can be a layer.
library;

import 'package:flutter/widgets.dart';

/// One thing on the grid: a span, what to call it, and whether it may be moved.
@immutable
class TimeGridItem {
  const TimeGridItem({
    required this.id,
    required this.start,
    required this.end,
    required this.title,
    this.subtitle,
    this.tint,
    this.movable = false,
    this.data,
  });

  final String id;

  /// The span, in the grid's own zone — see [TimeGrid.zone]. Converting is the
  /// caller's job, so the grid never has to know what a time *means*.
  final DateTime start;
  final DateTime end;

  final String title;
  final String? subtitle;

  /// The block's colour. Null takes the layer's.
  final Color? tint;

  /// Whether this one answers a drag or a resize. A holiday does not.
  final bool movable;

  /// Whatever the caller needs back in a callback — the entry behind the block.
  final Object? data;

  Duration get duration => end.difference(start);

  /// A copy spanning [start]..[end], for the preview a drag paints before the
  /// server has agreed to it.
  TimeGridItem movedTo(DateTime start, DateTime end) => TimeGridItem(
    id: id,
    start: start,
    end: end,
    title: title,
    subtitle: subtitle,
    tint: tint,
    movable: movable,
    data: data,
  );
}

/// Where a layer's items are drawn.
enum TimeGridPlacement {
  /// On the hour canvas, positioned by their span and packed side by side where
  /// they overlap. Time entries, and later shifts.
  blocks,

  /// In the strip under the day headings, one row per layer, spanning the days
  /// it covers. For everything that occupies a day rather than a time: an
  /// absence, a holiday — and, today, an entry logged as a plain duration,
  /// which has no hours to be drawn between.
  band,

  /// A wash behind a whole day column. Nothing is written in it; it says
  /// something about the day itself.
  background,
}

/// A stack of items drawn together, with one look and one interaction.
@immutable
class TimeGridLayer {
  const TimeGridLayer({
    required this.id,
    required this.items,
    this.placement = TimeGridPlacement.blocks,
    this.tint,
    this.label,
  });

  final String id;
  final List<TimeGridItem> items;
  final TimeGridPlacement placement;

  /// The colour items of this layer take unless they name their own.
  final Color? tint;

  /// What the band row is called, shown at its leading edge. Bands only.
  final String? label;

  bool get isEmpty => items.isEmpty;
}
