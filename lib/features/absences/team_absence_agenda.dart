/// The team absence calendar on a phone: an agenda by week (HIN-118).
///
/// The band's grid does not survive a compact width. The names take two fifths
/// of it, five days remain, and a capacity drawn as bar heights has no number a
/// thumb can reach — the tooltip that carries it does not exist on touch. So a
/// phone reads the same data as a list: one block per week, what is left of the
/// group's capacity written out, and underneath the people who are away with
/// their span and what the reader may know about it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/team_absence_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_widgets.dart' show HiveAvatar;
import '../../core/widgets/soft_card.dart';
import 'absence_labels.dart';
import 'team_absence_calendar.dart' show teamAbsenceLabel, TeamAbsenceBarPainter;

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// One week of the window: Monday to Sunday, cut at the window's edges.
class _Week {
  _Week(this.from, this.to);

  final DateTime from;
  final DateTime to;

  bool holds(DateTime day) => !day.isBefore(from) && !day.isAfter(to);
}

class TeamAbsenceAgenda extends StatelessWidget {
  const TeamAbsenceAgenda({
    super.key,
    required this.from,
    required this.to,
    required this.rows,
    this.capacity,
    this.onNearEnd,
    this.padding = EdgeInsets.zero,
  });

  final DateTime from;
  final DateTime to;
  final List<TeamAbsenceRow> rows;
  final CapacityBand? capacity;
  final VoidCallback? onNearEnd;
  final EdgeInsets padding;

  List<_Week> _weeks() {
    final weeks = <_Week>[];
    var start = _dayOnly(from);
    final end = _dayOnly(to);
    while (!start.isAfter(end)) {
      final sunday = DateTime(start.year, start.month, start.day + (7 - start.weekday));
      final last = sunday.isAfter(end) ? end : sunday;
      weeks.add(_Week(start, last));
      start = DateTime(last.year, last.month, last.day + 1);
    }
    return weeks;
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _weeks();
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final ask = onNearEnd;
        if (ask != null &&
            notification.metrics.pixels >= notification.metrics.maxScrollExtent - 300) {
          ask();
        }
        return false;
      },
      child: ListView.separated(
        padding: padding,
        itemCount: weeks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _WeekCard(
          week: weeks[index],
          rows: rows,
          capacity: capacity,
        ),
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.week, required this.rows, this.capacity});

  final _Week week;
  final List<TeamAbsenceRow> rows;
  final CapacityBand? capacity;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final dayMonth = DateFormat.MMMd(locale);
    final weekday = DateFormat.E(locale);
    final today = _dayOnly(DateTime.now());
    final current = week.holds(today);

    final people = <({TeamAbsenceRow row, TeamAbsenceEntry entry})>[
      for (final row in rows)
        for (final entry in row.entries)
          if (!entry.to.isBefore(week.from) && !entry.from.isAfter(week.to))
            (row: row, entry: entry),
    ]..sort((a, b) => a.entry.from.compareTo(b.entry.from));

    final holidays = <String>{
      for (final row in rows)
        for (final holiday in row.holidays)
          if (week.holds(_dayOnly(holiday.date)))
            '${weekday.format(holiday.date)} ${dayMonth.format(holiday.date)} · ${holiday.name}',
    }.toList()..sort();

    var planned = 0;
    var left = 0;
    for (final bucket in capacity?.buckets ?? const <CapacityBucket>[]) {
      if (week.holds(_dayOnly(bucket.from))) {
        planned += bucket.scheduledMinutes;
        left += bucket.capacityMinutes;
      }
    }
    String hours(int minutes) => NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: minutes % 60 == 0 ? 0 : 1,
    ).format(minutes / 60);

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${dayMonth.format(week.from)} – ${dayMonth.format(week.to)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (current)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accentDeep,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    context.t('absence.team.thisWeek'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          if (capacity != null && planned > 0) ...[
            const SizedBox(height: 6),
            Text(
              context.t(
                'absence.team.capacityWeek',
                variables: {'left': hours(left), 'planned': hours(planned)},
              ),
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 6),
            _Meter(share: planned == 0 ? 1 : left / planned),
          ],
          for (final holiday in holidays) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(LucideIcons.sparkle, size: 13, color: AppColors.inkSoft),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    holiday,
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          if (people.isEmpty)
            Text(
              context.t('absence.team.everybodyHere'),
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
            )
          else
            for (final (index, item) in people.indexed) ...[
              if (index > 0) Divider(height: 14, color: AppColors.hairline2),
              _AgendaRow(row: item.row, entry: item.entry, week: week),
            ],
        ],
      ),
    );
  }
}

/// What is left of the week, as a line across the card. The sentence above it
/// carries the figure; this only makes a thin week stand out while scrolling.
class _Meter extends StatelessWidget {
  const _Meter({required this.share});

  final double share;

  @override
  Widget build(BuildContext context) {
    final value = share.clamp(0.0, 1.0);
    final low = value < 0.5;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 6,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: AppColors.hairline)),
              Positioned.fill(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: math.max(0.02, value),
                    heightFactor: 1,
                    child: ColoredBox(
                      color: low ? AppColors.danger : AppColors.accentInk,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({required this.row, required this.entry, required this.week});

  final TeamAbsenceRow row;
  final TeamAbsenceEntry entry;
  final _Week week;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    // "Do. 3." stays one word: at a large text size the plain space broke
    // the weekday from its date.
    final format = DateFormat('E d.', locale);
    String day(DateTime date) => format.format(date).replaceAll(' ', '\u00a0');
    final from = entry.from.isBefore(week.from) ? week.from : entry.from;
    final to = entry.to.isAfter(week.to) ? week.to : entry.to;
    final span = from == to ? day(from) : '${day(from)} – ${day(to)}';
    final label = teamAbsenceLabel(context, entry);
    final tint = entry.typed ? absenceColor(context, entry.hue) : AppColors.inkSoft;
    final ink = entry.typed ? absenceInk(context, entry.hue) : AppColors.ink;
    final requested = context.t('absence.team.legend.requested');
    return MergeSemantics(
      child: Row(
        children: [
          HiveAvatar(name: row.name, imageUrl: row.avatarUrl, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  entry.halfDay ? '$span · ½' : span,
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: CustomPaint(
              painter: TeamAbsenceBarPainter(
                color: tint,
                hatched: entry.requested,
                outline: entry.requested ? ink : null,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      entry.requested
                          ? LucideIcons.hourglass
                          : entry.typed
                          ? absenceIcon(entry.icon)
                          : LucideIcons.calendarOff,
                      size: 12,
                      color: ink,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        entry.requested ? '$label · $requested' : label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
