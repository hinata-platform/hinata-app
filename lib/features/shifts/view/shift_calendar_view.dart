import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/project_repository.dart';
import '../../../core/repositories/shift_repository.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/theme/glass_chrome.dart' show GlassCircleButton;
import '../../../core/util/dates.dart' show addDays, weekStartFor;
import '../../../core/widgets/glass_filter_bar.dart'
    show GlassFilterPill, GlassPill, kGlassControlHeight, kGlassDockRow;
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/glass_switch_chip.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart' show GhostButton;
import '../../../core/widgets/project_picker.dart';
import '../../../core/widgets/time_grid/time_day_dots.dart';
import '../../../core/widgets/time_grid/time_grid.dart';
import '../../../core/widgets/time_grid/time_grid_geometry.dart'
    show TimeGridMetrics;
import '../../../core/widgets/time_grid/time_grid_model.dart';
import '../../../core/widgets/time_grid/time_month_grid.dart';
import '../../../core/widgets/time_grid/time_month_layout.dart'
    show dayKey, monthKey;
import '../../../core/widgets/time_grid/time_week_strip.dart';
import '../../shell/page_chrome.dart';
import '../../sprint/modals/glass_modal.dart'
    show
        GlassToastKind,
        anchorRectOfContext,
        showGlassConfirm,
        showGlassOptions,
        showGlassToast;
import '../bloc/shift_calendar_cubit.dart';
import '../shift_texts.dart';
import '../shift_views.dart';
import '../shift_zones.dart';
import '../widgets/shift_visibility.dart';
import '../widgets/series_scope_dialog.dart';
import '../widgets/shift_editor.dart' show showShiftEditor;
import '../widgets/shift_event_editor.dart' show showShiftEventEditor;
import '../widgets/shift_plan_texts.dart';
import '../widgets/shift_sheet.dart';
import '../widgets/shifts_head.dart';

/// What the address of the calendar says: `?project=&span=&date=`.
@immutable
class ShiftCalendarQuery {
  const ShiftCalendarQuery({this.projectId, this.span, this.date});

  factory ShiftCalendarQuery.parse(Map<String, String> query) =>
      ShiftCalendarQuery(
        projectId: (query['project'] ?? '').isEmpty ? null : query['project'],
        span: query['span'] == null
            ? null
            : ShiftCalendarSpan.parse(query['span']),
        date: DateTime.tryParse(query['date'] ?? ''),
      );

  final String? projectId;
  final ShiftCalendarSpan? span;
  final DateTime? date;

  @override
  bool operator ==(Object other) =>
      other is ShiftCalendarQuery &&
      other.projectId == projectId &&
      other.span == span &&
      other.date == date;

  @override
  int get hashCode => Object.hash(projectId, span, date);
}

/// The address of [state], for the route.
String shiftCalendarLocation(ShiftCalendarState state) {
  final f = state.focused;
  String two(int v) => v.toString().padLeft(2, '0');
  return Uri(
    path: ShiftsView.calendar.route,
    queryParameters: {
      'project': ?state.projectId,
      'span': state.span.name,
      'date': '${f.year}-${two(f.month)}-${two(f.day)}',
    },
  ).toString();
}

/// `/shifts/calendar`: provides the calendar's cubit (HIN-160).
class ShiftCalendarPage extends StatelessWidget {
  const ShiftCalendarPage({super.key, this.query = const ShiftCalendarQuery()});

  final ShiftCalendarQuery query;

  @override
  Widget build(BuildContext context) {
    final projects = context.read<ProjectRepository>();
    return BlocProvider(
      create: (_) => ShiftCalendarCubit(
        context.read<ShiftRepository>(),
        focused: query.date ?? DateTime.now(),
        span: query.span ?? ShiftCalendarSpan.week,
        projectId: query.projectId,
        projectNameOf: (id) async => (await projects.project(id)).name,
      )..start(),
      child: Builder(
        builder: (context) => ShiftVisibilityRelay(
          onVisible: context.read<ShiftCalendarCubit>().setVisible,
          child: ShiftCalendarView(query: query),
        ),
      ),
    );
  }
}

/// A shift's project tint, stable for the project: the time calendar's
/// pastels, picked by the project rather than by the order it was seen in.
Color shiftTint(String projectId) {
  var hash = 0;
  for (final unit in projectId.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return AppColors.pastelFor(hash);
}

/// The calendar of shifts (HIN-160): a week of hours on a wide window, one day
/// of it under the week strip on a phone, or a month of marks. Own shifts carry
/// a check, shifts still short of people a warning triangle and "fehlt 1" in
/// their title; both when both. A planner moves a block by dragging it, which
/// asks first; the editor does the same with fields.
class ShiftCalendarView extends StatefulWidget {
  const ShiftCalendarView({
    super.key,
    this.query = const ShiftCalendarQuery(),
    this.now,
    this.deviceZone,
  });

  final ShiftCalendarQuery query;

  /// Injected in tests.
  final DateTime? now;

  /// The device's zone, injected in tests; read from the platform otherwise.
  final String? deviceZone;

  @override
  State<ShiftCalendarView> createState() => _ShiftCalendarViewState();
}

/// The page a phone's day pager opens on; days are counted from it.
const int _kOriginPage = 100000;

class _ShiftCalendarViewState extends State<ShiftCalendarView> {
  late final DateTime _origin;
  late final PageController _pager;
  int _jump = 0;
  String? _deviceZone;

  /// Where the last pointer went down, for the sheet to hang off a block.
  Offset? _lastPointer;

  final Map<Object, List<TimeGridLayer>> _layerMemo = {};
  final Map<int, List<DateTime>> _daysMemo = {};
  Object? _memoKey;

  ShiftCalendarCubit get _cubit => context.read<ShiftCalendarCubit>();

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _origin = _cubit.state.focused;
    _pager = PageController(initialPage: _kOriginPage);
    _deviceZone = widget.deviceZone;
    if (_deviceZone == null) {
      unawaited(
        ShiftZones.deviceZone().then((zone) {
          if (mounted && zone != null) setState(() => _deviceZone = zone);
        }),
      );
    }
  }

  @override
  void didUpdateWidget(ShiftCalendarView old) {
    super.didUpdateWidget(old);
    final q = widget.query;
    if (q == old.query) return;
    // The address changed from outside (a link, the back button): follow it.
    final cubit = _cubit;
    if (q.projectId != cubit.state.projectId) cubit.setProject(q.projectId);
    if (q.span != null) cubit.setSpan(q.span!);
    if (q.date != null) cubit.focus(q.date!);
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  // --- the address ----------------------------------------------------------

  void _syncRoute(ShiftCalendarState state) {
    if (!PageChromeVisibility.of(context)) return;
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final location = shiftCalendarLocation(state);
    if (router.state.uri.toString() == location) return;
    router.go(location);
  }

  // --- what the grid draws --------------------------------------------------

  void _checkMemo(ShiftCalendarState state) {
    final key = (
      state.revision,
      AppColors.themeKey,
      Localizations.localeOf(context),
      state.plannable.length,
    );
    if (_memoKey != key) {
      _memoKey = key;
      _layerMemo.clear();
    }
  }

  List<DateTime> _dayList(DateTime day) =>
      _daysMemo[dayKey(day)] ??= [DateTime(day.year, day.month, day.day)];

  List<DateTime> _weekOf(DateTime day) {
    final start = weekStartFor(context, day);
    return _daysMemo[-dayKey(start)] ??= [
      for (var i = 0; i < 7; i++) addDays(start, i),
    ];
  }

  List<TimeGridLayer> _layersFor(List<DateTime> days) {
    final state = _cubit.state;
    _checkMemo(state);
    final key = (dayKey(days.first), days.length);
    return _layerMemo[key] ??= _buildLayers(days, state);
  }

  List<TimeGridLayer> _buildLayers(
    List<DateTime> days,
    ShiftCalendarState state,
  ) {
    final cubit = _cubit;
    final others = <TimeGridItem>[];
    final short = <TimeGridItem>[];
    final mine = <TimeGridItem>[];
    final seen = <String>{};
    for (
      var d = addDays(days.first, -1);
      !d.isAfter(addDays(days.last, 1));
      d = addDays(d, 1)
    ) {
      for (final shift in cubit.shiftsOn(d)) {
        if (!seen.add(shift.id)) continue;
        final item = _item(shift, state);
        if (shift.mine) {
          mine.add(item);
        } else if (shift.isShort) {
          short.add(item);
        } else {
          others.add(item);
        }
      }
    }
    return [
      TimeGridLayer(id: 'others', items: others, edge: false),
      TimeGridLayer(
        id: 'understaffed',
        items: short,
        edge: false,
        glyph: LucideIcons.triangleAlert,
      ),
      TimeGridLayer(
        id: 'mine',
        items: mine,
        edge: false,
        glyph: LucideIcons.check,
      ),
    ];
  }

  TimeGridItem _item(Shift shift, ShiftCalendarState state) {
    final short = shift.isShort;
    return TimeGridItem(
      id: shift.id,
      start: shift.startsAt,
      end: shift.endsAt,
      title: short
          ? context.t(
              'shifts.calendar.blockMissing',
              count: shift.coverage.missing,
              variables: {'title': shift.title},
            )
          : shift.title,
      subtitle: shift.cancelled
          ? context.t('shifts.event.cancelled')
          : coverageFigure(context, shift.coverage),
      tint: shiftTint(shift.projectId),
      movable: state.canPlan(shift.projectId) && !shift.cancelled,
      data: shift,
      glyph: shift.mine && short ? LucideIcons.triangleAlert : null,
    );
  }

  /// The month marks a day from its counts; the week strip from the shifts
  /// it already holds.
  TimeDayDots? _dotsOn(DateTime day) {
    final cubit = _cubit;
    if (cubit.state.span == ShiftCalendarSpan.month) {
      final marks = cubit.marksOn(day);
      if (marks == null) return null;
      return _dots(
        dot: !cubit.state.understaffedOnly && marks.mine > 0,
        ring: marks.understaffed > 0,
      );
    }
    final shifts = cubit.shiftsOn(day);
    if (shifts.isEmpty) return null;
    final dot = shifts.any((s) => s.mine);
    final ring = shifts.any((s) => !s.mine && s.isShort);
    return _dots(dot: dot, ring: ring);
  }

  TimeDayDots? _dots({required bool dot, required bool ring}) {
    if (!dot && !ring) return null;
    return TimeDayDots(
      dot: dot,
      ring: ring,
      label: [
        if (dot) context.t('shifts.calendar.dotMine'),
        if (ring) context.t('shifts.calendar.dotOpen'),
      ].join(', '),
    );
  }

  // --- acting on it ---------------------------------------------------------

  Rect? get _pointerRect {
    final p = _lastPointer;
    return p == null ? null : Rect.fromCenter(center: p, width: 2, height: 2);
  }

  void _openShift(TimeGridItem item) {
    final shift = item.data;
    if (shift is! Shift) return;
    unawaited(
      showShiftSheet(
        context,
        shiftId: shift.id,
        anchorRect: _pointerRect,
        onOpenEvent: () =>
            context.push('${ShiftsView.events.route}/${shift.eventId}'),
      ),
    );
  }

  Future<void> _moved(TimeGridItem item, TimeGridSpan span) async {
    final shift = item.data;
    if (shift is! Shift) return;
    final message = context.t(
      'shifts.plan.move.message',
      variables: {
        'title': shift.title,
        'when':
            '${dayLabel(context, span.start)}, '
            '${spanLabel(context, span.start, span.end)}',
      },
    );
    final event = _cubit.eventOf(shift);
    ShiftScope? scope;
    if (event != null && event.inSeries) {
      // On an occurrence of a series the scope question is the confirmation.
      scope = await askSeriesScope(
        context,
        write: SeriesWrite.move,
        day: shift.startsLocal,
        recurrenceLabel: event.recurrenceLabel,
        note: message,
      );
      if (scope == null || !mounted) return;
    } else {
      final ok = await showGlassConfirm(
        context,
        icon: LucideIcons.move,
        title: context.t('shifts.plan.move.title'),
        message: message,
        confirmLabel: context.t('shifts.plan.move.confirm'),
        confirmIcon: LucideIcons.move,
      );
      if (ok != true || !mounted) return;
    }
    final outcome = await _cubit.move(
      shift,
      span.start,
      span.end,
      scope: scope,
    );
    if (!mounted) return;
    if (!outcome.ok) {
      showGlassToast(
        context,
        planErrorText(context, outcome.errorKey!),
        kind: GlassToastKind.error,
      );
      return;
    }
    final overlaps = overlapNotice(context, outcome.edit?.warnings ?? const []);
    showGlassToast(
      context,
      overlaps ?? context.t('shifts.plan.done.moved'),
      kind: overlaps == null ? GlassToastKind.success : GlassToastKind.warning,
    );
  }

  // --- planning on the calendar (HIN-166) ----------------------------------

  /// A span swept out, or double clicked, on empty canvas: the shift editor
  /// on the event it falls into, after a choice where that is not one.
  Future<void> _createFrom(TimeGridSpan span) async {
    // The grid reports the sweep while the pointer's release is still being
    // handed out; the listener above it records where that was right after.
    await Future<void>.value();
    if (!mounted) return;
    final anchor = _pointerRect;
    await _place(_cubit.createTarget(span.start, span.end), anchor);
  }

  /// Puts a new shift where [target] says: straight into the editor on its
  /// one event, or through a choice between the events, or a new event.
  Future<void> _place(ShiftCreateTarget target, Rect? anchor) async {
    final only = target.only;
    if (only != null) return _openShiftEditor(only, target.spanFor(only));
    final state = _cubit.state;
    final picked = await showGlassOptions<Object>(
      context,
      title: context.t('shifts.calendar.whichEvent'),
      anchorRect: anchor,
      options: [
        for (final event in target.events)
          (
            value: event,
            child: _ChoiceRow(
              icon: LucideIcons.calendarDays,
              title: event.title,
              subtitle: [
                ?state.projectNames[event.projectId],
                spanLabel(context, event.startsAt, event.endsAt),
              ].join(' · '),
            ),
          ),
        (
          value: const _NewEventChoice(),
          child: _ChoiceRow(
            icon: LucideIcons.calendarPlus,
            title: context.t('shifts.calendar.newEventAt'),
            subtitle: spanLabel(context, target.start, target.end),
          ),
        ),
      ],
    );
    if (!mounted || picked == null) return;
    if (picked is ShiftEventSummary) {
      return _openShiftEditor(picked, target.spanFor(picked));
    }
    await _newEventThenShift((start: target.start, end: target.end));
  }

  /// The shift editor on [event] with [span], turned into the event's own
  /// wall clock: the calendar draws on the device's.
  Future<void> _openShiftEditor(
    ShiftEventSummary event,
    TimeGridSpan span,
  ) async {
    final zone = event.timezone;
    if (zone != null && zone != _deviceZone) await ShiftZones.ensureLoaded();
    if (!mounted) return;
    await showShiftEditor(
      context,
      event: event,
      start: ShiftZones.toWall(span.start, zone, _deviceZone),
      end: ShiftZones.toWall(span.end, zone, _deviceZone),
    );
  }

  /// "Neues Event mit dieser Zeit": the event editor on [span], and once the
  /// event is saved, its first shift with the same time.
  Future<void> _newEventThenShift(TimeGridSpan span) async {
    final saved = await _newEvent(start: span.start, end: span.end);
    if (saved == null || !mounted) return;
    await _openShiftEditor(saved, span);
  }

  /// The event editor for a new event, narrowed to the calendar's project
  /// when it is one the caller plans. Resolves to the event saved.
  Future<ShiftEventSummary?> _newEvent({
    DateTime? day,
    DateTime? start,
    DateTime? end,
  }) async {
    final cubit = _cubit;
    final state = cubit.state;
    final plannable = state.plannableInScope;
    final saved = await showShiftEventEditor(
      context,
      projectId: state.projectId != null && plannable.contains(state.projectId)
          ? state.projectId
          : null,
      projectName: state.projectName,
      plannable: plannable,
      day: day,
      start: start,
      end: end,
    );
    if (saved == null || !mounted) return null;
    final event = saved.event?.summary;
    if (event != null) {
      cubit.adoptEvent(event);
      return event;
    }
    // A new series answers with the series: its first occurrence is read.
    final id = saved.eventId;
    return id == null ? null : cubit.readEvent(id);
  }

  /// The "+" of the week, the day and the month, and a day's menu: a new
  /// event, or a shift on [day] (the day in focus without one) at the next
  /// full hour for an hour, placed like a sweep. The way to plan without
  /// dragging, for a keyboard and a screen reader.
  Future<void> _addMenu(Rect? anchor, {DateTime? day}) async {
    final picked = await showGlassOptions<String>(
      context,
      title: context.t('shifts.calendar.add'),
      anchorRect: anchor,
      options: [
        (
          value: 'event',
          child: _ChoiceRow(
            icon: LucideIcons.calendarPlus,
            title: context.t('shifts.calendar.newEvent'),
          ),
        ),
        (
          value: 'shift',
          child: _ChoiceRow(
            icon: LucideIcons.clockPlus,
            title: context.t('shifts.calendar.newShift'),
          ),
        ),
      ],
    );
    if (picked == null || !mounted) return;
    final on = day ?? _cubit.state.focused;
    if (picked == 'event') {
      await _newEvent(day: on);
      return;
    }
    final hour = (_now.hour + 1).clamp(0, 23);
    final start = DateTime(on.year, on.month, on.day, hour);
    final target = _cubit.createTarget(
      start,
      start.add(const Duration(hours: 1)),
      wholeDay: true,
    );
    await _place(target, anchor);
  }

  Future<void> _pickProject(Rect? anchor) async {
    if (anchor == null) return;
    final cubit = _cubit;
    if (cubit.state.projectId != null) {
      final choice = await showGlassMenu<String>(
        context: context,
        anchorRect: anchor,
        value: 'current',
        items: [
          GlassMenuItem(
            value: 'all',
            label: context.t('shifts.events.allProjects'),
            leading: Icon(
              LucideIcons.layers,
              size: 16,
              color: AppColors.inkSoft,
            ),
          ),
          GlassMenuItem(
            value: 'pick',
            label: context.t('shifts.events.pickProject'),
            leading: Icon(
              LucideIcons.folder,
              size: 16,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      );
      if (choice == null || !mounted) return;
      if (choice == 'all') return cubit.setProject(null);
    }
    if (!mounted) return;
    final picked = await showProjectPicker(
      context,
      anchorRect: anchor,
      selected: {?cubit.state.projectId},
      titleKey: 'shifts.events.pickProject',
      multi: false,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    cubit.setProject(picked.first.id, name: picked.first.name);
  }

  Future<void> _pickSpan(Rect? anchor) async {
    if (anchor == null) return;
    final cubit = _cubit;
    final picked = await showGlassMenu<ShiftCalendarSpan>(
      context: context,
      anchorRect: anchor,
      value: cubit.state.span,
      items: [
        GlassMenuItem(
          value: ShiftCalendarSpan.week,
          label: context.t('shifts.calendar.week'),
          leading: Icon(
            LucideIcons.calendarDays,
            size: 16,
            color: AppColors.inkSoft,
          ),
        ),
        GlassMenuItem(
          value: ShiftCalendarSpan.month,
          label: context.t('shifts.calendar.month'),
          leading: Icon(
            LucideIcons.calendar,
            size: 16,
            color: AppColors.inkSoft,
          ),
        ),
      ],
    );
    if (picked != null) cubit.setSpan(picked);
  }

  void _focusDay(DateTime day) {
    _cubit.focus(day);
    _jumpPager(day);
  }

  void _jumpPager(DateTime day) {
    if (!_pager.hasClients) return;
    final page =
        _kOriginPage +
        DateTime.utc(day.year, day.month, day.day)
            .difference(DateTime.utc(_origin.year, _origin.month, _origin.day))
            .inDays;
    if (_pager.page?.round() != page) _pager.jumpToPage(page);
  }

  DateTime _dayOfPage(int page) => addDays(_origin, page - _kOriginPage);

  void _step(int direction, {required bool compact}) {
    final cubit = _cubit;
    cubit.step(direction, byDay: compact);
    if (cubit.state.span == ShiftCalendarSpan.month) {
      setState(() => _jump++);
    } else if (compact) {
      _jumpPager(cubit.state.focused);
    }
  }

  void _today() {
    _cubit.today(_now);
    setState(() => _jump++);
    _jumpPager(_now);
  }

  // --- the page -------------------------------------------------------------

  Widget _projectPill(ShiftCalendarState state) => GlassFilterPill(
    icon: LucideIcons.folder,
    label: state.projectId == null
        ? context.t('shifts.events.allProjects')
        : state.projectName ?? context.t('shifts.calendar.oneProject'),
    active: state.projectId != null,
    onTap: (anchor) => unawaited(_pickProject(anchor)),
  );

  /// On a phone the dock holds three controls in one row; the label would run
  /// past the edge, so there the switch is its glyph in its own docked bar,
  /// with the label as tooltip and for the screen reader.
  Widget _shortChip(ShiftCalendarState state, {bool compact = false}) {
    final chip = GlassSwitchChip(
      label: context.t('shifts.event.onlyUnderstaffed'),
      icon: LucideIcons.triangleAlert,
      iconOnly: compact,
      active: state.understaffedOnly,
      onTap: _cubit.toggleUnderstaffed,
    );
    if (!compact) return chip;
    return GlassSwitchBar(
      compact: true,
      maxWidth: kGlassControlHeight * 2,
      chips: [chip],
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return BlocConsumer<ShiftCalendarCubit, ShiftCalendarState>(
      listenWhen: (a, b) =>
          a.span != b.span ||
          dayKey(a.focused) != dayKey(b.focused) ||
          a.projectId != b.projectId,
      listener: (context, state) => _syncRoute(state),
      buildWhen: (a, b) =>
          a.revision != b.revision ||
          a.span != b.span ||
          a.focused != b.focused ||
          a.projectId != b.projectId ||
          a.projectName != b.projectName ||
          a.understaffedOnly != b.understaffedOnly ||
          a.loading.isEmpty != b.loading.isEmpty ||
          a.marksLoading.isEmpty != b.marksLoading.isEmpty ||
          a.plannable != b.plannable,
      builder: (context, state) => PageChrome(
        bottom: compact
            ? ShiftsDock(
                current: ShiftsView.calendar,
                filters: [
                  _projectPill(state),
                  _shortChip(state, compact: true),
                ],
              )
            : null,
        bottomHeight: compact ? kGlassDockRow : 0,
        contentMax: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact)
              ShiftsHead(
                current: ShiftsView.calendar,
                filters: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _projectPill(state),
                    // Glass pills like the project filter beside them: the
                    // filter lights while it holds, the span pill names the
                    // view it switches to, so in the month it reads "Woche".
                    GlassFilterPill(
                      icon: LucideIcons.triangleAlert,
                      label: context.t('shifts.event.onlyUnderstaffed'),
                      active: state.understaffedOnly,
                      chevron: false,
                      onTap: (_) => _cubit.toggleUnderstaffed(),
                    ),
                    GlassFilterPill(
                      icon: state.span == ShiftCalendarSpan.month
                          ? LucideIcons.calendarDays
                          : LucideIcons.calendar,
                      label: context.t(
                        state.span == ShiftCalendarSpan.month
                            ? 'shifts.calendar.week'
                            : 'shifts.calendar.month',
                      ),
                      active: false,
                      chevron: false,
                      onTap: (_) => _cubit.setSpan(
                        state.span == ShiftCalendarSpan.month
                            ? ShiftCalendarSpan.week
                            : ShiftCalendarSpan.month,
                      ),
                    ),
                    if (state.canCreate)
                      _AddPill(onTap: (anchor) => unawaited(_addMenu(anchor))),
                  ],
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.pageGutter,
                compact ? context.topGutter + 8 : 0,
                context.pageGutter,
                8,
              ),
              child: _NavRow(
                label: _rangeLabel(state, compact),
                onPrevious: () => _step(-1, compact: compact),
                onNext: () => _step(1, compact: compact),
                onToday: _today,
                spanLabel: compact
                    ? context.t(
                        state.span == ShiftCalendarSpan.month
                            ? 'shifts.calendar.month'
                            : 'shifts.calendar.week',
                      )
                    : null,
                onSpan: compact
                    ? (anchor) => unawaited(_pickSpan(anchor))
                    : null,
                // On a phone the "+" sits in this row, beside the span: the
                // docked row scrolls sideways and would hide it past the edge.
                onAdd: compact && state.canCreate
                    ? (anchor) => unawaited(_addMenu(anchor))
                    : null,
                previousLabel: context.t(
                  state.span == ShiftCalendarSpan.month
                      ? 'shifts.calendar.previousMonth'
                      : compact
                      ? 'shifts.calendar.previousDay'
                      : 'shifts.calendar.previousWeek',
                ),
                nextLabel: context.t(
                  state.span == ShiftCalendarSpan.month
                      ? 'shifts.calendar.nextMonth'
                      : compact
                      ? 'shifts.calendar.nextDay'
                      : 'shifts.calendar.nextWeek',
                ),
              ),
            ),
            ..._notices(state, compact),
            if (compact && state.span == ShiftCalendarSpan.week)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  height: kTimeWeekStripWithDots,
                  child: TimeWeekStrip(
                    days: _weekOf(state.focused),
                    focused: state.focused,
                    today: _now,
                    onTap: _focusDay,
                    dotsOn: _dotsOn,
                  ),
                ),
              ),
            if (state.span == ShiftCalendarSpan.month)
              Padding(
                // Wide, the month keeps the page's gutter like the week does;
                // on a phone it runs edge to edge, as the time calendar's.
                padding: EdgeInsets.fromLTRB(
                  compact ? 0 : context.pageGutter,
                  0,
                  compact ? 0 : context.pageGutter,
                  4,
                ),
                child: const MonthWeekdayHeader(),
              ),
            Expanded(
              child: Listener(
                onPointerDown: (e) => _lastPointer = e.position,
                // Where a sweep was let go: the choice of event hangs there.
                onPointerUp: (e) => _lastPointer = e.position,
                child: _body(state, compact),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _notices(ShiftCalendarState state, bool compact) {
    final months = state.span == ShiftCalendarSpan.month
        ? [DateTime(state.focused.year, state.focused.month)]
        : {
            for (final d in _weekOf(state.focused)) DateTime(d.year, d.month),
          }.toList();
    final notes = <Widget>[
      // The month draws counts, which are never cut.
      if (state.span == ShiftCalendarSpan.week && state.truncatedAny(months))
        _Notice(
          icon: LucideIcons.info,
          text: context.t('shifts.calendar.truncated'),
        ),
      if (state.zoneDiffers(_deviceZone))
        _Notice(
          icon: LucideIcons.globe,
          text: context.t('shifts.calendar.ownZone'),
        ),
    ];
    return [
      for (final note in notes)
        Padding(
          padding: EdgeInsets.fromLTRB(
            context.pageGutter,
            0,
            context.pageGutter,
            8,
          ),
          child: note,
        ),
    ];
  }

  String _rangeLabel(ShiftCalendarState state, bool compact) {
    final f = state.focused;
    if (state.span == ShiftCalendarSpan.month) {
      return MaterialLocalizations.of(context).formatMonthYear(f);
    }
    if (compact) return dayLabel(context, f);
    final week = _weekOf(f);
    return context.t(
      'shifts.time.span',
      variables: {
        'from': dayLabel(context, week.first),
        'to': dayLabel(context, week.last),
      },
    );
  }

  Widget _body(ShiftCalendarState state, bool compact) {
    final monthSpan = state.span == ShiftCalendarSpan.month;
    final nothingHeld = monthSpan ? state.marks.isEmpty : state.months.isEmpty;
    final failed = monthSpan ? state.marksFailed : state.failed;
    if (nothingHeld &&
        (monthSpan ? state.marksLoading : state.loading).isNotEmpty) {
      return const Center(child: HiveLoader(size: 44));
    }
    final failure = failed[monthKey(state.focused)];
    if (nothingHeld && failure != null) {
      return ListView(
        padding: context.pagePadding,
        children: [
          HiveEmptyState(
            title: context.t('shifts.loadFailed'),
            message: context.t(failure),
            action: GhostButton(
              label: context.t('common.retry'),
              icon: LucideIcons.refreshCw,
              onPressed: () => unawaited(_cubit.retry(state.focused)),
            ),
          ),
        ],
      );
    }
    if (state.span == ShiftCalendarSpan.month) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 0 : context.pageGutter,
        ),
        child: TimeMonthScroller(
          anchor: DateTime(state.focused.year, state.focused.month),
          jump: _jump,
          revision: state.revision,
          now: _now,
          itemsForDay: (_) => const [],
          marksOnly: true,
          dotsOn: _dotsOn,
          failureFor: (key) => state.marksFailed[key],
          onNeedMonths: (months) => unawaited(_cubit.ensureMonths(months)),
          onMonthChanged: (_) {},
          onTapDay: (day) {
            _cubit.openDay(day);
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _jumpPager(day),
            );
          },
          onRetryMonth: (month) => unawaited(_cubit.retry(month)),
          // A planner's "+" in the day, shown on hover where there is a
          // pointer to hover with; held or right-clicked, the same menu.
          onDayMenu: state.canCreate
              ? (day, anchor) => unawaited(_addMenu(anchor, day: day))
              : null,
          onAddOnDay: state.canCreate && !compact
              ? (day, anchor) => unawaited(_addMenu(anchor, day: day))
              : null,
          addLabel: (day) => context.t(
            'shifts.calendar.addOn',
            variables: {
              'date': MaterialLocalizations.of(context).formatFullDate(day),
            },
          ),
        ),
      );
    }
    final grid = compact
        ? PageView.builder(
            controller: _pager,
            onPageChanged: (page) => _cubit.focus(_dayOfPage(page)),
            itemBuilder: (context, page) {
              final day = _dayOfPage(page);
              return _grid(_dayList(day), state, single: true);
            },
          )
        : _grid(_weekOf(state.focused), state, single: false);
    final empty =
        !state.loading.contains(monthKey(state.focused)) &&
        _weekOf(state.focused).every((d) => _cubit.shiftsOn(d).isEmpty);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 0 : context.pageGutter,
        4,
        compact ? 0 : context.pageGutter,
        compact ? 0 : context.pageGutter,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                compact ? 0 : AppTheme.radiusCard,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // Opaque on purpose. At 78 % the page behind had to be
                  // blended into every scrolled frame of the full grid, which
                  // cost the week about 4 ms raster p90 on a 60 Hz MacBook
                  // (19.9 to 16.2 ms, integration_test/shifts_perf_test.dart).
                  color: AppColors.surface,
                  border: compact
                      ? null
                      : Border.all(color: AppColors.hairline),
                  borderRadius: BorderRadius.circular(
                    compact ? 0 : AppTheme.radiusCard,
                  ),
                ),
                child: grid,
              ),
            ),
          ),
          if (empty)
            Positioned(
              left: 0,
              right: 0,
              top: 80,
              child: IgnorePointer(
                child: Center(
                  child: _Notice(
                    icon: LucideIcons.calendarX,
                    text: context.t(
                      state.understaffedOnly
                          ? 'shifts.calendar.noneShort'
                          : 'shifts.calendar.none',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _grid(
    List<DateTime> days,
    ShiftCalendarState state, {
    required bool single,
  }) {
    final planner = state.plannable.isNotEmpty;
    final cubit = _cubit;
    final create = state.canCreate;
    final scope = state.plannableInScope;
    // The week, also under a phone's single day: the day opens where its
    // week does, and swiping within the week does not jump.
    final week = _weekOf(days.first);
    return TimeGrid(
      days: days,
      layers: _layersFor(days),
      now: _now,
      metrics: const TimeGridMetrics(hourExtent: 52),
      showHeadings: !single,
      minColumnWidth: single ? 0 : kTimeGridMinColumn,
      // An hour before the week's first shift, once the week has arrived,
      // and again for every week turned to (HIN-166).
      initialScrollHour: cubit.scrollHourFor(week),
      scrollKey: (dayKey(week.first), cubit.holds(week)),
      onTap: _openShift,
      // Moving is for planners, and only blocks of their projects are movable
      // at all.
      onMoved: planner ? (item, span) => unawaited(_moved(item, span)) : null,
      // Sweeping empty canvas plans a shift, for a planner only (HIN-166).
      onCreate: create ? (span) => unawaited(_createFrom(span)) : null,
      onDayMenu: create && !single
          ? (day, anchor) => unawaited(_addMenu(anchor, day: day))
          : null,
      createTint: scope.length == 1
          ? shiftTint(scope.first)
          : AppColors.accentSoft,
    );
  }
}

/// The "+" of the calendar (HIN-166): a glass pill with the glyph, named
/// "Hinzufügen" as its tooltip and to a screen reader.
class _AddPill extends StatelessWidget {
  const _AddPill({required this.onTap});

  final void Function(Rect? anchor) onTap;

  @override
  Widget build(BuildContext context) {
    final label = context.t('shifts.calendar.add');
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        child: Builder(
          builder: (pill) => GlassPill(
            height: kGlassControlHeight,
            onTap: () => onTap(anchorRectOfContext(pill)),
            child: SizedBox(
              width: kGlassControlHeight,
              child: Icon(LucideIcons.plus, size: 16, color: AppColors.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// What "Neues Event mit dieser Zeit" answers with in the choice of event.
class _NewEventChoice {
  const _NewEventChoice();
}

/// One row of a choice: a glyph, a title and a line under it.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: AppColors.inkSoft),
      const SizedBox(width: 10),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: AppType.body,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: AppType.caption,
                  color: AppColors.inkSoft,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.previousLabel,
    required this.nextLabel,
    this.spanLabel,
    this.onSpan,
    this.onAdd,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final String previousLabel;
  final String nextLabel;
  final String? spanLabel;
  final void Function(Rect? anchor)? onSpan;

  /// The phone's "+" (HIN-166); null hides it.
  final void Function(Rect? anchor)? onAdd;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      GlassCircleButton(
        icon: LucideIcons.chevronLeft,
        onTap: onPrevious,
        size: 44,
        iconSize: 18,
        tooltip: previousLabel,
      ),
      GlassCircleButton(
        icon: LucideIcons.chevronRight,
        onTap: onNext,
        size: 44,
        iconSize: 18,
        tooltip: nextLabel,
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: AppType.title,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
      ),
      TextButton.icon(
        onPressed: onToday,
        icon: const Icon(LucideIcons.locateFixed, size: 16),
        label: Text(context.t('shifts.calendar.today')),
      ),
      if (spanLabel != null && onSpan != null)
        Builder(
          builder: (anchor) => TextButton.icon(
            onPressed: () {
              final box = anchor.findRenderObject() as RenderBox?;
              onSpan!(
                box == null || !box.hasSize
                    ? null
                    : box.localToGlobal(Offset.zero) & box.size,
              );
            },
            icon: const Icon(LucideIcons.chevronDown, size: 16),
            label: Text(spanLabel!),
          ),
        ),
      if (onAdd != null)
        Builder(
          builder: (anchor) => GlassCircleButton(
            icon: LucideIcons.plus,
            onTap: () => onAdd!(anchorRectOfContext(anchor)),
            size: 44,
            iconSize: 18,
            tooltip: context.t('shifts.calendar.add'),
          ),
        ),
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      border: Border.all(color: AppColors.accentLine),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Icon(icon, size: 15, color: AppColors.accentInk),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: AppType.label, color: AppColors.ink),
          ),
        ),
      ],
    ),
  );
}
