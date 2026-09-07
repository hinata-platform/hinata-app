import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/timer_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/time_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hue_colors.dart';
import '../../core/widgets/glass_switch_chip.dart';
import '../../core/widgets/glass_filter_bar.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/time_grid/time_grid.dart';
import '../../core/widgets/time_grid/time_grid_model.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart' show GlassToastKind, showGlassToast;
import 'time_entry_sheet.dart';
import 'time_views.dart';
import 'timer_bar.dart';

/// The module's calendar: a person's own hours laid out on a day or a week.
///
/// The grid itself is [TimeGrid] in `core/widgets` — shared, because the stages
/// after this one draw absences, holidays and subscribed events on it, and
/// shift planning draws shifts. This page is the part that is about *time
/// entries*: which window to ask for, what to do with a swept span, and where a
/// dropped block ends up.
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

/// How many days the grid shows at once.
enum _Span { day, week }

class _TimeCalendarScreenState extends State<TimeCalendarScreen> {
  _Span _span = _Span.week;

  /// The day the view is anchored on — the day itself, or a day inside the week.
  /// The day the view is anchored on.
  DateTime _anchor = _today();

  List<WorkItem> _entries = const [];
  bool _loading = true;
  String? _errorKey;
  bool _truncated = false;

  /// Monotonic token, so a slow week that resolves after the reader has paged
  /// on can never draw itself over the week now on screen.
  int _loadSeq = 0;

  /// The first window is asked for on the first [didChangeDependencies], not in
  /// [initState]: which day a week starts on comes from [MaterialLocalizations],
  /// and that is not reachable before the element is in the tree.
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_load());
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// The first day of [_anchor]'s week, in the reader's own locale.
  ///
  /// `firstDayOfWeekIndex` is 0 for Sunday, 1 for Monday — en-US starts on
  /// Sunday and German on Monday, and a calendar that always started on Monday
  /// would be wrong for half the app's languages. The server's weeks stay ISO;
  /// they are a different question (approval periods, stage 7) and are not
  /// this grid's business.
  DateTime _weekStart(DateTime day) {
    final first = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final delta = (day.weekday % 7 - first + 7) % 7;
    return DateTime(day.year, day.month, day.day - delta);
  }

  List<DateTime> get _days {
    if (_span == _Span.day) return [_anchor];
    final start = _weekStart(_anchor);
    return [for (var i = 0; i < 7; i++) _addDays(start, i)];
  }

  static DateTime _addDays(DateTime day, int days) =>
      // Through the constructor, not a Duration: a duration is an exact number
      // of hours, so in a week that changes clocks it lands at 23:00 the day
      // before and the whole grid shifts by one column.
      DateTime(day.year, day.month, day.day + days);

  bool get _isCurrent {
    final today = _today();
    return _days.any(
      (day) =>
          day.year == today.year &&
          day.month == today.month &&
          day.day == today.day,
    );
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    final days = _days;
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final window = await context.read<TimeRepository>().calendar(
        days.first,
        days.last,
      );
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _entries = window.entries;
        _truncated = window.truncated;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _errorKey = failure.message;
        _loading = false;
      });
    }
  }

  void _move(int steps) {
    setState(
      () => _anchor = _addDays(_anchor, steps * (_span == _Span.day ? 1 : 7)),
    );
    unawaited(_load());
  }

  void _setSpan(_Span span) {
    if (span == _span) return;
    setState(() => _span = span);
    unawaited(_load());
  }

  void _goToday() {
    setState(() => _anchor = _today());
    unawaited(_load());
  }

  // --- what the grid reports back ---------------------------------------------

  Future<void> _createFrom(TimeGridSpan span) async {
    final saved = await showTimeEntrySheet(context, span: span);
    if (saved == null || !mounted) return;
    unawaited(_load());
  }

  Future<void> _openEntry(TimeGridItem item) async {
    final entry = item.data;
    if (entry is! WorkItem) return;
    final saved = await showTimeEntrySheet(context, entry: entry);
    if (saved == null || !mounted) return;
    unawaited(_load());
  }

  /// A block dropped somewhere else. Optimistic: the grid already draws it in
  /// its new place, and a refusal puts it back by reloading the window.
  Future<void> _moveEntry(TimeGridItem item, TimeGridSpan span) async {
    final entry = item.data;
    if (entry is! WorkItem) return;
    final previous = _entries;
    setState(() {
      _entries = [
        for (final existing in _entries)
          if (existing.id == entry.id) _moved(existing, span) else existing,
      ];
    });
    try {
      await context.read<TimeRepository>().update(
        entry.id,
        TimeEntryDraft(
          startedAt: span.start,
          endedAt: span.end,
          date: DateTime(span.start.year, span.start.month, span.start.day),
          description: entry.description,
          activityType: entry.activityType,
        ),
      );
      if (mounted) unawaited(_load());
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _entries = previous);
      showGlassToast(
        context,
        context.t(failure.message),
        kind: GlassToastKind.error,
      );
    }
  }

  /// [entry] as it will be once the server agrees — what the grid draws while
  /// the request is in the air.
  ///
  /// Written out rather than copied with: [WorkItem] has no `copyWith`, and
  /// adding one for this would put a mutation helper on the model every screen
  /// then reaches for. Only the four fields a move actually changes are
  /// rebuilt; the rest come straight off the entry.
  static WorkItem _moved(WorkItem entry, TimeGridSpan span) => WorkItem(
    id: entry.id,
    issueId: entry.issueId,
    projectId: entry.projectId,
    userId: entry.userId,
    date: DateTime(span.start.year, span.start.month, span.start.day),
    durationMinutes: span.end.difference(span.start).inMinutes,
    activityType: entry.activityType,
    description: entry.description,
    createdAt: entry.createdAt,
    startedAt: span.start,
    endedAt: span.end,
    billable: entry.billable,
    tags: entry.tags,
    source: entry.source,
  );

  // --- build --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return PageChrome(
      fullWidth: true,
      bottom: compact ? _dockedControls() : null,
      bottomHeight: compact ? _kDockHeight : 0,
      child: BlocListener<TimerCubit, TimerState>(
        listenWhen: (previous, current) =>
            previous.isRunning && !current.isRunning,
        listener: (context, state) => unawaited(_load()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact) ...[
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
                      onPressed: () => _createFrom(_defaultSpan()),
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
                  child: TimerBar(onStopped: _load),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  context.pageGutter,
                  0,
                  context.pageGutter,
                  10,
                ),
                child: Row(children: [..._navigation(), const Spacer()]),
              ),
            ],
            if (_truncated)
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
                  context.pageGutter,
                  // On a phone nothing sits above the grid in the column — the
                  // controls are docked into the glass bar — so the body spends
                  // the bar's height itself. (The notice above spends it when
                  // it is there.)
                  compact && !_truncated ? context.topGutter + 8 : 0,
                  context.pageGutter,
                  context.bottomGutter + 8,
                ),
                child: _body(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TimeGridSpan _defaultSpan() {
    final day = _days.first;
    final start = DateTime(day.year, day.month, day.day, 9);
    return (start: start, end: start.add(const Duration(hours: 1)));
  }

  Widget _body() {
    if (_loading && _entries.isEmpty) {
      return const Center(child: HiveLoader(size: 44));
    }
    if (_errorKey != null && _entries.isEmpty) {
      return HiveEmptyState(
        title: context.t('time.error.title'),
        message: context.t(_errorKey!),
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(LucideIcons.refreshCw, size: 15),
          label: Text(context.t('common.retry')),
        ),
      );
    }
    return TimeGrid(
      days: _days,
      layers: _layers(),
      step: const Duration(minutes: 15),
      onCreate: _createFrom,
      onMoved: _moveEntry,
      onTap: _openEntry,
    );
  }

  /// Two layers over the same entries: the ones that happened between two
  /// times, and the ones that are only a duration on a day.
  ///
  /// The second lot cannot be drawn on the hour canvas — a plain duration
  /// occupies no hours — but leaving them out would make a day somebody logged
  /// look empty. They ride in the band under the headings instead, which is
  /// also where absences and holidays go when stage 10 lands.
  List<TimeGridLayer> _layers() {
    final timed = <TimeGridItem>[];
    final untimed = <TimeGridItem>[];
    for (final entry in _entries) {
      final item = _itemFor(entry);
      if (item == null) continue;
      (entry.startedAt != null && entry.endedAt != null ? timed : untimed).add(
        item,
      );
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

  TimeGridItem? _itemFor(WorkItem entry) {
    final title = entry.description?.trim().isNotEmpty == true
        ? entry.description!.trim()
        : context.t('time.entry.noDescription');
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
      // the canvas would silently invent a start time nobody recorded.
      movable: false,
      tint: _tintFor(entry),
      data: entry,
    );
  }

  /// A colour per project, so a week reads as projects rather than as a wall of
  /// amber. Unfiled entries keep the accent.
  Color _tintFor(WorkItem entry) {
    final projectId = entry.projectId;
    if (projectId == null) return AppColors.accent;
    return hueColor(projectId.hashCode.abs() % 360);
  }

  // --- the controls -------------------------------------------------------------

  List<Widget> _navigation() => [
    _RoundButton(
      icon: LucideIcons.chevronLeft,
      tooltip: context.t('time.calendar.previous'),
      onTap: () => _move(-1),
    ),
    const SizedBox(width: 6),
    _RoundButton(
      icon: LucideIcons.chevronRight,
      tooltip: context.t('time.calendar.next'),
      onTap: () => _move(1),
    ),
    const SizedBox(width: 10),
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
    const SizedBox(width: 10),
    ConstrainedBox(
      // Bounded like the view switcher, and for the same reason: a glass pill
      // laid out in a Row takes whatever width its labels want, and in a
      // language with long words for "day" and "week" that is more than the
      // row has. Past the ceiling the two chips scroll inside the pill.
      constraints: BoxConstraints(maxWidth: context.isCompact ? 130 : 230),
      child: GlassFloatingSurface(
        radius: 21,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icons only on a phone, the way the view switcher goes: the
                // row already carries two arrows, a date and a way back to
                // today, and two more words do not fit beside them.
                GlassSwitchChip(
                  label: context.t('time.calendar.day'),
                  icon: LucideIcons.calendar,
                  active: _span == _Span.day,
                  iconOnly: context.isCompact,
                  onTap: () => _setSpan(_Span.day),
                ),
                const SizedBox(width: 2),
                GlassSwitchChip(
                  label: context.t('time.calendar.week'),
                  icon: LucideIcons.calendarRange,
                  active: _span == _Span.week,
                  iconOnly: context.isCompact,
                  onTap: () => _setSpan(_Span.week),
                ),
              ],
            ),
          ),
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
  ];

  /// The window, named as briefly as the width allows.
  ///
  /// A phone gets the numeric form: spelled out, a week reads "7. Sept. 2026 –
  /// 13. Sept. 2026", which is most of the row and pushed the day/week control
  /// off the edge of it.
  String _rangeLabel() {
    final localizations = MaterialLocalizations.of(context);
    final compact = context.isCompact;
    final days = _days;
    if (days.length == 1) {
      return compact
          ? localizations.formatCompactDate(days.first)
          : localizations.formatMediumDate(days.first);
    }
    String short(DateTime day) => compact
        ? localizations.formatCompactDate(day)
        : localizations.formatShortDate(day);
    return '${short(days.first)} – ${short(days.last)}';
  }

  /// The phone's controls, in the band the app bar is already blurring — the
  /// same two rows the list wears, so the module's pages read as one place.
  Widget _dockedControls() {
    final gutter = context.pageGutter;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: kGlassControlHeight,
          child: Row(
            children: [
              SizedBox(width: gutter),
              // The switcher alone. The range belongs beside the arrows that
              // move it, one row down — printed here as well it was the same
              // sentence twice, and it pushed the day/week control off the
              // edge of the row that needed the space.
              const TimeViewSwitcher(current: TimeView.calendar),
              const Spacer(),
              SizedBox(width: gutter),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: kGlassControlHeight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Row(children: _navigation()),
          ),
        ),
      ],
    );
  }
}

/// Height of the docked control band: two rows and the gap between them, the
/// same shape the list's filters have.
const double _kDockHeight = kGlassControlHeight + 8 + kGlassControlHeight;

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
