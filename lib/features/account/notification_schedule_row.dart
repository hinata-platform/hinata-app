import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/account_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_switch_chip.dart';
import '../sprint/modals/glass_modal.dart' show showGlassTimePicker;
import 'account_widgets.dart';
import 'notification_days_row.dart';
import '../../core/theme/app_type.dart';

/// Settings → Notifications: when e-mail and push may arrive (HIN-131).
///
/// A glass switch between **Always** and **Custom**. Custom fades in the week
/// ([NotificationDaysRow]) and the window's **From** and **Until**, each a
/// button that opens the glass time picker, never an inline wheel. The switch
/// is the inline [GlassSwitchBar], as on the deadline basis: it stands in a
/// card, and a lens inside a card refracts a refraction.
///
/// Without a choice of the person's own the organisation's day count decides
/// ([NotifPrefs.defaultSchedule]); the line under the controls says what that
/// is, and **Use default** goes back to it.
class NotificationScheduleRow extends StatelessWidget {
  const NotificationScheduleRow({
    super.key,
    required this.prefs,
    required this.onChanged,
  });

  final NotifPrefs prefs;

  /// The preferences with the new schedule, to be saved.
  final ValueChanged<NotifPrefs> onChanged;

  static const _fade = Duration(milliseconds: 240);

  void _choose(NotifSchedule schedule) {
    if (schedule == NotifSchedule.always) {
      onChanged(prefs.copyWith(schedule: NotifSchedule.always));
      return;
    }
    // A first switch to custom starts from what applied: the days, and the
    // organisation's hours or office hours.
    onChanged(
      prefs.copyWith(
        schedule: NotifSchedule.custom,
        weekdays: prefs.effectiveWeekdays,
        from: prefs.from ?? prefs.defaultFrom ?? NotifPrefs.officeFrom,
        until: prefs.until ?? prefs.defaultUntil ?? NotifPrefs.officeUntil,
      ),
    );
  }

  /// Any change inside the custom block makes the whole choice the person's.
  NotifPrefs _custom({List<int>? days, String? from, String? until}) =>
      prefs.copyWith(
        schedule: NotifSchedule.custom,
        weekdays: days ?? prefs.effectiveWeekdays,
        from: from ?? prefs.effectiveFrom ?? NotifPrefs.officeFrom,
        until: until ?? prefs.effectiveUntil ?? NotifPrefs.officeUntil,
      );

  Future<void> _pick(BuildContext context, {required bool start}) async {
    final current =
        (start ? prefs.effectiveFrom : prefs.effectiveUntil) ??
        (start ? NotifPrefs.officeFrom : NotifPrefs.officeUntil);
    final picked = await showGlassTimePicker(
      context,
      initial: _parse(current),
      title: context.t(
        start
            ? 'account.notifications.schedule.from'
            : 'account.notifications.schedule.until',
      ),
    );
    if (picked == null) return;
    final text = _wire(picked);
    onChanged(start ? _custom(from: text) : _custom(until: text));
  }

  @override
  Widget build(BuildContext context) {
    final custom = prefs.effectiveSchedule == NotifSchedule.custom;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final Widget block = custom
        ? Padding(
            key: const ValueKey('custom'),
            padding: const EdgeInsets.only(top: 12),
            child: _CustomBlock(
              prefs: prefs,
              onDays: (days) => onChanged(_custom(days: days)),
              onPick: (start) => unawaited(_pick(context, start: start)),
            ),
          )
        : const SizedBox(key: ValueKey('always'), width: 0);
    return SettingRow(
      label: context.t('account.notifications.schedule.title'),
      description: context.t('account.notifications.schedule.hint'),
      icon: LucideIcons.bellRing,
      stack: true,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: GlassSwitchBar(
              inline: true,
              maxWidth: 360,
              chips: [
                _chip(context, NotifSchedule.always, LucideIcons.bell, custom),
                const SizedBox(width: 2),
                _chip(
                  context,
                  NotifSchedule.custom,
                  LucideIcons.calendarClock,
                  custom,
                ),
              ],
            ),
          ),
          // The custom block fades in and the card grows to it, rather than
          // the controls appearing all at once; with reduced motion it simply
          // appears (an AnimatedSize of zero length re-dirties its own layout).
          if (reduceMotion)
            block
          else
            AnimatedSize(
              duration: _fade,
              curve: Curves.easeOutCubic,
              alignment: AlignmentDirectional.topStart,
              child: AnimatedSwitcher(
                duration: _fade,
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: block,
              ),
            ),
          const SizedBox(height: 6),
          _DefaultLine(
            prefs: prefs,
            onUseDefault: prefs.followsDefault
                ? null
                : () => onChanged(
                    prefs.copyWith(
                      schedule: null,
                      weekdays: null,
                      from: null,
                      until: null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    NotifSchedule schedule,
    IconData icon,
    bool custom,
  ) {
    final active = (schedule == NotifSchedule.custom) == custom;
    return Semantics(
      selected: active,
      child: GlassSwitchChip(
        label: context.t(
          schedule == NotifSchedule.always
              ? 'account.notifications.schedule.always'
              : 'account.notifications.schedule.custom',
        ),
        icon: icon,
        active: active,
        onTap: active ? null : () => _choose(schedule),
      ),
    );
  }
}

/// The week and the window, shown while the schedule is custom.
class _CustomBlock extends StatelessWidget {
  const _CustomBlock({
    required this.prefs,
    required this.onDays,
    required this.onPick,
  });

  final NotifPrefs prefs;
  final ValueChanged<List<int>> onDays;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    final from = prefs.effectiveFrom;
    final until = prefs.effectiveUntil;
    final overnight =
        from != null && until != null && until.compareTo(from) < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        NotificationDaysRow(
          weekdays: prefs.effectiveWeekdays,
          defaultWeekdays: prefs.defaultWeekdays,
          onChanged: onDays,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _TimeButton(
              label: context.t('account.notifications.schedule.from'),
              value: from,
              onTap: () => onPick(true),
            ),
            _TimeButton(
              label: context.t('account.notifications.schedule.until'),
              value: until,
              onTap: () => onPick(false),
            ),
          ],
        ),
        if (overnight)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              context.t('account.notifications.schedule.overnight'),
              style: TextStyle(
                fontSize: AppType.caption,
                color: AppColors.inkSoft,
              ),
            ),
          ),
      ],
    );
  }
}

/// "Von  09:00": a caption and the button that opens the time picker.
class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;

  /// `HH:mm`, or null for the whole day.
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shown = value == null
        ? context.t('account.notifications.schedule.allDay')
        : _formatTime(context, value!);
    // A Wrap, so a long caption or a large text size puts the button under
    // the caption instead of pushing it off the card.
    return MergeSemantics(
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppType.label,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
          AccountActionButton(
            label: shown,
            icon: LucideIcons.clock,
            onPressed: onTap,
          ),
        ],
      ),
    );
  }
}

/// What applies without a choice, and the way back to it.
class _DefaultLine extends StatelessWidget {
  const _DefaultLine({required this.prefs, required this.onUseDefault});

  final NotifPrefs prefs;
  final VoidCallback? onUseDefault;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        Text(
          _describe(context),
          style: TextStyle(fontSize: AppType.caption, color: AppColors.inkSoft),
        ),
        if (onUseDefault != null)
          TextButton(
            onPressed: onUseDefault,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: AppColors.accentInk,
              textStyle: const TextStyle(
                fontSize: AppType.label,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(context.t('account.notifications.schedule.useDefault')),
          ),
      ],
    );
  }

  String _describe(BuildContext context) {
    if (prefs.defaultSchedule == NotifSchedule.always) {
      return context.t('account.notifications.schedule.defaultAlways');
    }
    final locale = Localizations.localeOf(context).toLanguageTag();
    final order = orderedWeekdays(
      MaterialLocalizations.of(context).firstDayOfWeekIndex,
    );
    final short = DateFormat.E(locale);
    String shortName(int weekday) {
      final name = short.format(DateTime(2024, 1, weekday));
      return name.endsWith('.') ? name.substring(0, name.length - 1) : name;
    }

    final days = formatDaySpan(
      prefs.defaultWeekdays,
      order,
      shortName,
      (from, to) => context.t(
        'account.notifications.days.range',
        variables: {'from': from, 'to': to},
      ),
    );
    final from = prefs.defaultFrom;
    final until = prefs.defaultUntil;
    if (from == null || until == null) {
      return context.t(
        'account.notifications.schedule.defaultCustomAllDay',
        variables: {'days': days},
      );
    }
    return context.t(
      'account.notifications.schedule.defaultCustom',
      variables: {
        'days': days,
        'from': _formatTime(context, from),
        'until': _formatTime(context, until),
      },
    );
  }
}

TimeOfDay _parse(String hhmm) {
  final parts = hhmm.split(':');
  return TimeOfDay(
    hour: int.tryParse(parts.first) ?? 9,
    minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
  );
}

String _wire(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

/// `HH:mm` in the reader's clock: 17:00 or 5:00 PM.
String _formatTime(BuildContext context, String hhmm) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      _parse(hhmm),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
