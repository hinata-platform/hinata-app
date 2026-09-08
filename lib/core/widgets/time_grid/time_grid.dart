/// A day/week grid with an hour axis, and the things drawn on it.
///
/// Shared on purpose. The calendar draws time entries here today; the stages
/// after this one add absences, holidays and subscribed calendar events, and
/// shift planning (HIN-44) draws shifts on the same surface. So the widget
/// knows about spans and layers, and nothing about work items.
///
/// **Times are the caller's.** Everything handed in is already in the zone the
/// grid should read — see the `zone` note on [TimeGrid.days]. A grid that
/// converted would need to know whose zone, and that answer differs between the
/// person looking (a time entry) and the thing itself (an event with a zone of
/// its own, which HIN-44 needs).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'time_grid_geometry.dart';
import 'time_grid_model.dart';

/// Width of the hour axis down the leading edge.
const double kTimeGridGutter = 56;

/// Height of the day heading above each column.
const double kTimeGridHeader = 46;

/// Height of one band row under the headings.
const double kTimeGridBandRow = 26;

/// Most rows one band layer is drawn in.
///
/// A band row holds one item per day, so a day with six untimed entries needs
/// six rows — and six rows of chips push the hour canvas off a phone. Past the
/// ceiling the last row says how many are left; the list view is where somebody
/// reads all of them anyway.
const int kTimeGridBandRowsMax = 3;

/// Narrowest a day column is drawn before the grid scrolls sideways instead of
/// squeezing. Seven columns of less than this on a phone is a chart nobody can
/// read, so the week scrolls.
const double kTimeGridMinColumn = 104;

/// What a drag produced, before anything has been saved.
typedef TimeGridSpan = ({DateTime start, DateTime end});

/// One block, worked out: where it goes and what colour it is.
typedef _Placed = ({TimeGridSlot slot, Rect rect, Color tint});

class TimeGrid extends StatefulWidget {
  const TimeGrid({
    super.key,
    required this.days,
    required this.layers,
    this.metrics = const TimeGridMetrics(),
    this.step = const Duration(minutes: 15),
    this.now,
    this.minColumnWidth = kTimeGridMinColumn,
    this.onCreate,
    this.onMoved,
    this.onTap,
    this.initialScrollHour = 8,
    this.showHeadings = true,
    this.newEntryLength = const Duration(hours: 1),
  });

  /// The columns, as local dates. One for a day view, seven for a week — the
  /// grid does not care which, and draws whatever it is given.
  final List<DateTime> days;

  final List<TimeGridLayer> layers;
  final TimeGridMetrics metrics;

  /// What a drag rounds to.
  final Duration step;

  /// Where the "now" line goes. Injectable so a test can place it.
  final DateTime? now;

  final double minColumnWidth;

  /// A span swept out on empty canvas. Null makes the grid read-only for
  /// creation.
  final void Function(TimeGridSpan span)? onCreate;

  /// A block moved or resized. The item carries its original span; the span is
  /// where it was dropped.
  final void Function(TimeGridItem item, TimeGridSpan span)? onMoved;

  /// A block or a band chip was tapped — both, deliberately: an entry with no
  /// clock is still an entry, and opening it is the same act as opening one on
  /// the canvas. The item is always the caller's own, never the copy a column
  /// was drawn from.
  final void Function(TimeGridItem item)? onTap;

  /// The hour the grid opens on, so a reader lands on the working day instead
  /// of on midnight.
  final int initialScrollHour;

  /// How long an entry is when the gesture said *where* but not *how long* —
  /// a tap, or a press that never moved.
  ///
  /// An hour rather than [step]: the step is the grain a sweep rounds to, and
  /// fifteen minutes is a useful grain and a useless default. The sheet opens
  /// on it either way, so this is a starting point, not a decision.
  final Duration newEntryLength;

  /// Whether each column writes its own date above it.
  ///
  /// A week has to: seven columns are seven days and nothing else says which.
  /// A single day drawn under a week strip does not — the strip names the day,
  /// and the page writes it out in full underneath — so the heading would be
  /// the third time in four centimetres. The band keeps its place either way.
  final bool showHeadings;

  @override
  State<TimeGrid> createState() => _TimeGridState();
}

/// What the finger is doing right now.
enum _DragKind { create, move, resize }

class _Drag {
  _Drag({
    required this.kind,
    required this.anchor,
    required this.start,
    required this.end,
    this.item,
    required this.dayIndex,
  }) : moved = false;

  final _DragKind kind;

  /// Whether the pointer ever left the point it went down on. A sweep says how
  /// long; a press that stayed put only says where.
  bool moved;

  /// Where the finger went down, and the one end of a sweep that does not move.
  ///
  /// Its own field because [start] and [end] are the *current* span and are
  /// rewritten on every pointer sample: reading the anchor back off [start], as
  /// this did, means the anchor follows the highest point the finger reached
  /// and a sweep can never be walked back down.
  final DateTime anchor;

  DateTime start;
  DateTime end;

  /// The block being moved or resized; null while creating.
  final TimeGridItem? item;

  /// Which column the drag is currently over.
  int dayIndex;

  TimeGridSpan get span => (start: start, end: end);
}

class _TimeGridState extends State<TimeGrid> {
  final _vertical = ScrollController();
  final _hBody = ScrollController();
  final _hHeader = ScrollController();

  _Drag? _drag;
  bool _didInitialScroll = false;

  /// The last placement worked out, and the inputs it was worked out from.
  ///
  /// Filtering, packing and rectangle arithmetic do not depend on the drag, and
  /// a drag rebuilds on every pointer sample: recomputing them there meant, per
  /// frame, one pass over every item per column, seven sorts, and four
  /// allocations per block. At a hundred-odd entries in a week that is a couple
  /// of thousand objects a frame — steady churn through a gesture that changes
  /// none of it.
  List<_Placed>? _placed;
  Object? _placedKey;

  /// The same, for how many rows each band layer needs: three call sites asked
  /// for it and each walked every item in the layer.
  Map<TimeGridLayer, int>? _bandRowCounts;

  @override
  void initState() {
    super.initState();
    // The two horizontal axes are two viewports over one width; the header
    // follows the body rather than the other way round, so a fling on the
    // canvas is the one that drives.
    _hBody.addListener(_followHeader);
  }

  @override
  void dispose() {
    _hBody.removeListener(_followHeader);
    _vertical.dispose();
    _hBody.dispose();
    _hHeader.dispose();
    super.dispose();
  }

  void _followHeader() {
    if (!_hHeader.hasClients) return;
    final target = _hBody.offset.clamp(0.0, _hHeader.position.maxScrollExtent);
    if ((_hHeader.offset - target).abs() > 0.5) _hHeader.jumpTo(target);
  }

  TimeGridMetrics get _metrics => widget.metrics;

  List<TimeGridLayer> get _blockLayers => widget.layers
      .where((l) => l.placement == TimeGridPlacement.blocks)
      .toList();

  /// The band layers that have something to show **on the days drawn** — not
  /// merely something in them.
  ///
  /// The difference is the whole of the "all-day" row's behaviour. A caller may
  /// hold a fortnight of entries and draw one day of it (the phone's calendar
  /// does exactly that, so a swipe to the next day has its hours already), and
  /// `!isEmpty` would then reserve a row on every one of those days because
  /// some other day has an untimed entry on it. A strip labelled "Ganztägig"
  /// with nothing in it is a claim about the day that is not true.
  List<TimeGridLayer> get _bandLayers => widget.layers
      .where((l) => l.placement == TimeGridPlacement.band && _bandRows(l) > 0)
      .toList();

  List<TimeGridLayer> get _washLayers => widget.layers
      .where((l) => l.placement == TimeGridPlacement.background)
      .toList();

  double get _bandHeight => _bandLayers
      .map((layer) => _bandRows(layer) * kTimeGridBandRow)
      .fold(0.0, (sum, height) => sum + height);

  /// How many rows [layer] needs: as many as its busiest drawn day has items,
  /// capped at [kTimeGridBandRowsMax]. Zero when no drawn day has any, which is
  /// how the row disappears rather than standing empty.
  int _bandRows(TimeGridLayer layer) {
    // Counted over every band layer, not over [_bandLayers] — that getter asks
    // this one which layers have a row, so filling the memo from it would be a
    // cycle.
    final counts = _bandRowCounts ??= {
      // Keyed on the layer, not its id: nothing requires an id to be unique,
      // and two layers sharing one would collapse to a single count while the
      // height above still summed both.
      for (final band in widget.layers)
        if (band.placement == TimeGridPlacement.band)
          band: _countBandRows(band),
    };
    return counts[layer] ?? 0;
  }

  int _countBandRows(TimeGridLayer layer) {
    var most = 0;
    for (final day in widget.days) {
      final count = _itemsOn(layer, day).length;
      if (count > most) most = count;
    }
    return most.clamp(0, kTimeGridBandRowsMax);
  }

  double _columnWidth(double available) => math.max(
    widget.minColumnWidth,
    available / math.max(1, widget.days.length),
  );

  DateTime _dayAt(int index) =>
      widget.days[index.clamp(0, widget.days.length - 1)];

  /// Which column a canvas x falls in.
  int _dayIndexAt(double dx, double columnWidth) =>
      (dx / columnWidth).floor().clamp(0, widget.days.length - 1);

  // --- interaction ------------------------------------------------------------

  /// The block under a canvas point, if any — and whether the point is on its
  /// bottom edge, which is what makes a drag a resize instead of a move.
  ///
  /// The item handed back is the caller's, never the clipped copy the column was
  /// drawn from. Clipping is geometry; a gesture is about the entry. A drag reads
  /// the item's own `start`, `end` and `duration` to work out where it lands, so
  /// grabbing the second half of a 22:00–06:00 entry and dropping it at nine
  /// would otherwise report a six-hour span — and the save that follows rewrites
  /// the entry to it. Eight hours becomes six, silently, in a working-time
  /// record.
  ({TimeGridItem item, bool onEdge})? _hitTest(
    Offset local,
    double columnWidth,
  ) {
    final index = _dayIndexAt(local.dx, columnWidth);
    final day = _dayAt(index);
    for (final layer in _blockLayers.reversed) {
      final slots = packOverlaps(_itemsOn(layer, day));
      for (final slot in slots.reversed) {
        final rect = _rectOf(slot, index, columnWidth);
        if (rect.contains(local)) {
          return (
            item: _originalOf(layer, slot.item),
            onEdge: local.dy > rect.bottom - 10,
          );
        }
      }
    }
    return null;
  }

  /// The item [drawn] was cut from, or [drawn] itself when nothing was cut.
  TimeGridItem _originalOf(TimeGridLayer layer, TimeGridItem drawn) {
    for (final item in layer.items) {
      if (item.id == drawn.id) return item;
    }
    return drawn;
  }

  /// [layer]'s items as [day]'s column sees them.
  ///
  /// A span that runs past midnight appears in every column it touches, cut to
  /// that column's hours — placed only in its start's column it was drawn from
  /// its start to the bottom of the canvas and the rest appeared nowhere, which
  /// for a night shift (HIN-44's ordinary case, not its edge) is most of the
  /// block missing.
  ///
  /// The clipped copy keeps the original's id and data, but its span is the
  /// column's — so it is for drawing and hit *testing* only. Every gesture
  /// resolves back to the caller's item through [_originalOf] before it reaches
  /// a callback, because a drag computes from the item's own span and would
  /// otherwise rewrite the entry to the half that was grabbed.
  Iterable<TimeGridItem> _itemsOn(TimeGridLayer layer, DateTime day) sync* {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = DateTime(day.year, day.month, day.day + 1);
    for (final item in layer.items) {
      if (_sameDay(item.start, day) && !item.end.isAfter(dayEnd)) {
        yield item; // the ordinary case: one day, uncut
        continue;
      }
      if (item.start.isBefore(dayEnd) && item.end.isAfter(dayStart)) {
        yield item.movedTo(
          item.start.isBefore(dayStart) ? dayStart : item.start,
          item.end.isAfter(dayEnd) ? dayEnd : item.end,
        );
      }
    }
  }

  Rect _rectOf(TimeGridSlot slot, int dayIndex, double columnWidth) {
    final day = _dayAt(dayIndex);
    final top = _metrics.offsetOf(slot.item.start, day);
    final bottom = _metrics.offsetOf(slot.item.end, day);
    final laneWidth = (columnWidth - 6) / slot.columns;
    return Rect.fromLTRB(
      dayIndex * columnWidth + 3 + slot.column * laneWidth,
      top,
      dayIndex * columnWidth + 3 + (slot.column + 1) * laneWidth - 2,
      // A one-minute entry is still worth grabbing, so a block never draws
      // thinner than a finger can find.
      math.max(bottom, top + 18),
    );
  }

  void _beginDrag(Offset local, double columnWidth) {
    final index = _dayIndexAt(local.dx, columnWidth);
    final hit = _hitTest(local, columnWidth);
    if (hit != null) {
      if (!hit.item.movable || widget.onMoved == null) return;
      setState(() {
        _drag = _Drag(
          kind: hit.onEdge ? _DragKind.resize : _DragKind.move,
          anchor: hit.item.start,
          start: hit.item.start,
          end: hit.item.end,
          item: hit.item,
          dayIndex: index,
        );
      });
      return;
    }
    if (widget.onCreate == null) return;
    final at = _metrics.timeAt(local.dy, _dayAt(index), step: widget.step);
    setState(() {
      _drag = _Drag(
        kind: _DragKind.create,
        anchor: at,
        start: at,
        end: at.add(widget.step),
        dayIndex: index,
      );
    });
  }

  void _updateDrag(Offset local, double columnWidth) {
    final drag = _drag;
    if (drag == null) return;
    final index = _dayIndexAt(local.dx, columnWidth);
    drag.moved = true;
    setState(() {
      switch (drag.kind) {
        case _DragKind.create:
          // A sweep stays in the column it began in: the anchor is a time on
          // that day, and pairing it with a time read off another one produces
          // a span across midnight that the grid cannot draw and the editor
          // would not have been asked for.
          final at = _metrics.timeAt(
            local.dy,
            _dayAt(drag.dayIndex),
            step: widget.step,
          );
          // Upwards is a span too — the anchor is where the finger went down,
          // not whichever end is earlier.
          drag.start = at.isBefore(drag.anchor) ? at : drag.anchor;
          drag.end = at.isBefore(drag.anchor) ? drag.anchor : at;
          if (!drag.end.isAfter(drag.start)) {
            drag.end = drag.start.add(widget.step);
          }
        case _DragKind.move:
          final at = _metrics.timeAt(
            local.dy,
            _dayAt(index),
            step: widget.step,
          );
          final length = drag.item!.duration;
          drag.start = at;
          drag.end = at.add(length);
          drag.dayIndex = index;
        case _DragKind.resize:
          // The start stays put; only the end follows, and never past it.
          final at = _metrics.timeAt(
            local.dy,
            _dayAt(drag.dayIndex),
            step: widget.step,
          );
          drag.end = at.isAfter(drag.start) ? at : drag.start.add(widget.step);
      }
    });
  }

  void _endDrag() {
    final drag = _drag;
    setState(() => _drag = null);
    if (drag == null) return;
    if (!drag.end.isAfter(drag.start)) return;
    if (drag.kind == _DragKind.create) {
      // A press that never moved said *where*, not *how long* — the same thing
      // a tap says, and it gets the same answer. Without this the two gestures
      // would disagree by three quarters of an hour for no reason a reader
      // could name.
      widget.onCreate?.call(
        drag.moved ? drag.span : _spanAt(drag.anchor),
      );
    } else {
      widget.onMoved?.call(drag.item!, drag.span);
    }
  }

  /// The pointer went away without finishing. The preview goes with it, and
  /// nothing is created — a cancelled gesture is not a smaller request.
  void _cancelDrag() {
    if (_drag == null) return;
    setState(() => _drag = null);
  }

  /// What a gesture that only named a moment asks for.
  TimeGridSpan _spanAt(DateTime at) => (
    start: at,
    end: at.add(widget.newEntryLength),
  );

  /// One tap opens the block under it; two on empty canvas start an entry.
  ///
  /// Two, not one. A single tap on empty canvas is the easiest gesture on the
  /// grid to make by accident — scrolling, dismissing something, putting the
  /// window in front — and an editor that opens by itself reads as a bug rather
  /// than as an offer. A double click is what a calendar has meant by "new
  /// entry here" for thirty years, and it is the only create gesture a mouse
  /// gets for free: pressing and holding half a second is something nobody
  /// does, which is what left the web with no way to create at all.
  ///
  /// One [SerialTapGestureRecognizer] rather than a tap and a double tap side
  /// by side, and that is the load-bearing part. Two recognizers in one arena
  /// make *every* tap wait out the double-tap window before it fires — three
  /// hundred milliseconds added to opening an entry, on every entry, to pay for
  /// a gesture used once an hour. This one reports each tap of the series as it
  /// happens and tells you which one it was.
  void _onSerialTapUp(SerialTapUpDetails details, double columnWidth) {
    final local = details.localPosition;
    final hit = _hitTest(local, columnWidth);
    if (hit != null) {
      // The second click of a double click on a block is the same block again;
      // opening it twice would stack two editors on one entry.
      if (details.count == 1) widget.onTap?.call(hit.item);
      return;
    }
    if (details.count != 2 || widget.onCreate == null) return;
    final index = _dayIndexAt(local.dx, columnWidth);
    widget.onCreate!.call(
      _spanAt(_metrics.timeAt(local.dy, _dayAt(index), step: widget.step)),
    );
  }

  // --- build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - kTimeGridGutter;
        final columnWidth = _columnWidth(available);
        final canvasWidth = columnWidth * widget.days.length;
        _scheduleInitialScroll();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _headerHeight + _bandHeight,
              child: Row(
                children: [
                  SizedBox(width: kTimeGridGutter, child: _bandLabels()),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _hHeader,
                      scrollDirection: Axis.horizontal,
                      // Driven by the body, never by itself: two scrollables
                      // that both accept input fight over the same fling.
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        width: canvasWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.showHeadings)
                              SizedBox(
                                height: kTimeGridHeader,
                                child: Row(
                                  children: [
                                    for (final day in widget.days)
                                      SizedBox(
                                        width: columnWidth,
                                        child: _DayHeading(
                                          day: day,
                                          today: _isToday(day),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            for (final layer in _bandLayers)
                              _BandRows(
                                layer: layer,
                                days: widget.days,
                                columnWidth: columnWidth,
                                rows: _bandRows(layer),
                                itemsOn: (day) => _itemsOn(layer, day),
                                onTap: widget.onTap,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: AppColors.hairline),
            Expanded(
              child: SingleChildScrollView(
                controller: _vertical,
                child: SizedBox(
                  height: _metrics.canvasHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: kTimeGridGutter,
                        child: _HourAxis(metrics: _metrics),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _hBody,
                          scrollDirection: Axis.horizontal,
                          // A canvas that already fits must not take the drag.
                          // A single day inside a horizontal pager is exactly
                          // that, and a scroller with nowhere to go still wins
                          // the gesture arena against its parent — which would
                          // eat the swipe to the next day.
                          // Half a point of slack, because the width is
                          // arrived at by dividing and multiplying back:
                          // `(available / 7) * 7` can exceed `available` by an
                          // ulp, and an exact compare would leave live physics
                          // on a canvas with a scroll extent of 1e-13.
                          physics: canvasWidth <= available + 0.5
                              ? const NeverScrollableScrollPhysics()
                              : null,
                          child: SizedBox(
                            width: canvasWidth,
                            child: _canvas(columnWidth),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _scheduleInitialScroll() {
    if (_didInitialScroll) return;
    _didInitialScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_vertical.hasClients) return;
      // A little above the hour, not exactly on it: the axis writes each label
      // seven pixels above its line, so landing on the line cuts the label the
      // grid opened on in half.
      final target =
          (widget.initialScrollHour - _metrics.firstHour) *
              _metrics.hourExtent -
          10;
      _vertical.jumpTo(target.clamp(0.0, _vertical.position.maxScrollExtent));
    });
  }

  /// What the day headings occupy — nothing when the page writes them itself.
  double get _headerHeight => widget.showHeadings ? kTimeGridHeader : 0;

  Widget _bandLabels() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(height: _headerHeight),
      for (final layer in _bandLayers)
        SizedBox(
          height: _bandRows(layer) * kTimeGridBandRow,
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Align(
              alignment: AlignmentDirectional.topEnd,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                // The gutter is narrower than most words for "untimed", so the
                // label ellipsises and the tooltip carries the rest.
                child: Tooltip(
                  message: layer.label ?? '',
                  child: Text(
                    layer.label ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: AppColors.inkFaint),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _canvas(double columnWidth) {
    final drag = _drag;
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      // Three recognizers, because a finger and a mouse are not the same
      // instrument and the same gesture is wrong for both.
      //
      // A **tap** opens what is under it, and a **double tap** on empty canvas
      // starts an entry there — both from one serial recognizer, so neither
      // waits on the other. See [_onSerialTapUp].
      //
      // A **long press, then drag** is the sweep on touch. Not a plain pan: a
      // pan started by a finger inside a scroll view never wins the arena (its
      // slop is twice the scrollable's), so drag-to-create would scroll the
      // grid instead. Holding first also keeps a stray finger from rewriting an
      // entry by brushing past it.
      //
      // A **plain pan, for pointing devices only**, is that same sweep with a
      // mouse or a stylus — where holding still for half a second before
      // dragging is a gesture nobody performs, and the web was consequently
      // left with no way to sweep at all. A precise pointer has a one-pixel
      // slop, so this wins the arena against the scrollables around it the way
      // a finger's pan cannot. Trackpads are deliberately excluded: a two-finger
      // scroll arrives as a pan-zoom event, and accepting it here would sweep
      // out an entry every time somebody scrolled the day.
      gestures: <Type, GestureRecognizerFactory>{
        SerialTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<SerialTapGestureRecognizer>(
              SerialTapGestureRecognizer.new,
              (recognizer) {
                recognizer.onSerialTapUp = (details) {
                  _onSerialTapUp(details, columnWidth);
                };
              },
            ),
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              LongPressGestureRecognizer.new,
              (recognizer) {
                // Block bodies, not arrows: an `=>` inside a cascade swallows
                // the `..` that follows it, and the next assignment silently
                // becomes a cascade on the *result* of this callback.
                recognizer.onLongPressStart = (details) {
                  _beginDrag(details.localPosition, columnWidth);
                };
                recognizer.onLongPressMoveUpdate = (details) {
                  _updateDrag(details.localPosition, columnWidth);
                };
                recognizer.onLongPressEnd = (_) => _endDrag();
                recognizer.onLongPressCancel = _cancelDrag;
              },
            ),
        PanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
              () => PanGestureRecognizer(
                supportedDevices: const {
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.invertedStylus,
                },
              ),
              (recognizer) {
                // Where the pointer went *down*, not where the drag was
                // recognised. The default reports the latter, so a drag begun
                // on a block and pulled downwards hit-tests a point already
                // past it — and moving an entry silently created a new one an
                // hour below instead.
                recognizer.dragStartBehavior = DragStartBehavior.down;
                recognizer.onStart = (details) {
                  _beginDrag(details.localPosition, columnWidth);
                };
                recognizer.onUpdate = (details) {
                  _updateDrag(details.localPosition, columnWidth);
                };
                recognizer.onEnd = (_) => _endDrag();
                recognizer.onCancel = _cancelDrag;
              },
            ),
      },
      child: Stack(
        children: [
          // Its own layer: the vertical viewport marks its child for paint on
          // every scroll offset, and without a boundary that re-records every
          // line, wash and block instead of moving a layer that is already
          // rasterised.
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                isComplex: true,
                willChange: false,
                painter: _GridPainter(
                  days: widget.days,
                  metrics: _metrics,
                  columnWidth: columnWidth,
                  now: _nowOnGrid(),
                  lineColor: AppColors.hairline,
                  hourColor: AppColors.hairline2,
                  weekendColor: AppColors.canvas2,
                  nowColor: AppColors.accentStrong,
                  washes: [
                    for (final layer in _washLayers)
                      for (final item in layer.items)
                        (
                          day: DateTime(
                            item.start.year,
                            item.start.month,
                            item.start.day,
                          ),
                          color:
                              (item.tint ?? layer.tint ?? AppColors.accentSoft)
                                  .withValues(alpha: 0.35),
                        ),
                  ],
                ),
              ),
            ),
          ),
          for (final placed in _placedBlocks(columnWidth))
            Positioned.fromRect(
              rect: placed.rect,
              // Each block its own layer. The painter's boundary retains the
              // lines and washes; without one here the blocks — a decoration and
              // a paragraph or two each — are still re-recorded on every scroll
              // frame, and at a hundred-odd entries they are the larger half.
              child: RepaintBoundary(
                child: _Block(
                  item: placed.slot.item,
                  tint: placed.tint,
                  dimmed: drag?.item?.id == placed.slot.item.id,
                ),
              ),
            ),
          if (drag != null) ..._dragPreview(drag, columnWidth),
        ],
      ),
    );
  }

  List<_Placed> _placedBlocks(double columnWidth) {
    // A record, not a hash: records compare structurally, and a hash is a
    // fingerprint — a collision would hand back a stale placement while
    // `_hitTest`, which is not memoised, kept computing the real one. The two
    // would then disagree, and a tap would land on a block nobody can see.
    //
    // Spans rather than counts, so an edit that keeps the number of items — a
    // block dragged an hour, which is the common case — is a different key. A
    // few hundred hashCodes per build buys away an invariant the caller would
    // otherwise have to know about.
    final key = (
      columnWidth,
      _metrics.hourExtent,
      _metrics.firstHour,
      _metrics.lastHour,
      Object.hashAll(widget.days),
      Object.hashAll([
        for (final layer in widget.layers) ...[
          layer.id,
          layer.placement,
          layer.tint,
          for (final item in layer.items) ...[
            item.id,
            item.start,
            item.end,
            item.tint,
          ],
        ],
      ]),
    );
    final cached = _placed;
    if (cached != null && _placedKey == key) return cached;
    final placed = <_Placed>[];
    for (final layer in _blockLayers) {
      for (var index = 0; index < widget.days.length; index++) {
        for (final slot in packOverlaps(_itemsOn(layer, _dayAt(index)))) {
          placed.add((
            slot: slot,
            rect: _rectOf(slot, index, columnWidth),
            tint: slot.item.tint ?? layer.tint ?? AppColors.accent,
          ));
        }
      }
    }
    _placed = placed;
    _placedKey = key;
    return placed;
  }

  @override
  void didUpdateWidget(TimeGrid old) {
    super.didUpdateWidget(old);
    // The key above counts items rather than comparing them, which is cheap and
    // catches everything except an edit that keeps the count. A new layer list
    // is the signal for that, and it is the one the caller always gives.
    if (!identical(old.layers, widget.layers) ||
        !identical(old.days, widget.days)) {
      _placed = null;
      _bandRowCounts = null;
    }
  }

  List<Widget> _dragPreview(_Drag drag, double columnWidth) {
    final day = _dayAt(drag.dayIndex);
    final top = _metrics.offsetOf(drag.start, day);
    final bottom = _metrics.offsetOf(drag.end, day);
    return [
      Positioned.fromRect(
        rect: Rect.fromLTRB(
          drag.dayIndex * columnWidth + 3,
          top,
          (drag.dayIndex + 1) * columnWidth - 3,
          math.max(bottom, top + 18),
        ),
        child: _DragPreview(label: _spanLabel(context, drag.start, drag.end)),
      ),
    ];
  }

  /// Where the "now" line goes, to the minute.
  ///
  /// Truncated on purpose. `DateTime.now()` is microsecond-resolution, so an
  /// untruncated value differs on every single build — and it is compared in
  /// [_GridPainter.shouldRepaint], which therefore never returned false and
  /// re-recorded the whole canvas on every frame of every drag. At the grid's
  /// zoom the line moves one pixel a minute; anything finer is a repaint for a
  /// difference nobody can see.
  DateTime? _nowOnGrid() {
    final now = widget.now ?? DateTime.now();
    if (!widget.days.any((day) => _sameDay(now, day))) return null;
    return DateTime(now.year, now.month, now.day, now.hour, now.minute);
  }

  bool _isToday(DateTime day) => _sameDay(widget.now ?? DateTime.now(), day);
}

String _spanLabel(BuildContext context, DateTime start, DateTime end) {
  final localizations = MaterialLocalizations.of(context);
  final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
  return '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(start), alwaysUse24HourFormat: use24)}'
      ' – '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(end), alwaysUse24HourFormat: use24)}';
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ─────────────────────────────── parts ────────────────────────────────────

class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.day, required this.today});

  final DateTime day;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          localizations.narrowWeekdays[day.weekday % 7],
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: today ? AppColors.accentStrong : AppColors.inkFaint,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: today
              ? BoxDecoration(
                  color: AppColors.accentSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accentLine),
                )
              : null,
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: today ? AppColors.accentStrong : AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class _HourAxis extends StatelessWidget {
  const _HourAxis({required this.metrics});

  final TimeGridMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    return Stack(
      children: [
        for (var hour = metrics.firstHour + 1; hour < metrics.lastHour; hour++)
          Positioned(
            top: (hour - metrics.firstHour) * metrics.hourExtent - 7,
            right: 6,
            child: Text(
              localizations.formatTimeOfDay(
                TimeOfDay(hour: hour, minute: 0),
                alwaysUse24HourFormat: use24,
              ),
              style: TextStyle(fontSize: 10, color: AppColors.inkFaint),
            ),
          ),
      ],
    );
  }
}

/// The all-day strip: one row per item a day holds, up to the ceiling.
///
/// A day with four untimed entries needs four rows, not four chips stacked in
/// the same place — which is what one row per *layer* drew, and it read as a
/// single entry with the others invisible underneath it. The strip is as tall
/// as the busiest day in the window, so the days line up and a reader can count
/// them across.
class _BandRows extends StatelessWidget {
  const _BandRows({
    required this.layer,
    required this.days,
    required this.columnWidth,
    required this.rows,
    required this.itemsOn,
    this.onTap,
  });

  final TimeGridLayer layer;
  final List<DateTime> days;
  final double columnWidth;
  final int rows;

  /// The same filter the row count was worked out from — passed in rather than
  /// reimplemented, because two answers to "which items does this column hold"
  /// is exactly how the strip came to reserve rows it never filled.
  final Iterable<TimeGridItem> Function(DateTime day) itemsOn;

  final void Function(TimeGridItem)? onTap;

  @override
  Widget build(BuildContext context) {
    final tint = layer.tint ?? AppColors.accent;
    return SizedBox(
      height: rows * kTimeGridBandRow,
      child: Stack(
        children: [
          for (var index = 0; index < days.length; index++)
            ..._chipsFor(index, tint),
        ],
      ),
    );
  }

  Iterable<Widget> _chipsFor(int index, Color tint) sync* {
    // Every column the item covers, which is what `TimeGridPlacement.band`
    // promises — an absence spanning a week is one item and belongs in all seven
    // of them. The row *count* is worked out the same way, and the two used to
    // disagree: rows were reserved across the week for a chip drawn in one
    // column, leaving blank strips beside it.
    final onDay = itemsOn(days[index]).toList();
    // The last row is given over to a count when there are more than fit, so
    // the number on screen is never a lie about how much is there.
    final shown = onDay.length > rows ? rows - 1 : onDay.length;
    for (var row = 0; row < shown; row++) {
      yield _positioned(index, row, _chip(onDay[row], tint));
    }
    if (onDay.length > shown) {
      yield _positioned(index, shown, _more(onDay.length - shown, tint));
    }
  }

  Widget _positioned(int index, int row, Widget child) => Positioned(
    left: index * columnWidth + 3,
    top: row * kTimeGridBandRow + 3,
    width: columnWidth - 6,
    height: kTimeGridBandRow - 6,
    child: child,
  );

  Widget _chip(TimeGridItem item, Color tint) => GestureDetector(
    onTap: onTap == null ? null : () => onTap!(item),
    child: Tooltip(
      message: item.title,
      child: _pill(
        (item.tint ?? tint).withValues(alpha: 0.22),
        item.title,
        AppColors.ink,
      ),
    ),
  );

  Widget _more(int count, Color tint) =>
      _pill(tint.withValues(alpha: 0.12), '+$count', AppColors.inkSoft);

  Widget _pill(Color background, String label, Color ink) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: AlignmentDirectional.centerStart,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 10, color: ink),
    ),
  );
}

class _Block extends StatelessWidget {
  const _Block({required this.item, required this.tint, this.dimmed = false});

  final TimeGridItem item;
  final Color tint;

  /// The block a drag has picked up: still in its old place, but plainly not
  /// the thing being moved.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.35 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(6),
          border: Border(left: BorderSide(color: tint, width: 2.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            if (item.subtitle != null)
              Text(
                item.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: AppColors.inkSoft),
              ),
          ],
        ),
      ),
    );
  }
}

class _DragPreview extends StatelessWidget {
  const _DragPreview({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.accentStrong, width: 1.5),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.accentStrong,
      ),
    ),
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.days,
    required this.metrics,
    required this.columnWidth,
    required this.lineColor,
    required this.hourColor,
    required this.weekendColor,
    required this.nowColor,
    required this.washes,
    this.now,
  });

  final List<DateTime> days;
  final TimeGridMetrics metrics;
  final double columnWidth;
  final Color lineColor;
  final Color hourColor;
  final Color weekendColor;
  final Color nowColor;
  final List<({DateTime day, Color color})> washes;
  final DateTime? now;

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0; index < days.length; index++) {
      final day = days[index];
      final column = Rect.fromLTWH(
        index * columnWidth,
        0,
        columnWidth,
        size.height,
      );
      if (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
        canvas.drawRect(column, Paint()..color = weekendColor);
      }
      for (final wash in washes) {
        if (_sameDay(wash.day, day)) {
          canvas.drawRect(column, Paint()..color = wash.color);
        }
      }
    }

    final hourPaint = Paint()
      ..color = hourColor
      ..strokeWidth = 1;
    final halfPaint = Paint()
      ..color = hourColor.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (var hour = 0; hour <= metrics.hourCount; hour++) {
      final y = hour * metrics.hourExtent;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hourPaint);
      if (hour < metrics.hourCount && metrics.hourExtent >= 40) {
        final half = y + metrics.hourExtent / 2;
        canvas.drawLine(Offset(0, half), Offset(size.width, half), halfPaint);
      }
    }

    final columnPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    for (var index = 1; index < days.length; index++) {
      final x = index * columnWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), columnPaint);
    }

    final at = now;
    if (at != null) {
      final index = days.indexWhere((day) => _sameDay(day, at));
      if (index >= 0) {
        final y = metrics.offsetOf(at, days[index]);
        final paint = Paint()
          ..color = nowColor
          ..strokeWidth = 2;
        canvas.drawLine(
          Offset(index * columnWidth, y),
          Offset((index + 1) * columnWidth, y),
          paint,
        );
        canvas.drawCircle(
          Offset(index * columnWidth + 3, y),
          3.5,
          Paint()..color = nowColor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.columnWidth != columnWidth ||
      old.metrics.hourExtent != metrics.hourExtent ||
      old.metrics.firstHour != metrics.firstHour ||
      old.metrics.lastHour != metrics.lastHour ||
      old.now != now ||
      old.lineColor != lineColor ||
      old.hourColor != hourColor ||
      old.weekendColor != weekendColor ||
      old.nowColor != nowColor ||
      // Element-wise, not by count: a wash that moves from Monday to Tuesday,
      // or changes colour, leaves the list exactly as long. That is the shape
      // stage 10's holidays and absences arrive in.
      !listEquals(old.washes, washes) ||
      !_sameDays(old.days, days);

  static bool _sameDays(List<DateTime> a, List<DateTime> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
