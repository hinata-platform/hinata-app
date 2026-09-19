import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/time_policy_cubit.dart';
import '../../core/models/time_policy_models.dart';
import '../../core/blocs/timer_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart' show GhostButton;
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/glass_switch_chip.dart';
import '../absences/absence_actions.dart';
import 'timer_bar.dart';

/// The extended time module's ways of looking at the same hours.
///
/// Separate routes rather than tabs inside one, so each is a link somebody can
/// send and come back to — and so the shell's back button and title behave the
/// way they do everywhere else. `shell_nav` already treats anything under
/// `/time/` as the module, so all of them keep the module's entry lit.
enum TimeView {
  list('/time', 'time.view.list', LucideIcons.list),
  calendar('/time/calendar', 'time.view.calendar', LucideIcons.calendarDays),
  timesheet('/time/timesheet', 'time.view.timesheet', LucideIcons.table),

  /// Days away — entered, asked for, decided. Here rather than on the account
  /// page, where they used to be kept: planning time off is planning, and the
  /// calendar it is planned in is one tab away.
  absences('/time/absences', 'time.view.absences', LucideIcons.calendarOff),

  /// Handed-in periods. Unlike the other three this one is **conditional**: it
  /// exists only while the operator has switched approvals on, because without
  /// them there is nothing to hand in and nothing to decide. [visibleViews]
  /// is where that is decided, once, for the pill and the phone's menu alike.
  approvals(
    '/time/approvals',
    'time.view.approvals',
    LucideIcons.fileCheck2,
    requiresApprovals: true,
  );

  const TimeView(
    this.route,
    this.labelKey,
    this.icon, {
    this.requiresApprovals = false,
  });

  final String route;
  final String labelKey;
  final IconData icon;

  /// Whether this view only exists while timesheets are submitted.
  final bool requiresApprovals;
}

/// The views this instance actually has.
///
/// One function for both the wide pill and the phone's menu: two filters would
/// be two chances for the phone to offer a page the desktop hides.
///
/// It takes the policy rather than reading it, and that is not ceremony. The pill
/// is a widget and has to *watch* the cubit so it rebuilds when an administrator
/// switches approvals on; the menu is opened from an `onTap` and must only ever
/// *read* it, because listening from outside the tree is an assertion failure in
/// provider. One function that chose for both would be wrong at one of the two
/// call sites.
List<TimeView> visibleViews(TimePolicySnapshot policy) => [
  for (final view in TimeView.values)
    if (policy.approvalsEnabled || !view.requiresApprovals) view,
];

/// The switcher every page of the module wears **on a wide window**.
///
/// A glass pill with one chip per view, the same control the Gantt chart uses.
/// On a phone there is no room for it in the two lines the chrome is allowed,
/// and it is [showTimeViewMenu] under the app bar's title instead.
class TimeViewSwitcher extends StatelessWidget {
  const TimeViewSwitcher({super.key, required this.current});

  final TimeView current;

  @override
  Widget build(BuildContext context) {
    final iconOnly = !context.isExpanded;
    final views = visibleViews(context.watch<TimePolicyCubit>().state);
    // Five words side by side are wider than the head has beside a title and
    // the add button, so past four views only the one on screen is named and
    // the others show their glyph, with the name as a tooltip.
    final named = !iconOnly && views.length <= 4;
    return GlassSwitchBar(
      compact: iconOnly,
      // Wider by a chip for each view past three, so a new one does not
      // squeeze the ones that were already there.
      maxWidth: iconOnly
          ? 170 + 45.0 * (views.length - 3)
          : named
          ? 330 + 115.0 * (views.length - 3)
          : 150 + 45.0 * views.length,
      chips: [
        for (final view in views) ...[
          if (view != views.first) const SizedBox(width: 2),
          GlassSwitchChip(
            label: context.t(view.labelKey),
            icon: view.icon,
            active: view == current,
            iconOnly: iconOnly || (!named && view != current),
            // Going rather than pushing: the three are one destination seen
            // three ways, so stepping back from the calendar belongs outside
            // the module, not on the list you came through. The one you are on
            // is not a button — null, so it does not ripple, take focus, or
            // announce itself as one.
            onTap: view == current ? null : () => context.go(view.route),
          ),
        ],
      ],
    );
  }
}

/// The "+", which is two things.
///
/// There are two ways to add time and the bar has room for one button. Writing
/// down what is already done and starting the clock on what is not are
/// independent — a timer is not a half-filled entry form — but before this only
/// the first had a button here, and on a phone the second was reachable only by
/// knowing that the title opens a menu with the focus view in it. So the button
/// asks which.
///
/// A popover on the button, not a sheet: it is two actions, and the same glass
/// menu the module's title and every row's `⋮` already open. One menu for all
/// three of the module's pages, because it is one button on all three — the
/// same "+" opening the entry sheet here and a menu there is exactly the seam
/// the module spends the rest of its chrome hiding.
///
/// The second row is the timer's one question — "am I working on this right
/// now" — rather than a start. Offering a start while one is running is a row
/// that can only fail, and a running timer is on screen to be stopped either
/// way. [onTimerStopped] fires when this menu is what stopped it, so the page
/// behind can reload; [onNewEntry] is the page's own sheet, which knows the day
/// or the cell the reader is looking at.
///
/// A null [anchor] means the button was not on screen to measure; nothing
/// opens, as with [showTimeViewMenu].
///
/// The absence rows ask for time off, or report sickness, from [absenceFrom] to
/// [absenceTo] — the day or week the page is showing — through the same forms
/// the absences view opens (`absence_actions.dart`).
Future<void> showTimeAddMenu(
  BuildContext context, {
  required Rect? anchor,
  required Future<void> Function() onNewEntry,
  void Function()? onTimerStopped,
  DateTime? absenceFrom,
  DateTime? absenceTo,
}) async {
  if (anchor == null) return;
  final timer = context.read<TimerCubit>().state.timer;
  final stopping = timer != null;
  final managed = absencesManaged(context);
  final chosen = await showGlassMenu<String>(
    context: context,
    anchorRect: anchor,
    width: 230,
    // Two actions, not a choice with a current value: nothing is ticked, the
    // way the row menus do it.
    value: '',
    items: [
      GlassMenuItem(
        value: 'entry',
        label: context.t('time.entry.new'),
        leading: Icon(
          LucideIcons.filePlus2,
          size: 15,
          color: AppColors.inkSoft,
        ),
      ),
      GlassMenuItem(
        value: 'timer',
        label: context.t(
          !stopping
              ? 'time.add.timerStart'
              // A break is never filed, so "stop" would promise an entry that
              // is not coming. The bar says the same thing.
              : timer.isBreak
              ? 'time.focus.endSession'
              : 'time.timer.finish',
        ),
        leading: Icon(
          stopping ? LucideIcons.square : LucideIcons.play,
          size: 15,
          color: AppColors.inkSoft,
        ),
      ),
      ...absenceMenuItems(context, managed: managed),
    ],
  );
  if (chosen == null || !context.mounted) return;
  if (chosen == 'entry') {
    await onNewEntry();
    return;
  }
  if (chosen == 'absence' || chosen == 'sick') {
    await followAbsenceChoice(
      context,
      chosen,
      from: absenceFrom,
      to: absenceTo,
    );
    return;
  }
  if (stopping) {
    await endTimerAndAdvise(context, onStopped: onTimerStopped);
  } else {
    // The plain start, which is the stopwatch — the same one the wide bar's
    // button is. The other two counts are chosen on the bar or in the focus
    // view, where there is room to say what they are.
    await context.read<TimerCubit>().start();
  }
}

/// The absence rows of a "+" or a day's menu: ask for time off — or, without
/// absence management, enter it — and report sickness. A day's menu passes
/// its [day]: sickness is reported when it happens, so a day still ahead
/// offers no report.
List<GlassMenuItem<String>> absenceMenuItems(
  BuildContext context, {
  required bool managed,
  DateTime? day,
}) => [
  GlassMenuItem(
    value: 'absence',
    label: context.t(
      managed ? 'absence.request.ask' : 'availability.timeOff.add',
    ),
    leading: Icon(LucideIcons.calendarOff, size: 15, color: AppColors.inkSoft),
  ),
  if (managed &&
      (day == null ||
          !DateUtils.dateOnly(day).isAfter(DateUtils.dateOnly(DateTime.now()))))
    GlassMenuItem(
      value: 'sick',
      label: context.t('absence.sick.report'),
      leading: Icon(
        LucideIcons.thermometer,
        size: 15,
        color: AppColors.inkSoft,
      ),
    ),
];

/// Runs [chosen] when it is one of [absenceMenuItems]; false for any other
/// value, which the caller then answers itself.
Future<bool> followAbsenceChoice(
  BuildContext context,
  String chosen, {
  DateTime? from,
  DateTime? to,
}) async {
  switch (chosen) {
    case 'absence':
      await askForAbsence(context, from: from, to: to);
      return true;
    case 'sick':
      await reportSickness(context, from: from, to: to);
      return true;
  }
  return false;
}

/// The wide head's add button: a new entry, with the absences beside it.
///
/// One button with two halves rather than two buttons. The head already
/// carries the title and the switch between five views, and a second button
/// was what made it run out of room; the arrow opens the absence rows the
/// phone's "+" has. [absenceFrom] and [absenceTo] are the days the page shows,
/// which the form starts on.
class TimeAddButton extends StatelessWidget {
  const TimeAddButton({
    super.key,
    required this.onNewEntry,
    this.absenceFrom,
    this.absenceTo,
  });

  final VoidCallback onNewEntry;
  final DateTime? absenceFrom;
  final DateTime? absenceTo;

  @override
  Widget build(BuildContext context) {
    ButtonStyle half(BorderRadius radius, EdgeInsets padding) =>
        FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: const Color(0xFF2A2410),
          padding: padding,
          minimumSize: const Size(40, 44),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: radius),
        );
    const radius = Radius.circular(AppTheme.radiusControl);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: onNewEntry,
          style: half(
            const BorderRadius.horizontal(left: radius),
            const EdgeInsets.fromLTRB(16, 13, 14, 13),
          ),
          icon: const Icon(LucideIcons.plus, size: 16),
          label: Text(context.t('time.entry.new')),
        ),
        const SizedBox(width: 1),
        Builder(
          builder: (anchorContext) => Tooltip(
            message: context.t('time.view.absences'),
            child: FilledButton(
              onPressed: () => unawaited(
                showAbsenceMenu(
                  anchorContext,
                  from: absenceFrom,
                  to: absenceTo,
                ),
              ),
              style: half(
                const BorderRadius.horizontal(right: radius),
                const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
              ),
              child: const Icon(LucideIcons.chevronDown, size: 16),
            ),
          ),
        ),
      ],
    );
  }
}

/// The absence rows on their own, for a head without a "new entry" to hang
/// them on — the timesheet's, where time is typed into the cells.
class AbsenceMenuButton extends StatelessWidget {
  const AbsenceMenuButton({super.key});

  @override
  Widget build(BuildContext context) => Builder(
    builder: (anchorContext) => GhostButton(
      icon: LucideIcons.calendarOff,
      label: context.t('time.view.absences'),
      onPressed: () => unawaited(showAbsenceMenu(anchorContext)),
      iconOnly: true,
    ),
  );
}

/// Opens [absenceMenuItems] under the widget [anchorContext] belongs to and
/// follows the choice; [from] and [to] are the days the form starts on.
Future<void> showAbsenceMenu(
  BuildContext anchorContext, {
  DateTime? from,
  DateTime? to,
}) async {
  final box = anchorContext.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return;
  final chosen = await showGlassMenu<String>(
    context: anchorContext,
    anchorRect: box.localToGlobal(Offset.zero) & box.size,
    width: 240,
    value: '',
    items: absenceMenuItems(
      anchorContext,
      managed: absencesManaged(anchorContext),
    ),
  );
  if (chosen == null || !anchorContext.mounted) return;
  await followAbsenceChoice(anchorContext, chosen, from: from, to: to);
}

/// One entry of the module menu: a view to go to, or something the page itself
/// answers.
///
/// The two are one list because they are one menu to the reader — "what am I
/// looking at" and "over what stretch of time" are the same question asked
/// twice — and because the menu has to come back with exactly one answer.
@immutable
class TimeMenuChoice<T extends Object> {
  const TimeMenuChoice.view(this.view) : extra = null, isFocus = false;

  /// A choice only the page knows about — the calendar's week/month, its way
  /// back to today. [extra] is whatever the page put in and gets back.
  const TimeMenuChoice.extra(this.extra) : view = null, isFocus = false;

  /// The focus view. Its own kind rather than a fourth [TimeView], because it
  /// is not a way of looking at the module's pages: it is a full-screen route
  /// outside the shell, and putting it in that enum would light the module's
  /// nav entry and give it a place in the wide window's switcher.
  const TimeMenuChoice.focus() : view = null, extra = null, isFocus = true;

  final TimeView? view;
  final T? extra;
  final bool isFocus;

  @override
  bool operator ==(Object other) =>
      other is TimeMenuChoice<T> &&
      other.view == view &&
      other.extra == extra &&
      other.isFocus == isFocus;

  @override
  int get hashCode => Object.hash(view, extra, isFocus);
}

/// One row a page adds under the three views.
@immutable
class TimeMenuExtra<T extends Object> {
  const TimeMenuExtra({
    required this.value,
    required this.label,
    required this.icon,
    this.selected = false,
    this.first = false,
  });

  final T value;
  final String label;
  final IconData icon;

  /// Whether this row is the one in force — the span the calendar is on.
  ///
  /// Its own flag rather than the menu's selected [value], because the menu
  /// ticks one row and this menu answers two questions: which view you are on,
  /// and how wide it is. The view keeps the tick; a live extra shows the same
  /// glyph in its trailing slot, so both read as chosen.
  final bool selected;

  /// Whether a divider is drawn above this row — set on the first of a group.
  final bool first;
}

/// The module's menu, opened by tapping the app bar's title.
///
/// This is where the phone keeps the switching that a wide window shows as
/// chips. The chrome above the page is allowed two lines — the app bar's own
/// and one docked row — and on the calendar that docked row is the week strip
/// or the weekday header, which leaves nowhere to put three views, two spans
/// and a way back to today. A title that already names what you are looking at
/// is the natural place to ask for something else.
///
/// Navigation between the three views happens here — every page would
/// otherwise write the same three lines — and returns null. [extras] come
/// straight back to the caller, typed, so its `switch` over them can be
/// exhaustive and adding a row cannot silently do nothing.
///
/// A null [anchor] means the title was not on screen to measure; nothing opens.
Future<T?> showTimeViewMenu<T extends Object>(
  BuildContext context, {
  required Rect? anchor,
  required TimeView current,
  List<TimeMenuExtra<T>> extras = const [],
}) async {
  if (anchor == null) return null;
  final chosen = await showGlassMenu<TimeMenuChoice<T>>(
    context: context,
    anchorRect: anchor,
    width: 240,
    value: TimeMenuChoice<T>.view(current),
    items: [
      // The same list the wide pill shows, through the same function: two
      // filters would be two chances for the phone to offer a page the desktop
      // hides.
      for (final view in visibleViews(context.read<TimePolicyCubit>().state))
        GlassMenuItem(
          value: TimeMenuChoice<T>.view(view),
          label: context.t(view.labelKey),
          leading: Icon(view.icon, size: 16, color: AppColors.inkSoft),
        ),
      for (final extra in extras)
        GlassMenuItem(
          value: TimeMenuChoice<T>.extra(extra.value),
          label: extra.label,
          leading: Icon(extra.icon, size: 16, color: AppColors.inkSoft),
          trailing: extra.selected
              ? const Icon(
                  LucideIcons.check,
                  size: 17,
                  color: AppColors.accentStrong,
                )
              : null,
          dividerAbove: extra.first,
        ),
      // Last, and below a divider: it is not one of the three views and not one
      // of the page's own choices. It is a route outside the shell — a way of
      // leaving all of this rather than of looking at it — so it is never
      // ticked, and choosing it goes there rather than answering the caller.
      GlassMenuItem(
        value: TimeMenuChoice<T>.focus(),
        label: context.t('time.focus.title'),
        leading: Icon(
          LucideIcons.crosshair,
          size: 16,
          color: AppColors.inkSoft,
        ),
        dividerAbove: true,
      ),
    ],
  );
  if (chosen == null) return null;
  if (chosen.isFocus) {
    if (context.mounted) context.go('/time/focus');
    return null;
  }
  final view = chosen.view;
  if (view != null) {
    // The one you are already on is not a navigation; going anyway would
    // rebuild the page and throw away the month it is showing.
    if (view != current && context.mounted) context.go(view.route);
    return null;
  }
  return chosen.extra;
}
