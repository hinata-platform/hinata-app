import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../i18n/i18n.dart';
import '../../theme/app_colors.dart';
import '../hive_widgets.dart' show fmtDuration;
import 'time_grid_model.dart';
import 'time_month_layout.dart';

/// A month as weeks × days, scrolling on for as long as somebody keeps
/// scrolling — the calendar's widest span, and the one the hour canvas cannot
/// draw.
///
/// [TimeGrid] gives a day a column of hours, which is what makes a day readable
/// and what makes a month impossible: thirty-one columns on a phone is two
/// millimetres each. So a month is a different drawing of the same data — the
/// same [TimeGridItem]s, laid out by the day they are filed under rather than
/// by the hours they cover.
///
/// That difference is also why an entry logged as a plain duration finally has
/// somewhere to be. On the hour canvas it has no span and rides in the band
/// under the headings; here it is a chip in its day like everything else, and
/// it counts towards the day's total through [TimeGridItem.accounted].
///
/// **Why it scrolls rather than fits.** A month that fits the page is a month
/// you leave to see the next one, and the two months either side of a deadline
/// are the ones anybody actually wants together. Scrolling makes them one
/// surface: the weeks run on, each month begins on its own row with the days
/// before the 1st left blank, and the title above says which month the top of
/// the screen is in.
///
/// **What it does not do is fetch.** [itemsForDay] is a lookup the owner fills;
/// [onNeedMonths] tells the owner which months the finger has reached. Keeping
/// the requests outside means the widget can be driven from a test with a map
/// and no server at all, and that the owner — which already knows about
/// windows, truncation and failures — stays the only thing that talks to one.
class TimeMonthScroller extends StatefulWidget {
  const TimeMonthScroller({
    super.key,
    required this.anchor,
    required this.jump,
    required this.revision,
    required this.itemsForDay,
    required this.onNeedMonths,
    required this.onMonthChanged,
    this.failureFor,
    this.now,
    this.showTotals = true,
    this.onTapDay,
    this.onTap,
    this.onRetryMonth,
  });

  /// The month the scroller centres on when [jump] changes.
  final DateTime anchor;

  /// Bumped by the owner for every deliberate jump — "today", a tap from
  /// elsewhere, the wide window's arrows.
  ///
  /// A token rather than a changed [anchor], because the two are not the same
  /// question. Scrolling does not move the anchor, so pressing "today" while
  /// already anchored on this month hands the scroller a value it has seen
  /// before — and a scroller that re-centres only on a *changed* anchor stays
  /// where the finger left it while the title above it says something else.
  final int jump;

  /// Bumped by the owner whenever [itemsForDay] would answer differently.
  ///
  /// The blocks are memoised — a month is thirty-odd cells and a scroll rebuild
  /// re-records every one of them — and a lookup function cannot say when its
  /// answers changed. This can.
  final int revision;

  /// What was logged on a day, by [dayKey]. Missing and empty are the same
  /// answer to the grid; the owner is the one that knows whether a month is
  /// empty or simply not here yet.
  final List<TimeGridItem> Function(int dayKey) itemsForDay;

  /// Why a month could not be read, by [monthKey], or null where it could.
  ///
  /// A month that failed and a month in which nobody logged anything draw
  /// identically otherwise, and the calendar would be telling somebody they did
  /// not work. It says so over that month's own rows rather than over the whole
  /// page, because the months either side of it may have arrived perfectly.
  final String? Function(int monthKey)? failureFor;

  /// The months now within reach — the visible one and its neighbours, so a
  /// flick lands on hours that are already there. Called after the frame, only
  /// when the set changes.
  final void Function(List<DateTime> months) onNeedMonths;

  /// The month the top of the viewport is in. Called only when it changes.
  final void Function(DateTime month) onMonthChanged;

  /// Injected in tests; [DateTime.now] otherwise.
  final DateTime? now;

  /// Whether a day writes what it adds up to beside its number. Suppressed
  /// where the columns are too narrow to hold both.
  final bool showTotals;

  /// A tap on a day — the way into that day's hours.
  final void Function(DateTime day)? onTapDay;

  /// A tap on one of the chips.
  final void Function(TimeGridItem item)? onTap;

  /// Ask for a month that failed again.
  final void Function(DateTime month)? onRetryMonth;

  @override
  State<TimeMonthScroller> createState() => _TimeMonthScrollerState();
}

class _TimeMonthScrollerState extends State<TimeMonthScroller> {
  final _controller = ScrollController();

  /// Splits the list into the months before [_centre] and the months from it
  /// on. Everything below is measured from the boundary between the two, which
  /// is where [ScrollPosition.pixels] reads zero.
  final _forwardKey = UniqueKey();

  /// The month offset 0 counts from — held so a rebuild that only changed the
  /// entries does not move the ground under the finger.
  late DateTime _centre;

  int _firstDayOfWeekIndex = 0;

  /// The locale the held blocks were built in.
  ///
  /// Not the same question as the first day of the week: German and French
  /// start on Monday, and a cell writes "+2 weitere" and a duration in words.
  /// Held across the switch, a French month kept its German labels.
  Locale? _locale;

  /// The month block widgets, by [monthKey].
  ///
  /// Held rather than rebuilt, and that is what makes a fling cheap: the sliver
  /// delegates are new objects on every build and `shouldRebuild` on those is
  /// unconditionally true, so without this every live month re-ran thirty-odd
  /// cells and a few hundred `InkWell`s — during the scroll that asked for the
  /// next month. Returning the same widget instance makes the framework
  /// short-circuit the subtree instead.
  ///
  /// A held block also holds the callbacks it was built with. That is safe
  /// because the owner passes method tear-offs off its own `State`, which do
  /// not change; a caller that passed a closure built per frame would get the
  /// first one for as long as the memo lives.
  final Map<int, Widget> _blocks = {};

  /// What [_blocks] was built for. Any of these changing throws the memo away.
  int? _blocksRevision;
  bool? _blocksTotals;
  int? _blocksToday;

  /// The brightness the held blocks were built at.
  ///
  /// The app's neutral tokens are a *global* the widgets read as they build —
  /// `AppColors.ink` is one value or the other depending on a static the app
  /// sets each frame — so a widget kept across a theme change keeps the colours
  /// it was born with. Held blocks came out in light ink on the dark canvas:
  /// the weekday numbers were very nearly invisible. Any memo of widgets in
  /// this app has to count the brightness among its inputs.
  Brightness? _blocksBrightness;

  /// Last reported, so the owner hears about a change and not about a frame.
  int? _reportedMonth;

  /// Where the last walk ended, so the next one starts there.
  ///
  /// A fling moves at most a month or two per frame, and the walk from the
  /// anchor costs a step per month scrolled — unbounded, and paid on every
  /// scroll notification. From here it is O(1).
  int _walkOffset = 0;
  double _walkEdge = 0;

  /// Row heights, by [monthKey] — not by offset.
  ///
  /// By offset it was wrong the moment [_centre] moved: offset 0 means a
  /// different month after a jump, and a four-row month reading a five-row
  /// height puts the walk 140 points out. Every scroll after that names the
  /// wrong month, which is the title, the prefetch and the window a save
  /// re-fetches, all at once.
  final Map<int, double> _heights = {};

  @override
  void initState() {
    super.initState();
    _centre = _monthOf(widget.anchor);
    _controller.addListener(_report);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The first report cannot wait for a scroll: nothing has moved yet, and the
    // month on screen still has to be named and fetched.
    _scheduleReport();
  }

  @override
  void didUpdateWidget(TimeMonthScroller old) {
    super.didUpdateWidget(old);
    if (widget.jump == old.jump) return;
    // A jump is not a scroll — re-centre on the anchor and start over.
    setState(() {
      _centre = _monthOf(widget.anchor);
      _reportedMonth = null;
      _walkOffset = 0;
      _walkEdge = 0;
      // [_blocks] and [_heights] are both keyed by month, so a new centre
      // leaves every entry in them still true of the month it names. Only the
      // walk's cursor was about the old centre.
    });
    // After the frame, never from here. `jumpTo` notifies its listeners
    // synchronously, so reporting from inside the parent's build phase marks
    // the owner dirty while it is being built.
    _scheduleReport(recentre: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static DateTime _monthOf(DateTime day) => DateTime(day.year, day.month);

  /// The month [offset] blocks away from the centre. Through the constructor,
  /// which normalises: month 13 is January of the next year.
  DateTime _monthAt(int offset) =>
      DateTime(_centre.year, _centre.month + offset);

  double _heightOf(int offset) {
    final month = _monthAt(offset);
    return _heights[monthKey(month)] ??=
        weeksInMonth(month, firstDayOfWeekIndex: _firstDayOfWeekIndex) *
        kMonthWeekExtent;
  }

  /// The month the top edge of the viewport is in.
  ///
  /// Walked rather than divided: month blocks are four, five or six rows tall,
  /// so there is no single row count to divide by. The walk resumes from where
  /// it stopped last, which for a scroll is a step or two.
  int _monthOffsetAt(double pixels) {
    // The viewport is infinite in both directions, so `maxScrollExtent` is too
    // and the usual clamping says nothing. A non-finite offset would spin here
    // for ever rather than land on a month.
    if (!pixels.isFinite) return _walkOffset;
    var offset = _walkOffset;
    var edge = _walkEdge;
    // Forward until the block containing [pixels] is the current one …
    while (edge + _heightOf(offset) <= pixels) {
      edge += _heightOf(offset);
      offset++;
    }
    // … and back for a scroll that went the other way.
    while (edge > pixels) {
      offset--;
      edge -= _heightOf(offset);
    }
    _walkOffset = offset;
    _walkEdge = edge;
    return offset;
  }

  void _scheduleReport({bool recentre = false}) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (recentre && _controller.hasClients) _controller.jumpTo(0);
        _report();
      });

  /// Names the month on screen and asks for the ones around it.
  ///
  /// Debounced against what was said last: the owner rebuilds on either, and a
  /// scroll produces sixty of these a second.
  void _report() {
    if (!_controller.hasClients) return;
    final month = _monthAt(_monthOffsetAt(_controller.position.pixels));
    final key = monthKey(month);
    if (key == _reportedMonth) return;
    _reportedMonth = key;
    widget.onMonthChanged(month);
    // The neighbours too: a flick crosses a month boundary long before a
    // request comes back, and an empty month that turns out to have hours in it
    // is the one thing a calendar must not do.
    widget.onNeedMonths([
      DateTime(month.year, month.month - 1),
      month,
      DateTime(month.year, month.month + 1),
    ]);
  }

  /// Takes the locale's answers from the build rather than from
  /// [didChangeDependencies].
  ///
  /// `Localizations` tells its dependents apart only by *locale*: when its
  /// delegates finish resolving — they may be asset-backed and asynchronous —
  /// it rebuilds with real translations and a real first day of the week, but
  /// `updateShouldNotify` is false, so nothing that read the value once is
  /// asked again. Cached in `didChangeDependencies`, the scroller kept the
  /// default Sunday-start week for the life of the page and measured every
  /// month a row wrong on a Monday-start locale.
  void _readLocale() {
    final first = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    if (first != _firstDayOfWeekIndex) {
      _firstDayOfWeekIndex = first;
      // Every height and every block was laid out on the other week.
      _heights.clear();
      _blocks.clear();
    }
    // Not the same question: German and French both start on Monday, and a cell
    // writes "+2 weitere" and a duration in words.
    final locale = Localizations.localeOf(context);
    if (locale != _locale) {
      _locale = locale;
      _blocks.clear();
    }
  }

  /// The block for the month [offset] away, built once per (data, width, day,
  /// theme).
  Widget _blockAt(int offset, DateTime today, Brightness brightness) {
    final todayKey = dayKey(today);
    if (_blocksRevision != widget.revision ||
        _blocksTotals != widget.showTotals ||
        _blocksToday != todayKey ||
        _blocksBrightness != brightness) {
      _blocksRevision = widget.revision;
      _blocksTotals = widget.showTotals;
      _blocksToday = todayKey;
      _blocksBrightness = brightness;
      _blocks.clear();
    }
    final month = _monthAt(offset);
    final key = monthKey(month);
    // A failure is not memoised: it arrives and clears without the data
    // changing, so a held block would keep saying a month could not be read
    // after it has been.
    final failure = widget.failureFor?.call(key);
    if (failure != null) {
      return _FailedMonth(
        month: month,
        firstDayOfWeekIndex: _firstDayOfWeekIndex,
        message: failure,
        onRetry: widget.onRetryMonth,
      );
    }
    // Nothing stale can be held for a month that has just recovered: the
    // failure path above returns before the memo is ever touched.
    return _blocks[key] ??= _MonthBlock(
      month: month,
      firstDayOfWeekIndex: _firstDayOfWeekIndex,
      itemsForDay: widget.itemsForDay,
      today: today,
      showTotals: widget.showTotals,
      onTapDay: widget.onTapDay,
      onTap: widget.onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    _readLocale();
    final today = widget.now ?? DateTime.now();
    // Two different things, deliberately. The `Theme.of` call is what makes
    // this element depend on the theme, so a change rebuilds it at all. The key
    // is `AppColors.brightness`, because that is the value the tokens are read
    // from — `Theme.of` crossfades over the theme animation and reports the old
    // brightness for those two hundred milliseconds, which would hold the stale
    // ink on screen for exactly as long as anybody is looking at the change.
    Theme.of(context);
    final brightness = AppColors.brightness;
    return CustomScrollView(
      controller: _controller,
      // Everything before this sliver grows upward from offset zero, which is
      // what makes the months above the anchor reachable at all: a list can
      // only be infinite in both directions if it has a middle.
      center: _forwardKey,
      // A month block is four to six rows tall, so the default 250-point cache
      // keeps whole months either side of the viewport built and laid out. One
      // row is enough to scroll smoothly into.
      scrollCacheExtent: const ScrollCacheExtent.pixels(kMonthWeekExtent),
      slivers: [
        // Before the centre, growing upward. A sliver ahead of [center] is laid
        // out in the reverse direction, so index 0 here is the month
        // immediately above the anchor.
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _blockAt(-index - 1, today, brightness),
            // Nothing in a month cell holds state worth keeping alive.
            addAutomaticKeepAlives: false,
          ),
        ),
        SliverList(
          key: _forwardKey,
          delegate: SliverChildBuilderDelegate(
            (context, index) => _blockAt(index, today, brightness),
            addAutomaticKeepAlives: false,
          ),
        ),
      ],
    );
  }
}

/// Height of one week's row.
///
/// At 140 a cell has 128 points inside it: the day line takes 22 and the five
/// chip rows that follow take 95, so an ordinary day names everything on it and
/// a very full one says how many are left.
const double kMonthWeekExtent = 140;

/// What the month keeps between its outer columns and the edge of the page.
///
/// Less than the page gutter, because seven columns is a grid and a full gutter
/// down each side costs most of a column on a phone — and more than nothing,
/// because at nothing the 1st and the 7th sit against the display edge. The
/// weekday letters above take the same inset, or the letters stop standing over
/// the columns they name.
const double kMonthGutter = 12;

/// Widest a column may be before a day writes its total beside its number.
/// Under this the number and "7:45" collide, and the number is the one that has
/// to survive.
const double kMonthTotalsMinColumn = 62;

/// Height the day's number occupies at the top of a cell — and the width of the
/// box it is centred in, which is what makes today's mark a circle rather than
/// an oval.
const double _kDayLine = 22;

/// What a cell keeps between its own edge and what it draws.
const double _kCellPad = 3;

/// Ink on the amber disc today's number sits in. A fixed near-black rather than
/// a theme token: the disc is [AppColors.accentStrong] in both themes, so what
/// reads on it does not change with the theme either.
const Color _onAccent = Color(0xFF2A2410);

/// The gap above each chip.
const double _kChipGap = 2;

/// One chip and the gap above it — what a cell divides its spare room by to
/// know how many entries it can name.
const double _kChipRow = 19;

/// The row of narrow weekday letters above the month.
///
/// Its own widget because it does not scroll with the weeks: the calendar docks
/// it into the app bar's glass, under the month's name, where it stays put over
/// whatever the finger has pulled into view.
class MonthWeekdayHeader extends StatelessWidget {
  const MonthWeekdayHeader({super.key, this.height = 22});

  final double height;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final narrow = localizations.narrowWeekdays;
    final first = localizations.firstDayOfWeekIndex;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kMonthGutter),
        child: Row(
          children: [
            for (var column = 0; column < 7; column++)
              Expanded(
                // The same leading box the day's number sits in, so the letter
                // stands over the number it names. Centred in the column
                // instead, it drifted a third of a column to the right of it —
                // the letters and the dates read as two different grids.
                child: Padding(
                  padding: const EdgeInsets.only(left: _kCellPad),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SizedBox(
                      width: _kDayLine,
                      child: Text(
                        narrow[(first + column) % 7],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          // The weekend recedes, the way it does in the grid
                          // below.
                          color: _isWeekend(first, column)
                              ? AppColors.inkFaint.withValues(alpha: 0.65)
                              : AppColors.inkFaint,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Whether the column at [column] of a week starting on [first] is a Saturday
/// or a Sunday. (0 is Sunday in the index `MaterialLocalizations` reports.)
bool _isWeekend(int first, int column) {
  final weekday = (first + column) % 7;
  return weekday == 0 || weekday == 6;
}

/// One month, in whole weeks, with the days before the 1st and after the last
/// left blank.
///
/// Blank rather than the neighbouring month's days greyed out, and that is the
/// whole reason the scroller is a stack of months rather than an unbroken run
/// of weeks: a month that starts on its own row is a month you can see the
/// start of. The neighbour is one row further on, drawn in its own block.
class _MonthBlock extends StatelessWidget {
  const _MonthBlock({
    required this.month,
    required this.firstDayOfWeekIndex,
    required this.itemsForDay,
    required this.today,
    required this.showTotals,
    this.onTapDay,
    this.onTap,
  });

  final DateTime month;
  final int firstDayOfWeekIndex;
  final List<TimeGridItem> Function(int dayKey) itemsForDay;
  final DateTime today;
  final bool showTotals;
  final void Function(DateTime day)? onTapDay;
  final void Function(TimeGridItem item)? onTap;

  @override
  Widget build(BuildContext context) {
    final length = DateUtils.getDaysInMonth(month.year, month.month);
    final days = [
      for (var i = 0; i < length; i++) DateTime(month.year, month.month, i + 1),
    ];
    final layout = MonthLayout.of(
      days,
      firstDayOfWeekIndex: firstDayOfWeekIndex,
    );
    // No `RepaintBoundary` per week: `SliverChildBuilderDelegate` already gives
    // each block one, so a scroll offsets that layer rather than re-recording
    // anything inside it. Adding another per week only multiplies the
    // composited layers — and the ink splashes paint above them anyway.
    return Column(
      children: [
        for (var week = 0; week < layout.weeks; week++)
          SizedBox(
            height: kMonthWeekExtent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.hairline, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  for (var column = 0; column < 7; column++)
                    Expanded(
                      child: _Cell(
                        day: layout.dayAt(week, column),
                        today: today,
                        itemsForDay: itemsForDay,
                        weekend: _isWeekend(firstDayOfWeekIndex, column),
                        showTotal: showTotals,
                        onTapDay: onTapDay,
                        onTap: onTap,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A month the server would not give us, drawn where that month belongs.
///
/// The alternative is a month of empty cells, which in a record of hours is the
/// app telling somebody they did not work. It takes the same room the month
/// would have taken, so the months either side of it stay where they are and
/// the scroll does not jump when the retry lands.
class _FailedMonth extends StatelessWidget {
  const _FailedMonth({
    required this.month,
    required this.firstDayOfWeekIndex,
    required this.message,
    this.onRetry,
  });

  final DateTime month;
  final int firstDayOfWeekIndex;
  final String message;
  final void Function(DateTime month)? onRetry;

  @override
  Widget build(BuildContext context) => SizedBox(
    height:
        weeksInMonth(month, firstDayOfWeekIndex: firstDayOfWeekIndex) *
        kMonthWeekExtent,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kMonthGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.cloudOff, size: 22, color: AppColors.inkFaint),
            const SizedBox(height: 10),
            Text(
              MaterialLocalizations.of(context).formatMonthYear(month),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.t(message),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => onRetry!(month),
                icon: const Icon(LucideIcons.refreshCw, size: 14),
                label: Text(context.t('common.retry')),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// One day: its number, what it adds up to, and as many of its entries as the
/// cell is tall enough to name.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.today,
    required this.itemsForDay,
    required this.weekend,
    required this.showTotal,
    this.onTapDay,
    this.onTap,
  });

  /// Null for the cells before the first of the month and after the last.
  final DateTime? day;
  final DateTime today;
  final List<TimeGridItem> Function(int dayKey) itemsForDay;
  final bool weekend;
  final bool showTotal;

  final void Function(DateTime day)? onTapDay;
  final void Function(TimeGridItem item)? onTap;

  /// Room a cell has under its number, in whole chips.
  static const int _room = ((kMonthWeekExtent - 8 - _kDayLine) ~/ _kChipRow);

  @override
  Widget build(BuildContext context) {
    final at = day;
    if (at == null) return const SizedBox.shrink();
    final items = itemsForDay(dayKey(at));
    final isToday = DateUtils.isSameDay(at, today);
    final minutes = items.fold<int>(
      0,
      (sum, item) => sum + item.accounted.inMinutes,
    );
    // The overflow line takes a chip's place, so showing "+1 more" instead of
    // the one entry it stands for helps nobody.
    final room = _room.clamp(0, items.length);
    final shown = room < items.length && room > 0 ? room - 1 : room;
    final hidden = items.length - shown;

    return InkWell(
      onTap: onTapDay == null ? null : () => onTapDay!(at),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_kCellPad, 4, _kCellPad, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Every date is written in full ink; only the weekend recedes.
            // Fading the days with nothing logged on them was tried and is
            // wrong: an empty month — a new account, a month not fetched yet,
            // a month whose request failed — came out uniformly grey and read
            // as disabled. What was logged is what the chips are for.
            _DayLine(
              day: at,
              today: isToday,
              weekend: weekend,
              minutes: showTotal ? minutes : 0,
            ),
            for (final item in items.take(shown))
              _Chip(item: item, onTap: onTap),
            if (hidden > 0)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  // `count:`, not a string in `variables` — i18next reads the
                  // plural form off an *int*, and a string silently selects the
                  // singular in all nine languages.
                  context.t('time.calendar.more', count: hidden),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The day's number, and what the day came to.
///
/// Today's number sits in a filled amber disc — the calendar's one loud mark,
/// and the thing a reader looks for first.
class _DayLine extends StatelessWidget {
  const _DayLine({
    required this.day,
    required this.today,
    required this.weekend,
    required this.minutes,
  });

  final DateTime day;
  final bool today;
  final bool weekend;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final number = Text(
      '${day.day}',
      style: TextStyle(
        fontSize: 13,
        fontWeight: today ? FontWeight.w800 : FontWeight.w600,
        color: today
            ? _onAccent
            : (weekend ? AppColors.inkFaint : AppColors.ink),
      ),
    );
    return SizedBox(
      height: _kDayLine,
      child: Row(
        children: [
          if (today)
            DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.accentStrong,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: _kDayLine,
                height: _kDayLine,
                child: Center(child: number),
              ),
            )
          else
            SizedBox(
              width: _kDayLine,
              height: _kDayLine,
              child: Center(child: number),
            ),
          if (minutes > 0)
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 2),
                child: Text(
                  fmtDuration(context, minutes),
                  maxLines: 1,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One entry in a day cell: the layer's colour and as much of the title as fits.
class _Chip extends StatelessWidget {
  const _Chip({required this.item, this.onTap});

  final TimeGridItem item;
  final void Function(TimeGridItem item)? onTap;

  @override
  Widget build(BuildContext context) {
    final tint = item.tint ?? AppColors.accent;
    return Padding(
      padding: const EdgeInsets.only(top: _kChipGap),
      child: SizedBox(
        height: _kChipRow - _kChipGap,
        child: InkWell(
          onTap: onTap == null ? null : () => onTap!(item),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: AlignmentDirectional.centerStart,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(4),
              border: BorderDirectional(
                start: BorderSide(color: tint, width: 2),
              ),
            ),
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
