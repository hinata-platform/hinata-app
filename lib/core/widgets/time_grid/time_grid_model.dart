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
    this.minutes,
    this.day,
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

  /// How much time this item accounts for, when its span cannot say.
  ///
  /// Normally null: a block on the hour canvas accounts for exactly the hours
  /// it covers, and [accounted] measures them. An entry logged as a plain
  /// duration has no hours — it begins and ends at midnight — and still counts
  /// towards its day, which is the number a month is read for.
  final int? minutes;

  /// The day this item is *filed* under, when that is not simply the day it
  /// starts on.
  ///
  /// The two come apart more easily than they look. A time entry's reporting
  /// day is a field of its own on the server, set in the account's zone and
  /// left alone when only the interval is edited — so an entry moved from the
  /// 10th to the 20th still belongs to the 10th, and that is the day the
  /// server selected it by and the timesheet adds it into.
  ///
  /// **Which of the two a view uses depends on what it is drawing.** Anything
  /// that *lists* a day files by [filedOn] — the month's cells, the timesheet,
  /// a day's total — because that is the day the record says the work belongs
  /// to, and the one the server selected the window by. The hour canvas places
  /// by the span instead, because a block has to be where its hours are, and
  /// cuts one that crosses midnight into both columns. The two answers must
  /// therefore both be reachable: a caller that hands the canvas only the items
  /// filed on the day it is drawing loses every entry whose hours were moved
  /// off it, and the tail of every overnight one.
  final DateTime? day;

  /// Whatever the caller needs back in a callback — the entry behind the block.
  final Object? data;

  /// The day this item belongs to: [day] when the caller named one, and
  /// otherwise the day it starts on.
  DateTime get filedOn => day ?? DateTime(start.year, start.month, start.day);

  Duration get duration => end.difference(start);

  /// What this item adds to a day's total.
  Duration get accounted =>
      minutes != null ? Duration(minutes: minutes!) : duration;

  /// A copy spanning [start]..[end], for the preview a drag paints before the
  /// server has agreed to it.
  ///
  /// [day] and [minutes] carry over by default, which is what the hour canvas
  /// wants: it clips a block to a column without the entry moving at all, and
  /// the record's own numbers must survive that. A caller that is moving the
  /// entry — a drop, which re-files it — passes the new [day] and lets
  /// [minutes] fall back to the new span, or the preview sits filed under the
  /// day it came from with the total it used to have.
  TimeGridItem movedTo(
    DateTime start,
    DateTime end, {
    DateTime? day,
    bool keepMinutes = true,
  }) => TimeGridItem(
    id: id,
    start: start,
    end: end,
    title: title,
    subtitle: subtitle,
    tint: tint,
    movable: movable,
    minutes: keepMinutes ? minutes : null,
    day: day ?? this.day,
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
    this.glyph,
  });

  final String id;
  final List<TimeGridItem> items;
  final TimeGridPlacement placement;

  /// The colour items of this layer take unless they name their own.
  final Color? tint;

  /// What the band row is called, shown at its leading edge. Bands only.
  final String? label;

  /// A mark beside the date of every day this layer covers. Background only.
  ///
  /// A wash on its own cannot say *what* it means, and the grid already has one:
  /// the weekend recedes behind exactly such a wash. A second wash would read as
  /// "this is also a weekend" — so a layer that says something else about a day
  /// names itself with a glyph in the heading, where the eye is already going for
  /// the date. The freeze of HIN-88 is the first; holidays and absences (HIN-91)
  /// are the next, and the same one line carries them.
  final IconData? glyph;
}
