import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/time_policy_cubit.dart';
import '../../core/blocs/timer_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/time_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hue_colors.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/glass_switch_chip.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/time_grid/time_grid.dart';
import '../../core/widgets/time_grid/time_grid_model.dart';
import '../../core/widgets/time_grid/time_month_grid.dart';
import '../../core/widgets/time_grid/time_month_layout.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart' show GlassToastKind, showGlassToast;
import 'time_entry_sheet.dart';
import 'time_views.dart';
import 'timer_bar.dart';

/// The module's calendar: a person's own hours, read a day at a time inside a
/// week, or a month at a time for as far as they care to scroll.
///
/// The grid itself is [TimeGrid] in `core/widgets` — shared, because the stages
/// after this one draw absences, holidays and subscribed events on it, and
/// shift planning draws shifts. This page is the part that is about *time
/// entries*: which window to ask for, what to do with a swept span, and where a
/// dropped block ends up.
///
/// **Two spans, not three.** There used to be a day, a week and a month, and
/// the day was the one anybody on a phone actually used — seven columns of
/// hours across a display that narrow is a chart nobody can read. So the week
/// *is* the day now: the strip in the app bar says which week, the canvas below
/// shows one day of it, and a swipe moves to the next one and on into the week
/// after. A wide window has the room for all seven columns and draws them.
///
/// **Which clock the blocks are laid out on.** The device's, through
/// `toLocal()`, and that is the account's: `TimeZoneSync` stamps the account
/// with the device's zone at sign-in and on every resume, and the server files
/// an entry's reporting day in the account's zone. Drawing on any other clock
/// would put an entry near midnight in a different column from the day it is
/// filed under — and would disagree with the list and the timesheet beside it,
/// which read `toLocal()` too.
///
/// A second pipeline through the tz database would resolve to the same answer,
/// so there is not one. The place a real conversion belongs is HIN-44, where an
/// event carries a zone of its own that is nobody's device — and [TimeGrid]
/// already takes wall-clock times, so that stage converts on the way in without
/// touching the grid.
class TimeCalendarScreen extends StatefulWidget {
  const TimeCalendarScreen({super.key});

  @override
  State<TimeCalendarScreen> createState() => _TimeCalendarScreenState();
}

/// How much of the calendar is on screen at once.
enum _Span { week, month }

/// What the module menu can answer with, beyond the three views.
enum _MenuAction { week, month, today }

/// One month of entries, as it came back.
@immutable
class _MonthWindow {
  const _MonthWindow({required this.items, required this.truncated});

  final List<TimeGridItem> items;

  /// Whether the server had to cut this month short of what it covers.
  final bool truncated;
}

class _TimeCalendarScreenState extends State<TimeCalendarScreen> {
  _Span _span = _Span.week;

  /// The day the week span is reading — the one the canvas draws and the strip
  /// marks.
  DateTime _focused = _today();

  /// The month the scroller centres on when [_jump] is bumped. Never moved by a
  /// scroll — which is what keeps the ground still under a finger.
  DateTime _monthAnchor = DateTime(_today().year, _today().month);

  /// Bumped for every deliberate jump. The scroller re-centres on the token,
  /// not on the anchor: pressing "today" while already anchored on this month
  /// hands it a value it has seen, and a scroller that re-centred only on a
  /// change would sit where the finger left it while the title said otherwise.
  int _jump = 0;

  /// The month the scroller has scrolled to, which is what the title says.
  DateTime _visibleMonth = DateTime(_today().year, _today().month);

  /// Everything held, by [monthKey].
  ///
  /// One cache for both spans, because a week is at most two months and asking
  /// for the month it is in costs the same one request as asking for the week —
  /// and buys every neighbouring day the swipe can reach, already drawn. It is
  /// also the only shape a month that scrolls can be held in.
  final Map<int, _MonthWindow> _months = {};

  /// Months asked for and not yet answered, so a scroll that crosses the same
  /// boundary sixty times a second asks once.
  final Set<int> _inFlight = {};

  /// Months the server would not give us.
  ///
  /// Held apart from [_months], because "not here" and "empty" are different
  /// answers and a calendar that draws them the same way tells somebody they
  /// logged nothing in a month it never managed to read.
  final Map<int, String> _failed = {};

  /// Monotonic per month, so a slow answer that arrives after the month was
  /// evicted and asked for again cannot overwrite the newer one.
  final Map<int, int> _loadSeq = {};

  /// The days each held item is filed under, rebuilt whenever [_months] changes
  /// — the lookup the month scroller reads, and the pool the day canvas filters.
  Map<int, List<TimeGridItem>> _byDay = const {};

  /// Bumped whenever [_byDay] changes, so the month scroller knows its memoised
  /// blocks are stale. A lookup function cannot say when its answers changed.
  int _revision = 0;

  /// The layers handed to [TimeGrid], memoised per window.
  ///
  /// Not per build: the grid keeps its packing memo behind the identity of what
  /// it was given, so a fresh list every build threw the memo away and made a
  /// day re-filter and re-pack on every frame of a swipe.
  final Map<int, List<TimeGridLayer>> _layerMemo = {};

  /// The freeze the memo was built against — the lock date *and* its exceptions.
  ///
  /// The memo exists so a build does not re-pack a day, and the wash rides in it —
  /// so a freeze an administrator has just lifted would stay drawn for the life of
  /// the screen unless the memo is told. Compared rather than listened to: the
  /// policy is read in the builder anyway, and one int is cheaper than a
  /// subscription that would rebuild the whole canvas.
  int? _washedAgainst;

  /// The `days` lists handed to [TimeGrid], for the same reason and with more
  /// force: the grid drops *both* its memos when the list is not the identical
  /// object, so a fresh `[day]` on every build defeated [_layerMemo] entirely.
  final Map<int, List<DateTime>> _daysMemo = {};

  /// The pager the week span swipes through. Its page is a day, counted from
  /// [_pageEpoch], so moving on past the end of a week simply moves on.
  late PageController _pager = PageController(initialPage: _pageOf(_focused));

  /// The first window is asked for on the first [didChangeDependencies], not in
  /// [initState]: which day a week starts on comes from [MaterialLocalizations],
  /// and that is not reachable before the element is in the tree.
  bool _started = false;

  /// The brightness the memoised widgets and layer tints were built at.
  ///
  /// The app's neutral tokens are a *global* read at build time, so anything
  /// held across a theme change keeps the colours it was born with — the docked
  /// week strip and the band layer's tint both do. Counting the brightness as
  /// an input is the only thing that makes a widget memo safe here.
  Brightness? _brightness;

  /// Which day a week starts on, held so a rebuild can tell a locale change
  /// from any other dependency.
  int? _firstDayOfWeekIndex;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only what actually moved. `didChangeDependencies` fires for *any*
    // dependency — including every `MediaQuery.size` while a desktop window is
    // being dragged — and clearing the memos there would re-pack the grid and
    // re-publish the chrome on every frame of the drag, which is the state
    // these memos were introduced to end.
    final locale = MaterialLocalizations.of(context);
    final first = locale.firstDayOfWeekIndex;
    if (first != _firstDayOfWeekIndex) {
      _firstDayOfWeekIndex = first;
      // Which day a week starts on decides both the strip and the list handed
      // to the grid.
      _daysMemo.clear();
      _dockKey = null;
    }
    // The dependency is on the theme; the *value* is the global the tokens are
    // read from, which flips at once where `Theme.of` crossfades over two
    // hundred milliseconds.
    Theme.of(context);
    final brightness = AppColors.brightness;
    if (brightness != _brightness) {
      _brightness = brightness;
      // The band layer's tint is `AppColors.inkFaint`, baked in when the layer
      // was built; the docked strip is a held widget.
      _layerMemo.clear();
      _dockKey = null;
    }
    if (_started) return;
    _started = true;
    // The rules, on the same terms as every other screen in the module. The
    // calendar was the one that never asked, and it showed: opened directly —
    // a bookmark, a reload, a notification's deep link — the freeze wash and
    // its padlock were simply absent, because the snapshot the wash reads was
    // still `TimePolicySnapshot.none`. It looked right only after the list or
    // the timesheet had been visited first in the same session.
    unawaited(context.read<TimePolicyCubit>().ensureLoaded());
    unawaited(_ensureAround(_focused));
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// The day page zero stands for. Fixed rather than "today", so a session that
  /// runs past midnight does not renumber the pages under the finger.
  static final DateTime _pageEpoch = DateTime(2000);

  /// Half the pager's range, as pages. A day either side of the epoch reaches
  /// roughly ±13 700 years, which is not a range anybody scrolls out of.
  static const int _pageBase = 5000000;

  /// Through [daysBetween], not through `Duration.inDays`: two local midnights
  /// on either side of a clock change are 23 or 25 hours apart, and truncation
  /// turns that into a day less — which opened the pager on yesterday.
  int _pageOf(DateTime day) => _pageBase + daysBetween(_pageEpoch, day);

  DateTime _dayOfPage(int page) => addDays(_pageEpoch, page - _pageBase);

  // --- what is loaded -----------------------------------------------------------

  /// The months a day needs before it can be drawn: its own, and — for the week
  /// span — the ones its week reaches into.
  List<DateTime> _monthsAround(DateTime day) {
    final week = weekStartFor(context, day);
    return [
      DateTime(week.year, week.month),
      DateTime(day.year, day.month),
      // The last day of the week, which may be in the month after.
      () {
        final last = addDays(week, 6);
        return DateTime(last.year, last.month);
      }(),
      // One month either side, so a swipe out of the week has its hours ready.
      DateTime(day.year, day.month - 1),
      DateTime(day.year, day.month + 1),
    ];
  }

  Future<void> _ensureAround(DateTime day) => _ensure(_monthsAround(day));

  /// Fetches whichever of [months] is not held or already in the air.
  ///
  /// Deduplicated as it goes, not filtered and then fetched: [_monthsAround]
  /// names the same month more than once on purpose — a week is usually all in
  /// one — and a list checked against [_inFlight] before anything is added to
  /// it asks for that month once per mention.
  Future<void> _ensure(List<DateTime> months) async {
    final wanted = <int, DateTime>{};
    for (final month in months) {
      final key = monthKey(month);
      if (_months.containsKey(key) || _inFlight.contains(key)) continue;
      wanted[key] = month;
    }
    if (wanted.isEmpty) return;
    // Only when it shows: [_inFlight] reaches the screen through the spinner,
    // and the spinner is only up while nothing is held. Otherwise this is a
    // whole-page rebuild for a set nobody is reading.
    final show = _months.isEmpty;
    void note() {
      _inFlight.addAll(wanted.keys);
      for (final key in wanted.keys) {
        _failed.remove(key);
      }
    }

    if (show) {
      setState(note);
    } else {
      note();
    }
    // One frame for the lot. Three months arrive together on a boundary
    // crossing, and a `setState` each meant three whole-cache regroups and
    // three page rebuilds during the fling that asked for them.
    final answers = await Future.wait(wanted.values.map(_loadMonth));
    if (!mounted) return;
    setState(() {
      for (final answer in answers) {
        // Retired while the batch was waiting on its slowest member — a save
        // came in and asked again. Checked *here*, not where the answer was
        // captured: `Future.wait` holds a valid answer until the last sibling
        // lands, and a save in that gap would otherwise write the pre-save
        // month back over the fresh one and draw its entries twice.
        //
        // And left alone entirely, rather than filed as a failure: the key
        // belongs to the newer request now, so clearing its in-flight flag or
        // marking it failed would take the newer request's place.
        if (_loadSeq[answer.key] != answer.seq) continue;
        _inFlight.remove(answer.key);
        final window = answer.window;
        if (window != null) {
          _months[answer.key] = window;
          _failed.remove(answer.key);
        } else {
          _failed[answer.key] = answer.errorKey ?? 'errors.unexpected';
        }
      }
      _evict();
      _regroup();
    });
  }

  /// One month's answer, so [_ensure] can apply the lot in a single frame.
  Future<({int key, int seq, _MonthWindow? window, String? errorKey})>
  _loadMonth(DateTime month) async {
    final key = monthKey(month);
    final seq = (_loadSeq[key] ?? 0) + 1;
    _loadSeq[key] = seq;
    final first = DateTime(month.year, month.month);
    final last = DateTime(
      month.year,
      month.month,
      DateUtils.getDaysInMonth(month.year, month.month),
    );
    try {
      final window = await context.read<TimeRepository>().calendar(first, last);
      return (
        key: key,
        seq: seq,
        window: _MonthWindow(
          items: _itemsOf(window.entries),
          truncated: window.truncated,
        ),
        errorKey: null,
      );
    } on ApiFailure catch (failure) {
      return (key: key, seq: seq, window: null, errorKey: failure.message);
      // Everything else too, deliberately. A decode error that escaped here
      // would leave the month wedged in [_inFlight] for the life of the page —
      // never drawn, never asked for again, and indistinguishable from a month
      // in which nobody logged anything.
    } catch (_) {
      return (key: key, seq: seq, window: null, errorKey: 'errors.unexpected');
    }
  }

  /// Most months held at once.
  ///
  /// A month that scrolls has no end, and every month kept is a list of entries
  /// kept. Fifteen is a year either side of wherever the reader stopped, which
  /// is further than a scroll goes before it turns around.
  static const int _keepMonths = 15;

  void _evict() {
    if (_months.length <= _keepMonths) return;
    final here = monthKey(_span == _Span.month ? _visibleMonth : _focused);
    final byDistance = _months.keys.toList()
      ..sort((a, b) => _monthsApart(a, here).compareTo(_monthsApart(b, here)));
    for (final key in byDistance.skip(_keepMonths)) {
      _months.remove(key);
      _loadSeq.remove(key);
    }
  }

  /// Distance between two [monthKey]s in months — not in the raw difference,
  /// which jumps by 88 at every new year.
  static int _monthsApart(int a, int b) =>
      ((a ~/ 100) * 12 + a % 100 - ((b ~/ 100) * 12 + b % 100)).abs();

  /// Most one-day lists held before the memo is thrown away.
  ///
  /// They are three words each and never go stale, so this is not about
  /// correctness — it is so that a session spent swiping through a year does
  /// not quietly keep a list per day it ever visited.
  static const int _keepDayLists = 96;

  void _regroup() {
    if (_daysMemo.length > _keepDayLists) _daysMemo.clear();
    _byDay = groupItemsByDay([
      for (final window in _months.values) ...window.items,
    ]);
    _layerMemo.clear();
    _revision++;
  }

  /// Everything held is dropped after a save, and only what is on screen is
  /// asked for again.
  ///
  /// Dropped rather than patched, because an edit can move an entry into a
  /// month this page is not looking at — the reporting day is a field of its
  /// own — and a cache that kept the old month would show the entry twice.
  /// Re-asked for narrowly, because the cache holds up to [_keepMonths]: a save
  /// is not a reason to fetch a year, and the months a finger scrolls back to
  /// are fetched again when it gets there.
  Future<void> _reload() async {
    setState(() {
      // The scroller is unmounted for the frame the cache is empty, and comes
      // back centred on its anchor — so the anchor has to be the month the
      // reader was actually looking at, or a save throws them back to wherever
      // they last jumped from, onto months this very method did not fetch.
      if (_span == _Span.month) {
        _monthAnchor = _visibleMonth;
        _jump++;
      }
      // Every request in the air was asked before the save and would answer
      // with what the save changed. Bumping the sequence retires them: without
      // it, one landing after this could write a pre-save month back into the
      // cache, and the same entry would then be drawn on two days.
      for (final key in _inFlight) {
        _loadSeq[key] = (_loadSeq[key] ?? 0) + 1;
      }
      _months.clear();
      _inFlight.clear();
      _failed.clear();
      _regroup();
    });
    // Around what is on screen, which in a month that has been scrolled is not
    // the month it was anchored on.
    await _ensure(
      _span == _Span.month
          ? [
              DateTime(_visibleMonth.year, _visibleMonth.month - 1),
              _visibleMonth,
              DateTime(_visibleMonth.year, _visibleMonth.month + 1),
            ]
          : _monthsAround(_focused),
    );
  }

  // --- navigation ----------------------------------------------------------------

  void _focusDay(DateTime day) {
    final at = DateTime(day.year, day.month, day.day);
    setState(() {
      _focused = at;
      _monthAnchor = DateTime(at.year, at.month);
      _visibleMonth = _monthAnchor;
      _jump++;
    });
    final page = _pageOf(at);
    if (_pager.hasClients) {
      if (_pager.page?.round() != page) _pager.jumpToPage(page);
    } else {
      // Not attached — the month span is on screen. A controller cannot be
      // told where to open after the fact, so it is replaced.
      _pager.dispose();
      _pager = PageController(initialPage: page);
    }
    unawaited(_ensureAround(at));
  }

  /// The day a tap in the month opens.
  void _openDay(DateTime day) {
    setState(() => _span = _Span.week);
    _focusDay(day);
  }

  void _setSpan(_Span span) {
    if (span == _span) return;
    if (span == _Span.month) {
      setState(() {
        _span = span;
        _monthAnchor = DateTime(_focused.year, _focused.month);
        _visibleMonth = _monthAnchor;
        // Bumped even though the scroller is a fresh `State` here: the rule is
        // "the anchor moved, so say so", and the one place that quietly broke
        // it would break for real the day both spans are kept alive at once.
        _jump++;
      });
      unawaited(_ensure([_monthAnchor]));
      return;
    }
    setState(() => _span = span);
    // Through the one write path. A `PageController` keeps its offset while it
    // is detached and opens on its `initialPage` when the pager is rebuilt, and
    // `onPageChanged` does not fire on that — so coming back to the week span
    // would show one day while the strip, the title and the fetch all named
    // another, with nothing to reconcile them.
    _focusDay(_focused);
  }

  void _goToday() {
    final today = _today();
    if (_span == _Span.month) {
      setState(() {
        _monthAnchor = DateTime(today.year, today.month);
        _visibleMonth = _monthAnchor;
        _focused = today;
        _jump++;
      });
      unawaited(_ensure([_monthAnchor]));
      return;
    }
    _focusDay(today);
  }

  /// The window's arrows on a wide screen: a week, or a month.
  void _move(int steps) {
    if (_span == _Span.month) {
      setState(() {
        // From the month on screen, not from the one it was anchored on: the
        // month scrolls, so after a scroll those are different months and
        // "next" would step forward from wherever the reader last jumped to.
        //
        // Through the constructor, which normalises: the 31st plus one month is
        // the 1st of the month after next everywhere else, and stepping through
        // a year from the 31st would skip February entirely.
        _monthAnchor = DateTime(
          _visibleMonth.year,
          _visibleMonth.month + steps,
        );
        _visibleMonth = _monthAnchor;
        _jump++;
      });
      unawaited(_ensure([_monthAnchor]));
      return;
    }
    _focusDay(addDays(_focused, steps * 7));
  }

  bool get _isCurrent {
    final today = _today();
    if (_span == _Span.month) {
      return _visibleMonth.year == today.year &&
          _visibleMonth.month == today.month;
    }
    return _weekDays.any((day) => DateUtils.isSameDay(day, today));
  }

  void _openModuleMenu(Rect? anchor) => unawaited(_moduleMenu(anchor));

  Future<void> _moduleMenu(Rect? anchor) async {
    final chosen = await showTimeViewMenu<_MenuAction>(
      context,
      anchor: anchor,
      current: TimeView.calendar,
      extras: [
        TimeMenuExtra(
          value: _MenuAction.week,
          label: context.t('time.calendar.week'),
          icon: LucideIcons.calendarRange,
          selected: _span == _Span.week,
          first: true,
        ),
        TimeMenuExtra(
          value: _MenuAction.month,
          label: context.t('time.calendar.month'),
          icon: LucideIcons.calendarDays,
          selected: _span == _Span.month,
        ),
        TimeMenuExtra(
          value: _MenuAction.today,
          label: context.t('common.today'),
          icon: LucideIcons.locateFixed,
          first: true,
        ),
      ],
    );
    if (chosen == null || !mounted) return;
    // Exhaustive, so a row added to the menu cannot compile into doing nothing.
    switch (chosen) {
      case _MenuAction.week:
        _setSpan(_Span.week);
      case _MenuAction.month:
        _setSpan(_Span.month);
      case _MenuAction.today:
        _goToday();
    }
  }

  // --- what the grid reports back ---------------------------------------------

  Future<void> _newEntry() => _createFrom(_defaultSpan());

  /// A new entry on a day the reader pointed at in the month.
  ///
  /// Given the hour the page would have offered anyway, because a month cell
  /// says which day and nothing about when — and an entry that opens at
  /// midnight is one the person has to fix before they can save it.
  Future<void> _newEntryOn(DateTime day) {
    final fallback = _defaultSpan();
    DateTime on(DateTime at) =>
        DateTime(day.year, day.month, day.day, at.hour, at.minute);
    return _createFrom((start: on(fallback.start), end: on(fallback.end)));
  }

  Future<void> _createFrom(TimeGridSpan span) async {
    final saved = await showTimeEntrySheet(context, span: span);
    if (saved == null || !mounted) return;
    unawaited(_reload());
  }

  Future<void> _openEntry(TimeGridItem item) async {
    final entry = item.data;
    if (entry is! WorkItem) return;
    final saved = await showTimeEntrySheet(context, entry: entry);
    if (saved == null || !mounted) return;
    unawaited(_reload());
  }

  /// A block dropped somewhere else.
  ///
  /// Optimistic: the grid draws it in its new place before the server has
  /// agreed, and a refusal puts the previous entries straight back — no reload,
  /// because the answer is already here and a round trip would only leave the
  /// block sitting wrong for longer. The reload is on the way *out* of a
  /// successful save, where the server may have adjusted something.
  Future<void> _moveEntry(TimeGridItem item, TimeGridSpan span) async {
    final entry = item.data;
    if (entry is! WorkItem) return;
    final day = DateTime(span.start.year, span.start.month, span.start.day);
    // The preview carries the day it is being moved *to* and forgets the logged
    // minutes, because the drop re-files the entry and re-measures it. Kept, it
    // would sit filed under the day it came from — where the canvas would then
    // fail to draw it at all — with the total it used to have.
    _patch(
      item.id,
      (each) =>
          each.movedTo(span.start, span.end, day: day, keepMinutes: false),
    );
    try {
      await context.read<TimeRepository>().update(
        entry.id,
        TimeEntryDraft(
          startedAt: span.start,
          endedAt: span.end,
          date: day,
          description: entry.description,
          activityType: entry.activityType,
        ),
      );
      if (mounted) unawaited(_reload());
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      // Only this entry back, not the whole cache. A snapshot restored wholesale
      // would drop the months that arrived while the request was in the air —
      // and nothing asks for those again until the reader scrolls out and back.
      _patch(item.id, (_) => item);
      showGlassToast(
        context,
        context.t(failure.message),
        kind: GlassToastKind.error,
      );
    }
  }

  /// Replaces the item with [id] wherever it is held.
  void _patch(String id, TimeGridItem Function(TimeGridItem) change) {
    setState(() {
      for (final key in _months.keys.toList()) {
        final window = _months[key]!;
        if (!window.items.any((each) => each.id == id)) continue;
        _months[key] = _MonthWindow(
          items: [
            for (final each in window.items)
              if (each.id == id) change(each) else each,
          ],
          truncated: window.truncated,
        );
      }
      _regroup();
    });
  }

  // --- build --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    // The freeze rides in the layer memo, so a freeze that has moved has to drop
    // it — otherwise a day an administrator just reopened stays washed for the
    // life of the screen. Both halves, and the second is the one that caught this:
    // reopening a span changes only `lockExceptions`, so comparing the lock date
    // alone left the padlock painted over a day that was now open.
    final policy = context.watch<TimePolicyCubit>().state;
    final washedBy = Object.hash(
      policy.lockBefore,
      Object.hashAll(policy.lockExceptions),
    );
    if (washedBy != _washedAgainst) {
      _washedAgainst = washedBy;
      _layerMemo.clear();
    }
    // Once. Both readers below walk the same months, and in the week span that
    // walk resolves the week twice over.
    final onScreen = _monthsOnScreen;
    final truncated = onScreen.any(
      (month) => _months[monthKey(month)]?.truncated ?? false,
    );
    return PageChrome(
      fullWidth: true,
      title: _title(),
      onTitleTap: compact ? _openModuleMenu : null,
      // On the leading edge, because the title is a month name that changes as
      // the calendar scrolls and a centred one on a phone reads "Septem…".
      titleLeading: true,
      // Compact only, and that is not a style choice: the module's pages are
      // nav destinations, so a wide window builds no sub-page bar and would
      // drop these on the floor. A wide window has room for both ways of
      // adding time and offers them separately — the entry button in the
      // page's own head, the timer on the bar above it. One slot cannot, so
      // the phone's button asks which.
      actions: compact
          ? [
              PageAction(
                icon: LucideIcons.plus,
                label: context.t('time.add.title'),
                primary: true,
                // The module's one "+", shared by all three of its pages: an
                // entry on the day this page would have offered anyway, or the
                // timer. See [showTimeAddMenu].
                onTap: (anchor) => unawaited(
                  showTimeAddMenu(
                    context,
                    anchor: anchor,
                    onNewEntry: _newEntry,
                    onTimerStopped: _reload,
                  ),
                ),
              ),
            ]
          : const [],
      bottom: compact ? _dockedNavigation() : null,
      bottomHeight: compact ? _dockHeight : 0,
      child: BlocListener<TimerCubit, TimerState>(
        listenWhen: (previous, current) =>
            previous.isRunning && !current.isRunning,
        listener: (context, state) => unawaited(_reload()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact) ..._wideHead(),
            if (truncated)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  context.pageGutter,
                  compact ? context.topGutter + 8 : 0,
                  context.pageGutter,
                  8,
                ),
                child: const _TruncatedNotice(),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  // The month keeps a smaller inset than the rest of the app:
                  // its cells are a grid, and a full gutter down both sides of
                  // seven columns costs most of a column on a phone — but at
                  // nothing the 1st and the 7th sit against the display edge.
                  // The weekday letters docked above take the same one.
                  _span == _Span.month ? kMonthGutter : context.pageGutter,
                  // On a phone nothing sits above the canvas in the column —
                  // the week strip is docked into the glass bar — so the body
                  // spends the bar's height itself. (The notice above spends it
                  // when it is there.)
                  compact && !truncated ? context.topGutter : 0,
                  _span == _Span.month ? kMonthGutter : context.pageGutter,
                  context.bottomGutter + 8,
                ),
                child: _body(onScreen),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The head a wide window wears: the module's name, its three views, the
  /// timer and the window's own controls. A phone has all of this in the app
  /// bar's two lines instead.
  List<Widget> _wideHead() => [
    Padding(
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        18 + context.topGutter,
        context.pageGutter,
        12,
      ),
      child: PageHead(
        title: context.t('nav.time'),
        actions: [
          const TimeViewSwitcher(current: TimeView.calendar),
          const SizedBox(width: 8),
          PrimaryButton(
            icon: LucideIcons.plus,
            label: context.t('time.entry.new'),
            onPressed: _newEntry,
            collapseToIcon: true,
          ),
        ],
      ),
    ),
    Padding(
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        0,
        context.pageGutter,
        10,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: AppColors.hairline),
        ),
        child: TimerBar(onStopped: _reload),
      ),
    ),
    Padding(
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        0,
        context.pageGutter,
        10,
      ),
      // The window's controls on the leading edge, the span switcher hard
      // against the trailing one — the row reads as "which window" on the left
      // and "how wide" on the right, instead of one long clump with empty space
      // after it.
      child: Row(
        children: [
          _RoundButton(
            icon: backChevron(context),
            tooltip: context.t('time.calendar.previous'),
            onTap: () => _move(-1),
          ),
          const SizedBox(width: 6),
          _RoundButton(
            icon: forwardChevron(context),
            tooltip: context.t('time.calendar.next'),
            onTap: () => _move(1),
          ),
          const SizedBox(width: 10),
          // The window's name and the way back to today take the whole middle,
          // which is what puts the switcher hard against the trailing edge. A
          // `Flexible` beside a `Spacer` splits the slack between the two, and
          // the half the label does not use is left as a gap before the
          // switcher rather than after it.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    _rangeLabel(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                if (!_isCurrent) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _goToday,
                    icon: const Icon(LucideIcons.locateFixed, size: 15),
                    label: Text(context.t('common.today')),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          _spanSwitcher(),
        ],
      ),
    ),
  ];

  /// What "new entry" starts out as: nine in the morning on the day the reader
  /// is looking at, or — in a month — on today when the month contains it and
  /// its first otherwise. (Nobody reaching for the button on the 20th means the
  /// 1st, unless the 1st is all the month they are looking at has.)
  TimeGridSpan _defaultSpan() {
    final today = _today();
    final DateTime day;
    if (_span == _Span.week) {
      day = _focused;
    } else if (_visibleMonth.year == today.year &&
        _visibleMonth.month == today.month) {
      day = today;
    } else {
      day = DateTime(_visibleMonth.year, _visibleMonth.month);
    }
    final start = DateTime(day.year, day.month, day.day, 9);
    return (start: start, end: start.add(const Duration(hours: 1)));
  }

  /// The months whose days are drawn right now.
  List<DateTime> get _monthsOnScreen {
    if (_span == _Span.month) return [_visibleMonth];
    final week = weekStartFor(context, _focused);
    final last = addDays(week, 6);
    return [
      DateTime(week.year, week.month),
      DateTime(_focused.year, _focused.month),
      DateTime(last.year, last.month),
    ];
  }

  /// What the failure on screen is, if any — the month the reader is looking at
  /// came back as an error rather than as a month with nothing in it.
  String? _errorOn(List<DateTime> months) {
    for (final month in months) {
      final failure = _failed[monthKey(month)];
      if (failure != null) return failure;
    }
    return null;
  }

  Widget _body(List<DateTime> onScreen) {
    if (_months.isEmpty && _inFlight.isNotEmpty) {
      return const Center(child: HiveLoader(size: 44));
    }
    final failure = _errorOn(onScreen);
    // Only when there is nothing else to look at. A month that failed beside
    // three that arrived is a gap the month scroller marks in place; replacing
    // the whole calendar with an error would throw away what did come back.
    if (failure != null && _months.isEmpty) {
      return HiveEmptyState(
        title: context.t('time.error.title'),
        message: context.t(failure),
        action: FilledButton.icon(
          onPressed: () => _retry(onScreen),
          icon: const Icon(LucideIcons.refreshCw, size: 15),
          label: Text(context.t('common.retry')),
        ),
      );
    }
    if (_span == _Span.month) return _month();
    return context.isCompact ? _dayPager() : _weekCanvas();
  }

  void _retry(List<DateTime> onScreen) {
    setState(() {
      for (final month in onScreen) {
        _failed.remove(monthKey(month));
      }
    });
    unawaited(
      _ensure(_span == _Span.month ? onScreen : _monthsAround(_focused)),
    );
  }

  /// Asks for one month again — the button on a month that could not be read.
  void _retryMonth(DateTime month) => _retry([month]);

  Widget _month() {
    TimeMonthScroller scroller(bool showTotals) => TimeMonthScroller(
      anchor: _monthAnchor,
      jump: _jump,
      revision: _revision,
      itemsForDay: _itemsForDay,
      failureFor: (key) => _failed[key],
      onNeedMonths: _need,
      onMonthChanged: _onMonthScrolled,
      showTotals: showTotals,
      // No drag-create and no drag-move: a month cell is a day, and dropping a
      // block into one would have to invent the hours nobody chose. Tapping a
      // day opens it instead, which is where those hours exist.
      onTapDay: _openDay,
      onNewOnDay: _newEntryOn,
      onTap: _openEntry,
      onRetryMonth: _retryMonth,
    );
    // The width decides only whether a cell has room to write its total beside
    // its number, and on a phone the month runs edge to edge — so there the
    // window's own width is the answer and no `LayoutBuilder` is needed. A wide
    // window has a rail beside it and does need to measure.
    if (context.isCompact) {
      // The weekday letters are docked into the app bar's glass, above the
      // month's own title — the two lines the chrome is allowed.
      return scroller(
        MediaQuery.sizeOf(context).width / 7 >= kMonthTotalsMinColumn,
      );
    }
    // A wide window has no docked band — the shell renders one only on a phone
    // — so the letters go at the top of the body, where they still stand over
    // the columns they name and still do not scroll with them.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: MonthWeekdayHeader(),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) =>
                scroller(constraints.maxWidth / 7 >= kMonthTotalsMinColumn),
          ),
        ),
      ],
    );
  }

  void _need(List<DateTime> months) => unawaited(_ensure(months));

  void _onMonthScrolled(DateTime month) {
    if (monthKey(month) == monthKey(_visibleMonth)) return;
    setState(() => _visibleMonth = month);
  }

  /// A week, read one day at a time — the phone's calendar.
  ///
  /// A pager over days rather than over weeks, because that is what the swipe
  /// is asked to do: the day after Sunday is Monday, and it being in the next
  /// week is the strip's problem, not the reader's.
  Widget _dayPager() => PageView.builder(
    controller: _pager,
    onPageChanged: (page) {
      final day = _dayOfPage(page);
      setState(() {
        _focused = day;
        _monthAnchor = DateTime(day.year, day.month);
        _visibleMonth = _monthAnchor;
      });
      unawaited(_ensureAround(day));
    },
    itemBuilder: (context, page) {
      final day = _dayOfPage(page);
      return _Day(
        day: day,
        days: _daysFor(day),
        layers: _layersFor(day),
        onCreate: _createFrom,
        onMoved: _moveEntry,
        onTap: _openEntry,
      );
    },
  );

  Widget _weekCanvas() => TimeGrid(
    days: _weekDays,
    layers: _layersForWeek(_weekDays),
    step: const Duration(minutes: 15),
    onCreate: _createFrom,
    onMoved: _moveEntry,
    onTap: _openEntry,
  );

  // --- the entries, as the grid wants them ---------------------------------

  List<TimeGridItem> _itemsForDay(int key) => _byDay[key] ?? const [];

  /// The one-day list handed to [TimeGrid], remembered so the identical object
  /// comes back on the next build.
  ///
  /// [TimeGrid] keeps its packing memo behind `identical(old.days, …)` and
  /// drops it — along with the band-row counts — when the list is a new object.
  /// A fresh `[day]` in `build` therefore made every rebuild re-filter and
  /// re-pack the day, which is exactly what [_layerMemo] exists to prevent.
  List<DateTime> _daysFor(DateTime day) => _daysMemo[dayKey(day)] ??= [day];

  /// The week on screen, cached until the week itself changes.
  List<DateTime> get _weekDays {
    final start = weekStartFor(context, _focused);
    final key = dayKey(start);
    return _daysMemo[-key] ??= [for (var i = 0; i < 7; i++) addDays(start, i)];
  }

  /// The pool a single day's canvas is drawn from — the day, and the days
  /// either side of it.
  ///
  /// The memo is keyed on one day but its contents depend on its neighbours,
  /// which is only sound because [_regroup] clears the whole memo whenever
  /// [_byDay] changes at all. Anything that later invalidates it per day has to
  /// invalidate the neighbours with it.
  ///
  /// Not just the day's own entries, and the difference is the whole of two
  /// bugs. [_byDay] files by the *reporting day*, but the hour canvas places by
  /// the *span*: an entry filed on the 10th whose hours were edited onto the
  /// 20th is in the 10th's pool and belongs on the 20th's canvas, so handed
  /// only its own day it is drawn nowhere at all. And an entry that runs past
  /// midnight is filed on the day it began, so the following day never saw the
  /// tail the wide week canvas draws — the same entry, two answers, depending
  /// on the width of the window.
  ///
  /// A day either side is enough: the grid clips what it is given to the column
  /// it draws, and an entry can be dragged a day off its filed one but not a
  /// week. An entry moved further than that is drawn in the month, in the list
  /// and in the timesheet, all of which file by the day the record names.
  List<TimeGridLayer> _layersFor(DateTime day) => _layerMemo[dayKey(day)] ??= [
    ..._split([
      ..._itemsForDay(dayKey(addDays(day, -1))),
      ..._itemsForDay(dayKey(day)),
      ..._itemsForDay(dayKey(addDays(day, 1))),
    ]),
    ..._frozenWash([addDays(day, -1), day, addDays(day, 1)]),
  ];

  List<TimeGridLayer> _layersForWeek(List<DateTime> days) {
    // Keyed negatively on the first day, so a week and a day cannot collide in
    // the one memo.
    final key = -dayKey(days.first);
    final window = [addDays(days.first, -1), ...days, addDays(days.last, 1)];
    return _layerMemo[key] ??= [
      ..._split([for (final day in window) ..._itemsForDay(dayKey(day))]),
      ..._frozenWash(window),
    ];
  }

  /// The days in [window] nothing can be written to, as one background wash.
  ///
  /// Before this the calendar said **nothing** about a frozen day: you found out
  /// by opening an entry and being refused, which for a closed month is the worst
  /// possible moment to learn it. The wash is deliberately not the weekend's —
  /// that one already means "quiet", and a second flat rect in the same tone
  /// would read as "this is also a weekend". So it has its own weight, measured
  /// per theme in [AppColors.closed], and the day's heading carries a padlock
  /// beside its date, which is the part that actually says *what* it means.
  ///
  /// Only the lock date, and that is not a gap: a period somebody has handed in
  /// freezes their entries for **one project**, while a column is a whole day
  /// across every project. A wash over it would claim more than is true, and a
  /// wrong statement about a freeze is worse than none. Those entries carry the
  /// lock on themselves — see the chip in the list and the notice in the sheet.
  List<TimeGridLayer> _frozenWash(List<DateTime> window) {
    final policy = context.read<TimePolicyCubit>().state;
    if (policy.lockBefore == null) return const [];
    final frozen = [
      for (final day in window)
        if (policy.isLocked(day))
          TimeGridItem(
            id: 'frozen-${dayKey(day)}',
            start: DateTime(day.year, day.month, day.day),
            end: DateTime(day.year, day.month, day.day, 23, 59),
            title: '',
            movable: false,
          ),
    ];
    if (frozen.isEmpty) return const [];
    return [
      TimeGridLayer(
        id: 'frozen',
        placement: TimeGridPlacement.background,
        items: frozen,
        // Its own token, not the weekend's: the two have to be told apart at a
        // glance, and in the dark theme that cannot be done by darkening at all.
        // The numbers are in [AppColors.closed].
        tint: AppColors.closed,
        glyph: LucideIcons.lock,
      ),
    ];
  }

  /// Two layers over the same entries: the ones that happened between two
  /// times, and the ones that are only a duration on a day.
  ///
  /// The second lot cannot be drawn on the hour canvas — a plain duration
  /// occupies no hours — but leaving them out would make a day somebody logged
  /// look empty. They ride in the band under the headings instead, which is
  /// also where absences and holidays go when stage 10 lands.
  List<TimeGridLayer> _split(List<TimeGridItem> items) {
    final timed = <TimeGridItem>[];
    final untimed = <TimeGridItem>[];
    for (final item in items) {
      (item.movable ? timed : untimed).add(item);
    }
    return [
      if (untimed.isNotEmpty)
        TimeGridLayer(
          id: 'untimed',
          label: context.t('time.calendar.untimed'),
          placement: TimeGridPlacement.band,
          items: untimed,
          tint: AppColors.inkFaint,
        ),
      TimeGridLayer(id: 'entries', items: timed, tint: AppColors.accent),
    ];
  }

  List<TimeGridItem> _itemsOf(List<WorkItem> entries) {
    // Hoisted out of the loop: one lookup, not one per entry.
    final noDescription = context.t('time.entry.noDescription');
    return [for (final entry in entries) ?_itemFor(entry, noDescription)];
  }

  TimeGridItem? _itemFor(WorkItem entry, String noDescription) {
    final title = entry.description?.trim().isNotEmpty == true
        ? entry.description!.trim()
        : noDescription;
    // `toLocal()`, and deliberately so — see the zone note on this class.
    final start = entry.startedAt?.toLocal();
    final end = entry.endedAt?.toLocal();
    if (start != null && end != null) {
      return TimeGridItem(
        id: entry.id,
        start: start,
        end: end,
        title: title,
        subtitle: entry.activityType,
        movable: true,
        tint: _tintFor(entry),
        // The logged minutes and the filed day, not the span and not the day
        // the hours fall on — the entry's own numbers are the ones the list and
        // the timesheet add up, and the day is the field the server selected
        // this window by. A total computed from the drawing instead of from the
        // record is a second answer to a question that must only have one.
        minutes: entry.durationMinutes,
        day: entry.date,
        data: entry,
      );
    }
    final day = entry.date;
    if (day == null) return null;
    final at = DateTime(day.year, day.month, day.day);
    return TimeGridItem(
      id: entry.id,
      start: at,
      end: at,
      title: title,
      // Not movable: there are no hours to move it to, and dragging one onto
      // the canvas would silently invent a start time nobody recorded. It is
      // also what [_split] reads to tell the two layers apart.
      movable: false,
      tint: _tintFor(entry),
      minutes: entry.durationMinutes,
      day: day,
      data: entry,
    );
  }

  /// A colour per project, so a week reads as projects rather than as a wall of
  /// amber. Unfiled entries keep the accent.
  Color _tintFor(WorkItem entry) {
    final projectId = entry.projectId;
    if (projectId == null) return AppColors.accent;
    // Remembered per project: `hueColor` is an OKLCH conversion, and a week of
    // one project's entries asked for the same answer once per entry.
    return _tints[projectId] ??= hueColor(projectId.hashCode.abs() % 360);
  }

  final Map<String, Color> _tints = {};

  // --- the controls -------------------------------------------------------------

  /// What the app bar is called: the month, written out.
  ///
  /// The same answer in both spans, and the same one the reference calendar
  /// gives. In a month it is what you are scrolling through and it changes
  /// under the finger; in a week it is where the day you are reading lives, and
  /// the day itself is written out in full under the strip.
  ///
  /// The month alone, because the bar centres its title in what the leading and
  /// trailing items leave it — about a hundred points on a phone — and
  /// "September 2026" came out as "Septem…". The year is only written when it
  /// is not the current one, which is the only time it tells the reader
  /// anything.
  String _title() {
    final month = _span == _Span.month ? _visibleMonth : _focused;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final name = DateFormat.MMMM(locale).format(month);
    return month.year == DateTime.now().year ? name : '$name ${month.year}';
  }

  /// The window a wide screen names beside its arrows.
  String _rangeLabel() {
    final localizations = MaterialLocalizations.of(context);
    if (_span == _Span.month) {
      return localizations.formatMonthYear(_visibleMonth);
    }
    final days = _weekDays;
    return '${localizations.formatShortDate(days.first)} – '
        '${localizations.formatShortDate(days.last)}';
  }

  /// Week · month, for a window with room to show both at once.
  Widget _spanSwitcher() {
    const spans = <({_Span span, String labelKey, IconData icon})>[
      (
        span: _Span.week,
        labelKey: 'time.calendar.week',
        icon: LucideIcons.calendarRange,
      ),
      (
        span: _Span.month,
        labelKey: 'time.calendar.month',
        icon: LucideIcons.calendarDays,
      ),
    ];
    return GlassSwitchBar(
      maxWidth: 240,
      chips: [
        for (final each in spans) ...[
          if (each != spans.first) const SizedBox(width: 2),
          GlassSwitchChip(
            label: context.t(each.labelKey),
            icon: each.icon,
            active: _span == each.span,
            onTap: each.span == _span ? null : () => _setSpan(each.span),
          ),
        ],
      ],
    );
  }

  /// Height of the one line the phone docks into the app bar's glass.
  ///
  /// One, and only one: the chrome above any page of this app is the bar's own
  /// title row plus at most a single docked row, and on a calendar that row is
  /// the navigation — the week you are in, or the days of the week the month
  /// below is laid out in. Everything else the page used to keep up here is in
  /// the menu under the title.
  ///
  /// Deliberately not [kGlassDockRow]: that constant is the height a row of
  /// 36-point glass pills needs, and neither of these rows is pills. Forcing it
  /// would crop the strip's discs and leave the weekday letters swimming.
  double get _dockHeight => _span == _Span.month ? _kWeekdayRow : _kWeekStrip;

  /// The docked row, held rather than rebuilt.
  ///
  /// The shell compares it by identity — a widget has no `==` — so a new one on
  /// every build re-publishes the page's chrome and rebuilds the whole glass
  /// bar with it, seven strip days and all. It depends on the span, the week
  /// and the day in focus, so it is thrown away exactly when one of those
  /// moves.
  Widget? _dock;
  Object? _dockKey;

  Widget _dockedNavigation() {
    final today = _today();
    final key = Object.hash(
      _span,
      dayKey(_focused),
      dayKey(today),
      AppColors.brightness,
    );
    if (_dockKey == key) return _dock!;
    _dockKey = key;
    // The month's header brings its own inset — the letters have to stand over
    // the columns below them, and those are laid out to [kMonthGutter], not to
    // the page gutter the rest of the app uses.
    return _dock = _span == _Span.month
        ? const Align(
            alignment: Alignment.bottomCenter,
            child: MonthWeekdayHeader(height: _kWeekdayRow - 4),
          )
        : Padding(
            padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
            child: _WeekStrip(
              days: _weekDays,
              focused: _focused,
              today: today,
              onTap: _focusDay,
            ),
          );
  }
}

/// Height of the week strip docked under the title in the week span.
const double _kWeekStrip = 52;

/// Height of the weekday letters docked under the title in the month span.
const double _kWeekdayRow = 26;

/// One day of a week: the date written out, and the hours under it.
///
/// A widget of its own so the pager's neighbours are const-comparable and only
/// the page that changed rebuilds.
class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.days,
    required this.layers,
    required this.onCreate,
    required this.onMoved,
    required this.onTap,
  });

  final DateTime day;

  /// `[day]`, held by the page rather than built here — [TimeGrid] drops its
  /// packing memo when the list is not the identical object it was given last.
  final List<DateTime> days;

  final List<TimeGridLayer> layers;
  final void Function(TimeGridSpan span) onCreate;
  final void Function(TimeGridItem item, TimeGridSpan span) onMoved;
  final void Function(TimeGridItem item) onTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          MaterialLocalizations.of(context).formatFullDate(day),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ),
      Expanded(
        child: TimeGrid(
          days: days,
          layers: layers,
          step: const Duration(minutes: 15),
          // The strip above says which day this is and the line above that
          // writes it out; a heading over the single column would be the third
          // time in four centimetres.
          showHeadings: false,
          // One column, however narrow the phone: a minimum here would make the
          // canvas wider than the page and hand the swipe to a scroller.
          minColumnWidth: 0,
          onCreate: onCreate,
          onMoved: onMoved,
          onTap: onTap,
        ),
      ),
    ],
  );
}

/// The seven days of the week the reader is in, with the one on screen marked.
///
/// The calendar's whole navigation on a phone: tapping a day goes to it, and
/// swiping the canvas below moves through them and on into the weeks either
/// side, which redraws this strip around the new day.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.days,
    required this.focused,
    required this.today,
    required this.onTap,
  });

  final List<DateTime> days;
  final DateTime focused;
  final DateTime today;
  final void Function(DateTime day) onTap;

  @override
  Widget build(BuildContext context) {
    final narrow = MaterialLocalizations.of(context).narrowWeekdays;
    return Row(
      children: [
        for (final day in days)
          Expanded(
            child: _WeekStripDay(
              day: day,
              letter: narrow[day.weekday % 7],
              focused: DateUtils.isSameDay(day, focused),
              today: DateUtils.isSameDay(day, today),
              onTap: () => onTap(day),
            ),
          ),
      ],
    );
  }
}

class _WeekStripDay extends StatelessWidget {
  const _WeekStripDay({
    required this.day,
    required this.letter,
    required this.focused,
    required this.today,
    required this.onTap,
  });

  final DateTime day;
  final String letter;
  final bool focused;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final weekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    // Today is amber and the day you are reading is a filled disc. When they
    // are the same day the amber wins — it is the louder mark, and it is still
    // the day on screen.
    final Color disc;
    final Color ink;
    if (focused && today) {
      disc = AppColors.accentStrong;
      ink = _stripOnAccent;
    } else if (focused) {
      disc = AppColors.ink;
      ink = AppColors.surface;
    } else {
      disc = Colors.transparent;
      ink = today
          ? AppColors.accentStrong
          : (weekend ? AppColors.inkFaint : AppColors.ink);
    }
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            letter,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: 3),
          DecoratedBox(
            decoration: BoxDecoration(color: disc, shape: BoxShape.circle),
            child: SizedBox(
              width: 26,
              height: 26,
              child: Center(
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: focused || today
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: ink,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ink on the amber disc. Fixed rather than a theme token: the disc is the same
/// amber in both themes, so what reads on it does not change either.
const Color _stripOnAccent = Color(0xFF2A2410);

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: AppColors.surface,
      shape: CircleBorder(side: BorderSide(color: AppColors.hairline)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 16, color: AppColors.inkSoft),
        ),
      ),
    ),
  );
}

class _TruncatedNotice extends StatelessWidget {
  const _TruncatedNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      border: Border.all(color: AppColors.accentLine),
    ),
    child: Row(
      children: [
        const Icon(LucideIcons.info, size: 15, color: AppColors.accentStrong),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.t('time.calendar.truncated'),
            style: TextStyle(fontSize: 12.5, color: AppColors.ink),
          ),
        ),
      ],
    ),
  );
}
