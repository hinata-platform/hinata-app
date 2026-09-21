/// The team absence calendar on a wide window: people down the side, days
/// across, and for who plans the capacity the group has left (HIN-118).
///
/// It draws exactly what the server sent. The server has applied the calendar
/// level and every type's own visibility, and sickness never arrives as
/// sickness. Three states read apart at a glance and in words: away is a
/// washed bar, requested a hatched one with an hourglass, and weekends and
/// holidays a wash behind both.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/team_absence_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/hive_widgets.dart' show HiveAvatar;
import '../../core/widgets/soft_card.dart';
import 'team_absence_style.dart';

/// The three states and the wash, named once under the chart. Colour never
/// carries the meaning alone: each swatch has its word beside it.
class TeamAbsenceLegend extends StatelessWidget {
  const TeamAbsenceLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final away = AppColors.inkSoft;
    Widget item(Widget swatch, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch,
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        item(_Swatch(color: away), context.t('absence.team.legend.away')),
        item(
          _Swatch(color: away, hatched: true),
          context.t('absence.team.legend.requested'),
        ),
        item(
          _Swatch(color: AppColors.dayOffWash, flat: true),
          context.t('absence.team.legend.dayOff'),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, this.hatched = false, this.flat = false});

  final Color color;
  final bool hatched;

  /// A plain fill, for the wash of days off, which has no outline.
  final bool flat;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 12,
    child: CustomPaint(
      painter: flat
          ? _FlatPainter(color)
          : TeamAbsenceBarPainter(
              color: color,
              hatched: hatched,
              outline: hatched ? color : null,
            ),
    ),
  );
}

class _FlatPainter extends CustomPainter {
  _FlatPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRRect(
    RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
    Paint()..color = color,
  );

  @override
  bool shouldRepaint(covariant _FlatPainter old) => old.color != color;
}

/// The chart: people down the side, days across, and the group's capacity on
/// top when the reader plans it. Both axes scroll; the names stay put.
class TeamAbsenceBand extends StatefulWidget {
  const TeamAbsenceBand({
    super.key,
    required this.from,
    required this.to,
    required this.rows,
    this.capacity,
    this.onNearEnd,
  });

  final DateTime from;
  final DateTime to;
  final List<TeamAbsenceRow> rows;
  final CapacityBand? capacity;

  /// Called when the rows are scrolled close to their end; null when every
  /// page is there.
  final VoidCallback? onNearEnd;

  @override
  State<TeamAbsenceBand> createState() => _TeamAbsenceBandState();
}

class _TeamAbsenceBandState extends State<TeamAbsenceBand> {
  final _hBody = ScrollController();
  final _hHeader = ScrollController();
  final _vBody = ScrollController();
  final _vLabels = ScrollController();
  bool _didInitialScroll = false;

  static const _baseRow = 44.0;
  static const _baseHeader = 50.0;
  static const _baseCapacity = 40.0;

  // Grow with the reader's text size (WCAG 1.4.4): at 200 % a fixed 46-point
  // head cut the month and the weekday off. Measured in initState's absence,
  // on every build, from the scaler in force.
  double _rowHeight = _baseRow;
  double _headerHeight = _baseHeader;
  double _capacityHeight = _baseCapacity;

  @override
  void initState() {
    super.initState();
    _hBody.addListener(() => _follow(_hHeader, _hBody.offset));
    _vBody.addListener(() {
      _follow(_vLabels, _vBody.offset);
      final ask = widget.onNearEnd;
      if (ask != null &&
          _vBody.position.pixels >=
              _vBody.position.maxScrollExtent - kTeamAbsenceNearEnd) {
        ask();
      }
    });
  }

  @override
  void didUpdateWidget(covariant TeamAbsenceBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.from != widget.from || oldWidget.to != widget.to) {
      _didInitialScroll = false;
    }
  }

  @override
  void dispose() {
    _hBody.dispose();
    _hHeader.dispose();
    _vBody.dispose();
    _vLabels.dispose();
    super.dispose();
  }

  /// The days of the window, built once per window: the row painters compare
  /// the list by identity, so a new list on every build repainted every row.
  List<DateTime>? _days;
  DateTime? _daysFrom;
  DateTime? _daysTo;

  List<DateTime> _daysOf(DateTime from, DateTime to) {
    if (_days == null || _daysFrom != from || _daysTo != to) {
      _daysFrom = from;
      _daysTo = to;
      _days = List.unmodifiable([
        for (
          var day = dateOnly(from);
          !day.isAfter(to);
          day = DateTime(day.year, day.month, day.day + 1)
        )
          day,
      ]);
    }
    return _days!;
  }

  void _follow(ScrollController follower, double offset) {
    if (!follower.hasClients) return;
    final target = offset.clamp(0.0, follower.position.maxScrollExtent);
    if ((follower.offset - target).abs() > 0.5) follower.jumpTo(target);
  }

  void _scrollToToday(int? todayIndex, double pxPerDay) {
    if (_didInitialScroll) return;
    _didInitialScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hBody.hasClients) return;
      final viewport = _hBody.position.viewportDimension;
      final target = todayIndex == null
          ? 0.0
          : todayIndex * pxPerDay + pxPerDay / 2 - viewport / 2;
      _hBody.jumpTo(target.clamp(0.0, _hBody.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _chart(context, constraints.maxWidth),
  );

  Widget _chart(BuildContext context, double available) {
    final compact = context.isCompact;
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      2.5,
    );
    _rowHeight = _baseRow * scale;
    _headerHeight = _baseHeader * scale;
    _capacityHeight = _baseCapacity * scale;
    final labelWidth = math.min(
      (compact ? 128.0 : 188.0) * scale,
      available * (compact ? 0.42 : 0.3),
    );
    final days = _daysOf(widget.from, widget.to);
    // At least the base width a day needs, and wide enough that a month fills
    // the card on a wide window rather than stopping two thirds across it.
    final minPerDay = (compact ? 28.0 : 32.0) * (1 + (scale - 1) * 0.5);
    final pxPerDay = math.max(
      minPerDay,
      (available - labelWidth - 3) / days.length,
    );
    final width = days.length * pxPerDay;
    final today = dateOnly(DateTime.now());
    final todayIndex = days.indexWhere((day) => day == today);
    _scrollToToday(todayIndex < 0 ? null : todayIndex, pxPerDay);
    final capacity = widget.capacity;
    final head = _headerHeight + (capacity == null ? 0 : _capacityHeight);

    return LayoutBuilder(
      builder: (context, box) {
        // As tall as the rows need and no taller: five people in a card the
        // height of the window left most of it empty.
        const cardBorder = 2.0;
        final rowsHeight = widget.rows.length * _rowHeight;
        final room = box.maxHeight.isFinite
            ? math.max(0.0, box.maxHeight - head - 1 - cardBorder)
            : rowsHeight;
        final body = math.min(rowsHeight, room);
        return Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: SizedBox(
            height: head + 1 + body + cardBorder,
            child: _card(
              context,
              head,
              body,
              labelWidth,
              width,
              days,
              pxPerDay,
              todayIndex,
              capacity,
              scale,
            ),
          ),
        );
      },
    );
  }

  Widget _card(
    BuildContext context,
    double head,
    double body,
    double labelWidth,
    double width,
    List<DateTime> days,
    double pxPerDay,
    int todayIndex,
    CapacityBand? capacity,
    double scale,
  ) {
    return SoftCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SizedBox(
            height: head,
            child: Row(
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Column(
                    children: [
                      SizedBox(
                        height: _headerHeight,
                        child: _CornerLabel(context.t('absence.team.person')),
                      ),
                      if (capacity != null)
                        SizedBox(
                          height: _capacityHeight,
                          child: _CornerLabel(
                            context.t('absence.team.capacity'),
                            detail: context.t(
                              'absence.team.capacityPeople',
                              variables: {'count': '${capacity.people}'},
                              count: capacity.people,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(width: 1, color: AppColors.hairline),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _hHeader,
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: SizedBox(
                      width: width,
                      child: Column(
                        children: [
                          SizedBox(
                            height: _headerHeight,
                            child: _DayAxis(
                              days: days,
                              pxPerDay: pxPerDay,
                              todayIndex: todayIndex,
                            ),
                          ),
                          if (capacity != null)
                            SizedBox(
                              height: _capacityHeight,
                              child: _CapacityStrip(
                                days: days,
                                pxPerDay: pxPerDay,
                                band: capacity,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.hairline),
          SizedBox(
            height: body,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: labelWidth,
                  child: ListView.builder(
                    controller: _vLabels,
                    physics: const NeverScrollableScrollPhysics(),
                    itemExtent: _rowHeight,
                    itemCount: widget.rows.length,
                    itemBuilder: (context, index) => _PersonLabel(
                      row: widget.rows[index],
                      lines: scale > 1.3 ? 2 : 1,
                    ),
                  ),
                ),
                Container(width: 1, color: AppColors.hairline),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _hBody,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      child: ListView.builder(
                        controller: _vBody,
                        itemExtent: _rowHeight,
                        itemCount: widget.rows.length,
                        // Each row paints on its own layer: a page arriving
                        // below must not repaint the rows already on screen.
                        itemBuilder: (context, index) => RepaintBoundary(
                          child: _PersonRow(
                            row: widget.rows[index],
                            days: days,
                            pxPerDay: pxPerDay,
                            todayIndex: todayIndex,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CornerLabel extends StatelessWidget {
  const _CornerLabel(this.label, {this.detail});

  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: AppColors.textSecondary,
          ),
        ),
        if (detail != null)
          Text(
            detail!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
          ),
      ],
    ),
  );
}

class _PersonLabel extends StatelessWidget {
  const _PersonLabel({required this.row, this.lines = 1});

  final TeamAbsenceRow row;

  /// Two at a large text size, where one line leaves three letters of a name.
  final int lines;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        HiveAvatar(name: row.name, imageUrl: row.avatarUrl, size: 24),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            row.name,
            maxLines: lines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The days across the top: the day of the month over its weekday letter,
/// the month's name where a month begins, today in the accent.
class _DayAxis extends StatelessWidget {
  const _DayAxis({
    required this.days,
    required this.pxPerDay,
    required this.todayIndex,
  });

  final List<DateTime> days;
  final double pxPerDay;
  final int todayIndex;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final weekday = DateFormat.E(locale);
    final month = DateFormat.MMM(locale);
    return Row(
      children: [
        for (var i = 0; i < days.length; i++)
          SizedBox(
            width: pxPerDay,
            child: _DayHead(
              day: days[i],
              today: i == todayIndex,
              month: i == 0 || days[i].day == 1 ? month.format(days[i]) : null,
              weekday: weekday.format(days[i]).characters.first,
            ),
          ),
      ],
    );
  }
}

class _DayHead extends StatelessWidget {
  const _DayHead({
    required this.day,
    required this.today,
    required this.weekday,
    this.month,
  });

  final DateTime day;
  final bool today;
  final String weekday;
  final String? month;

  @override
  Widget build(BuildContext context) {
    final weekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = today
        // accentStrong reaches 3.3:1 on the card; the deeper honey clears 4.5.
        ? (dark ? AppColors.accent : AppColors.accentDeep)
        : weekend
        ? AppColors.inkFaint
        : AppColors.inkSoft;
    // Scaled down rather than cut off when a font runs taller than the head.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            month ?? '',
            maxLines: 1,
            overflow: TextOverflow.clip,
            softWrap: false,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSoft,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: today
                ? BoxDecoration(
                    color: AppColors.accentDeep,
                    borderRadius: BorderRadius.circular(9),
                  )
                : null,
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: today ? FontWeight.w800 : FontWeight.w600,
                color: today ? AppColors.textOnDark : color,
              ),
            ),
          ),
          Text(weekday, style: TextStyle(fontSize: 9.5, color: color)),
        ],
      ),
    );
  }
}

/// What the group has left per day: a bar as high as the share of planned
/// minutes still available, with the numbers in its tooltip. Days nobody
/// planned carry no bar.
class _CapacityStrip extends StatelessWidget {
  const _CapacityStrip({
    required this.days,
    required this.pxPerDay,
    required this.band,
  });

  final List<DateTime> days;
  final double pxPerDay;
  final CapacityBand band;

  @override
  Widget build(BuildContext context) {
    final byDay = {
      for (final bucket in band.buckets) dateOnly(bucket.from): bucket,
    };
    return Row(
      children: [
        for (final day in days)
          SizedBox(
            width: pxPerDay,
            child: _CapacityDay(bucket: byDay[day]),
          ),
      ],
    );
  }
}

class _CapacityDay extends StatelessWidget {
  const _CapacityDay({required this.bucket});

  final CapacityBucket? bucket;

  @override
  Widget build(BuildContext context) {
    final bucket = this.bucket;
    if (bucket == null || bucket.scheduledMinutes <= 0) {
      return const SizedBox.shrink();
    }
    String hours(int minutes) => formatAbsenceHours(context, minutes);
    final message = context.t(
      'absence.team.capacityDay',
      variables: {
        'left': hours(bucket.capacityMinutes),
        'planned': hours(bucket.scheduledMinutes),
        'away': '${bucket.away}',
        'requested': '${bucket.requested}',
      },
    );
    final share = bucket.share.clamp(0.0, 1.0);
    final low = share < 0.5;
    return Tooltip(
      message: message,
      child: Semantics(
        label: message,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              widthFactor: 0.3,
              heightFactor: math.max(0.08, share),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: low ? AppColors.danger : AppColors.accentInk,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One person across the window: the wash of their days off behind, their
/// absences and requests as bars in front, today as a hairline.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.row,
    required this.days,
    required this.pxPerDay,
    required this.todayIndex,
  });

  final TeamAbsenceRow row;
  final List<DateTime> days;
  final double pxPerDay;
  final int todayIndex;

  @override
  Widget build(BuildContext context) {
    final first = days.first;
    final last = days.last;
    final holidays = {
      for (final holiday in row.holidays) dateOnly(holiday.date): holiday,
    };
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _RowWashPainter(
              days: days,
              pxPerDay: pxPerDay,
              holidays: holidays.keys.toSet(),
              wash: AppColors.dayOffWash,
              line: AppColors.hairline2,
              today: todayIndex < 0 ? null : todayIndex,
              todayColor: AppColors.accentStrong,
            ),
          ),
        ),
        for (final holiday in holidays.values)
          if (!holiday.date.isBefore(first) && !holiday.date.isAfter(last))
            Positioned(
              left: _index(holiday.date) * pxPerDay,
              width: pxPerDay,
              top: 0,
              bottom: 0,
              child: Tooltip(
                message: holiday.name ?? context.t('absence.team.holiday'),
                child: Semantics(
                  label: holiday.name ?? context.t('absence.team.holiday'),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(
                        LucideIcons.sparkle,
                        size: 9,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        for (final entry in row.entries) _bar(context, entry, first, last),
      ],
    );
  }

  int _index(DateTime day) => dateOnly(day).difference(days.first).inDays;

  Widget _bar(
    BuildContext context,
    TeamAbsenceEntry entry,
    DateTime first,
    DateTime last,
  ) {
    final from = entry.from.isBefore(first) ? first : entry.from;
    final to = entry.to.isAfter(last) ? last : entry.to;
    if (to.isBefore(from)) return const SizedBox.shrink();
    final span = to.difference(from).inDays + 1;
    final widthDays = entry.halfDay && span == 1 ? 0.5 : span.toDouble();
    final width = math.max(8.0, widthDays * pxPerDay - 4);
    final visuals = TeamAbsenceVisuals.of(context, entry);
    final label = teamAbsenceLabel(context, entry);
    final localizations = MaterialLocalizations.of(context);
    final dates = entry.from == entry.to
        ? localizations.formatShortDate(entry.from)
        : '${localizations.formatShortDate(entry.from)} – '
              '${localizations.formatShortDate(entry.to)}';
    final message = [
      row.name,
      label,
      dates,
      if (entry.requested) context.t('absence.team.legend.requested'),
    ].join(' · ');
    return Positioned(
      left: _index(from) * pxPerDay + 2,
      width: width,
      top: 9,
      height: 26,
      child: Tooltip(
        message: message,
        child: Semantics(
          label: message,
          child: CustomPaint(
            painter: visuals.painter(entry),
            child: width < 22
                ? null
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    child: Row(
                      children: [
                        Icon(visuals.icon, size: 12, color: visuals.ink),
                        if (width >= 56) ...[
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: visuals.ink,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _RowWashPainter extends CustomPainter {
  _RowWashPainter({
    required this.days,
    required this.pxPerDay,
    required this.holidays,
    required this.wash,
    required this.line,
    required this.today,
    required this.todayColor,
  });

  final List<DateTime> days;
  final double pxPerDay;
  final Set<DateTime> holidays;
  final Color wash;
  final Color line;
  final int? today;
  final Color todayColor;

  @override
  void paint(Canvas canvas, Size size) {
    final washPaint = Paint()..color = wash;
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final off =
          day.weekday == DateTime.saturday ||
          day.weekday == DateTime.sunday ||
          holidays.contains(day);
      if (off) {
        canvas.drawRect(
          Rect.fromLTWH(i * pxPerDay, 0, pxPerDay, size.height),
          washPaint,
        );
      }
    }
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = line
        ..strokeWidth = 1,
    );
    final at = today;
    if (at != null) {
      canvas.drawRect(
        Rect.fromLTWH(at * pxPerDay, 0, pxPerDay, size.height),
        Paint()..color = todayColor.withValues(alpha: 0.08),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RowWashPainter old) =>
      !identical(old.days, days) ||
      old.pxPerDay != pxPerDay ||
      !setEquals(old.holidays, holidays) ||
      old.wash != wash ||
      old.line != line ||
      old.today != today ||
      old.todayColor != todayColor;
}
