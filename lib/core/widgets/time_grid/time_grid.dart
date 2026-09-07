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

/// Narrowest a day column is drawn before the grid scrolls sideways instead of
/// squeezing. Seven columns of less than this on a phone is a chart nobody can
/// read, so the week scrolls.
const double kTimeGridMinColumn = 104;

/// What a drag produced, before anything has been saved.
typedef TimeGridSpan = ({DateTime start, DateTime end});

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

  final void Function(TimeGridItem item)? onTap;

  /// The hour the grid opens on, so a reader lands on the working day instead
  /// of on midnight.
  final int initialScrollHour;

  @override
  State<TimeGrid> createState() => _TimeGridState();
}

/// What the finger is doing right now.
enum _DragKind { create, move, resize }

class _Drag {
  _Drag({
    required this.kind,
    required this.start,
    required this.end,
    this.item,
    this.dayIndex = 0,
  });

  final _DragKind kind;
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

  List<TimeGridLayer> get _bandLayers => widget.layers
      .where((l) => l.placement == TimeGridPlacement.band && !l.isEmpty)
      .toList();

  List<TimeGridLayer> get _washLayers => widget.layers
      .where((l) => l.placement == TimeGridPlacement.background)
      .toList();

  double get _bandHeight => _bandLayers.length * kTimeGridBandRow;

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
          return (item: slot.item, onEdge: local.dy > rect.bottom - 10);
        }
      }
    }
    return null;
  }

  Iterable<TimeGridItem> _itemsOn(TimeGridLayer layer, DateTime day) =>
      layer.items.where((item) => _sameDay(item.start, day));

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

  void _onLongPressStart(LongPressStartDetails details, double columnWidth) {
    final local = details.localPosition;
    final index = _dayIndexAt(local.dx, columnWidth);
    final hit = _hitTest(local, columnWidth);
    if (hit != null) {
      if (!hit.item.movable || widget.onMoved == null) return;
      setState(() {
        _drag = _Drag(
          kind: hit.onEdge ? _DragKind.resize : _DragKind.move,
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
        start: at,
        end: at.add(widget.step),
        dayIndex: index,
      );
    });
  }

  void _onLongPressMove(
    LongPressMoveUpdateDetails details,
    double columnWidth,
  ) {
    final drag = _drag;
    if (drag == null) return;
    final local = details.localPosition;
    final index = _dayIndexAt(local.dx, columnWidth);
    final at = _metrics.timeAt(local.dy, _dayAt(index), step: widget.step);
    setState(() {
      switch (drag.kind) {
        case _DragKind.create:
          // Sweeping upwards is a span too — the anchor is wherever the finger
          // went down, not necessarily the earlier end.
          final anchor = drag.item?.start ?? drag.start;
          drag.start = at.isBefore(anchor) ? at : anchor;
          drag.end = at.isBefore(anchor) ? anchor : at;
          if (!drag.end.isAfter(drag.start)) {
            drag.end = drag.start.add(widget.step);
          }
          drag.dayIndex = index;
        case _DragKind.move:
          final length = drag.item!.duration;
          drag.start = at;
          drag.end = at.add(length);
          drag.dayIndex = index;
        case _DragKind.resize:
          // The start stays put; only the end follows, and never past it.
          drag.end = at.isAfter(drag.start) ? at : drag.start.add(widget.step);
      }
    });
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    final drag = _drag;
    setState(() => _drag = null);
    if (drag == null) return;
    // A span of nothing is a long press that never moved, not a request.
    if (!drag.end.isAfter(drag.start)) return;
    if (drag.kind == _DragKind.create) {
      widget.onCreate?.call(drag.span);
    } else {
      widget.onMoved?.call(drag.item!, drag.span);
    }
  }

  void _onTapUp(TapUpDetails details, double columnWidth) {
    final hit = _hitTest(details.localPosition, columnWidth);
    if (hit != null) widget.onTap?.call(hit.item);
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
              height: kTimeGridHeader + _bandHeight,
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
                              _BandRow(
                                layer: layer,
                                days: widget.days,
                                columnWidth: columnWidth,
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
      final target =
          (widget.initialScrollHour - _metrics.firstHour) * _metrics.hourExtent;
      _vertical.jumpTo(target.clamp(0.0, _vertical.position.maxScrollExtent));
    });
  }

  Widget _bandLabels() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: kTimeGridHeader),
      for (final layer in _bandLayers)
        SizedBox(
          height: kTimeGridBandRow,
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                layer.label ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: AppColors.inkFaint),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _canvas(double columnWidth) {
    final drag = _drag;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => _onTapUp(details, columnWidth),
      // Long press, then drag — not a plain pan. Inside a scroll view a pan
      // never wins the arena on touch (its slop is twice the scrollable's), so
      // a drag-to-create would scroll the grid instead. The long press also
      // keeps a stray finger from rewriting an entry by brushing past it.
      onLongPressStart: (details) => _onLongPressStart(details, columnWidth),
      onLongPressMoveUpdate: (details) =>
          _onLongPressMove(details, columnWidth),
      onLongPressEnd: _onLongPressEnd,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
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
                        color: (item.tint ?? layer.tint ?? AppColors.accentSoft)
                            .withValues(alpha: 0.35),
                      ),
                ],
              ),
            ),
          ),
          for (final placed in _placedBlocks(columnWidth))
            Positioned.fromRect(
              rect: placed.rect,
              child: _Block(
                item: placed.slot.item,
                tint: placed.tint,
                dimmed: drag?.item?.id == placed.slot.item.id,
              ),
            ),
          if (drag != null) ..._dragPreview(drag, columnWidth),
        ],
      ),
    );
  }

  Iterable<({TimeGridSlot slot, Rect rect, Color tint})> _placedBlocks(
    double columnWidth,
  ) sync* {
    for (final layer in _blockLayers) {
      for (var index = 0; index < widget.days.length; index++) {
        final slots = packOverlaps(_itemsOn(layer, _dayAt(index)));
        for (final slot in slots) {
          yield (
            slot: slot,
            rect: _rectOf(slot, index, columnWidth),
            tint: slot.item.tint ?? layer.tint ?? AppColors.accent,
          );
        }
      }
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

  DateTime? _nowOnGrid() {
    final now = widget.now ?? DateTime.now();
    return widget.days.any((day) => _sameDay(now, day)) ? now : null;
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

/// One row of all-day things across the columns they cover.
class _BandRow extends StatelessWidget {
  const _BandRow({
    required this.layer,
    required this.days,
    required this.columnWidth,
    this.onTap,
  });

  final TimeGridLayer layer;
  final List<DateTime> days;
  final double columnWidth;
  final void Function(TimeGridItem)? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kTimeGridBandRow,
      child: Stack(
        children: [
          for (var index = 0; index < days.length; index++)
            for (final item in layer.items.where(
              (item) => _sameDay(item.start, days[index]),
            ))
              Positioned(
                left: index * columnWidth + 3,
                top: 3,
                width: columnWidth - 6,
                height: kTimeGridBandRow - 6,
                child: GestureDetector(
                  onTap: onTap == null ? null : () => onTap!(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: AlignmentDirectional.centerStart,
                    decoration: BoxDecoration(
                      color: (item.tint ?? layer.tint ?? AppColors.accent)
                          .withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: AppColors.ink),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
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
      old.weekendColor != weekendColor ||
      old.washes.length != washes.length ||
      !_sameDays(old.days, days);

  static bool _sameDays(List<DateTime> a, List<DateTime> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
