import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/util/dates.dart';

/// The ISO weekdays (1 Monday to 7 Sunday) in the order a week is read in a
/// locale whose week starts on [firstDayOfWeekIndex] (0 Sunday to 6 Saturday,
/// as `MaterialLocalizations` reports it).
List<int> orderedWeekdays(int firstDayOfWeekIndex) => [
  for (var i = 0; i < 7; i++)
    switch ((firstDayOfWeekIndex + i) % 7) {
      0 => DateTime.sunday,
      final d => d,
    },
];

/// "Mo bis Fr" when [days] run unbroken in [order] (three or more of them),
/// otherwise the short names joined with commas: "Mo, Mi, Fr".
String formatDaySpan(
  List<int> days,
  List<int> order,
  String Function(int weekday) shortName,
  String Function(String from, String to) range,
) {
  final positions = [for (final d in days) order.indexOf(d)]..sort();
  if (positions.isEmpty) return '';
  final unbroken = positions.last - positions.first + 1 == positions.length;
  if (unbroken && positions.length >= 3) {
    return range(
      shortName(order[positions.first]),
      shortName(order[positions.last]),
    );
  }
  return positions.map((p) => shortName(order[p])).join(', ');
}

/// The seven days of a notification schedule (HIN-129, HIN-131).
///
/// Seven round day toggles, in the reader's week order. The design takes its
/// cue from Sahil Vhora's "Notification schedule" shot on Dribbble (initials in
/// circles, chosen ones filled); here the fill is Hinata's honey wash, as on
/// `GlassSwitchChip`, and the rest are hairline rings. At least one day stays
/// on: the last one says why instead of switching off, because "no days" would
/// read as "notifications off", which the channel switches above already are.
///
/// The week always sits on one line. Each toggle is 48 by 48 where seven fit
/// and grows with the text size; on a narrow screen or at a large text size
/// the seven share the width instead, the name scaling down with its ring.
class NotificationDaysRow extends StatefulWidget {
  const NotificationDaysRow({
    super.key,
    required this.weekdays,
    required this.defaultWeekdays,
    required this.onChanged,
  });

  /// The person's own days (ISO, ascending), or null for the default.
  final List<int>? weekdays;

  /// What null works out to where the person lives.
  final List<int> defaultWeekdays;

  /// The new days, ascending.
  final ValueChanged<List<int>> onChanged;

  @override
  State<NotificationDaysRow> createState() => _NotificationDaysRowState();
}

class _NotificationDaysRowState extends State<NotificationDaysRow> {
  /// One per ISO weekday, so a tap on the last day can show its reason.
  final Map<int, GlobalKey<TooltipState>> _tips = {
    for (var d = DateTime.monday; d <= DateTime.sunday; d++)
      d: GlobalKey<TooltipState>(),
  };

  Set<int> get _effective => {...(widget.weekdays ?? widget.defaultWeekdays)};

  void _toggle(int weekday) {
    final days = _effective;
    if (days.contains(weekday)) {
      if (days.length == 1) {
        _tips[weekday]?.currentState?.ensureTooltipVisible();
        // The tooltip is for the eye; a screen reader hears the reason too.
        SemanticsService.sendAnnouncement(
          View.of(context),
          context.t('account.notifications.days.lastDay'),
          Directionality.of(context),
        );
        return;
      }
      days.remove(weekday);
    } else {
      days.add(weekday);
    }
    widget.onChanged(days.toList()..sort());
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final order = orderedWeekdays(
      MaterialLocalizations.of(context).firstDayOfWeekIndex,
    );
    final short = DateFormat.E(locale);
    String shortName(int weekday) {
      final name = short.format(DateTime(2024, 1, weekday));
      // "Mo." in German — the dot is an abbreviation mark, not part of the day.
      return name.endsWith('.') ? name.substring(0, name.length - 1) : name;
    }

    final days = _effective;

    // Always one line, the way a week is read. Each day gets a seventh of the
    // width, capped at its natural size, so a wide window keeps round 48s and
    // a narrow phone or a large text size shrinks the rings rather than
    // breaking the week in two.
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = math.min(
          _DayToggle.sideFor(context),
          constraints.maxWidth / order.length,
        );
        return Row(
          children: [
            for (final d in order)
              _DayToggle(
                tipKey: _tips[d]!,
                label: shortName(d),
                fullName: weekdayName(context, d),
                selected: days.contains(d),
                isLast: days.length == 1 && days.contains(d),
                cell: cell,
                onTap: () => _toggle(d),
              ),
          ],
        );
      },
    );
  }
}

/// One round day toggle. The whole square cell is the hit target: 48 across
/// at the normal text size and growing with the text, as far as a seventh of
/// the row allows.
class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.tipKey,
    required this.label,
    required this.fullName,
    required this.selected,
    required this.isLast,
    required this.onTap,
    required this.cell,
  });

  /// 48 at the normal text size, and as much more as the text grows.
  static double sideFor(BuildContext context) =>
      math.max(48.0, MediaQuery.textScalerOf(context).scale(48));

  final GlobalKey<TooltipState> tipKey;
  final String label;
  final String fullName;
  final bool selected;
  final bool isLast;
  final VoidCallback onTap;

  /// The square cell's side: [sideFor], or less where seven do not fit.
  final double cell;

  static const Duration _settle = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lastReason = context.t('account.notifications.days.lastDay');
    final ring = cell - 4;
    return Tooltip(
      key: tipKey,
      message: isLast ? lastReason : fullName,
      child: Semantics(
        button: true,
        selected: selected,
        label: fullName,
        hint: isLast ? lastReason : null,
        excludeSemantics: true,
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: cell,
            child: Center(
              child: AnimatedContainer(
                duration: _settle,
                curve: Curves.easeOut,
                width: ring,
                height: ring,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // A wash, not a slab: the honey tint of the switch
                  // chips, so a row of seven does not shout.
                  color: selected
                      ? AppColors.accent.withValues(alpha: dark ? 0.30 : 0.22)
                      : Colors.transparent,
                  border: Border.all(
                    color: selected ? AppColors.accentLine : AppColors.hairline,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(4),
                // Scales the name down only when the ring had to shrink.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      // The deep honey ink in light mode: the amber of
                      // the ring is too pale for text this small.
                      color: selected
                          ? (dark ? AppColors.accent : AppColors.accentText)
                          : AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
