import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/util/dates.dart';
import 'account_widgets.dart';

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

/// Settings → Notifications: the days on which e-mail and push may arrive.
///
/// Seven round day toggles, in the reader's week order. The design takes its
/// cue from Sahil Vhora's "Notification schedule" shot on Dribbble (initials in
/// circles, chosen ones filled); here the fill is Hinata's honey wash, as on
/// `GlassSwitchChip`, and the rest are hairline rings. At least one day stays
/// on: the last one says why instead of switching off, because "no days" would
/// read as "notifications off", which the channel switches above already are.
///
/// Every toggle is at least 48 by 48 and grows with the text size; where seven
/// of them do not fit side by side they wrap onto a second line rather than
/// shrinking below what a thumb hits.
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

  /// The new days, ascending; null to follow the default again.
  final ValueChanged<List<int>?> onChanged;

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
    final defaultSpan = formatDaySpan(
      widget.defaultWeekdays,
      order,
      shortName,
      (from, to) => context.t(
        'account.notifications.days.range',
        variables: {'from': from, 'to': to},
      ),
    );

    return SettingRow(
      label: context.t('account.notifications.days.title'),
      description: context.t('account.notifications.days.hint'),
      icon: LucideIcons.calendarDays,
      stack: true,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final d in order)
                _DayToggle(
                  tipKey: _tips[d]!,
                  label: shortName(d),
                  fullName: weekdayName(context, d),
                  selected: days.contains(d),
                  isLast: days.length == 1 && days.contains(d),
                  onTap: () => _toggle(d),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              Text(
                context.t(
                  'account.notifications.days.defaultLine',
                  variables: {'days': defaultSpan},
                ),
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
              if (widget.weekdays != null)
                TextButton(
                  onPressed: () => widget.onChanged(null),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: AppColors.accentInk,
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(
                    context.t('account.notifications.days.useDefault'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One round day toggle. The whole square cell is the hit target: 48 across
/// at the normal text size, and growing with the text so the name inside the
/// circle never has to shrink.
class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.tipKey,
    required this.label,
    required this.fullName,
    required this.selected,
    required this.isLast,
    required this.onTap,
  });

  final GlobalKey<TooltipState> tipKey;
  final String label;
  final String fullName;
  final bool selected;
  final bool isLast;
  final VoidCallback onTap;

  static const Duration _settle = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lastReason = context.t('account.notifications.days.lastDay');
    // 48 at the normal text size, and as much more as the text grows.
    final side = math.max(48.0, MediaQuery.textScalerOf(context).scale(48));
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
            dimension: side,
            child: Center(
              child: AnimatedContainer(
                duration: _settle,
                curve: Curves.easeOut,
                width: side - 4,
                height: side - 4,
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
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
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
    );
  }
}
