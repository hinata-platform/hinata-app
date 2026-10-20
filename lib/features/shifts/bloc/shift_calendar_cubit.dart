import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/shift_repository.dart';
import '../../../core/util/dates.dart' show addDays;
import '../../../core/widgets/time_grid/time_month_layout.dart'
    show dayKey, monthKey;
import 'shift_changes.dart';

/// How much of the calendar is on screen: a week (on a phone, one day of it
/// under the week strip) or a month.
enum ShiftCalendarSpan {
  week,
  month;

  static ShiftCalendarSpan parse(String? value) =>
      value == 'month' ? month : week;
}

/// What a month answered with, or why it did not.
class ShiftCalendarState extends Equatable {
  const ShiftCalendarState({
    required this.focused,
    this.span = ShiftCalendarSpan.week,
    this.projectId,
    this.projectName,
    this.understaffedOnly = false,
    this.months = const {},
    this.failed = const {},
    this.loading = const {},
    this.plannable = const {},
    this.revision = 0,
    this.moving = const {},
  });

  /// The day in focus: the day a phone shows, the week a wide window shows,
  /// the month the month scroller centres on.
  final DateTime focused;
  final ShiftCalendarSpan span;

  /// The project the calendar is narrowed to; null for every visible one.
  final String? projectId;

  /// Its name for the pill, once known.
  final String? projectName;

  /// The "Nur unterbesetzt" filter, applied to the months already held.
  final bool understaffedOnly;

  /// The months held, by [monthKey]. One cache for week, day and month.
  final Map<int, ShiftCalendar> months;

  /// Months that could not be read, by [monthKey], as a message key.
  final Map<int, String> failed;

  /// Months asked for and not answered yet.
  final Set<int> loading;

  /// The projects the caller plans, from every month read.
  final Set<String> plannable;

  /// Bumped whenever what a day shows would change: a month arrived, the
  /// filter flipped. What the views memoise is keyed on it.
  final int revision;

  /// Shifts with a move in the air.
  final Set<String> moving;

  bool canPlan(String projectId) => plannable.contains(projectId);

  /// Whether a month on screen was cut at the server's cap.
  bool truncatedAny(Iterable<DateTime> months) =>
      months.any((month) => this.months[monthKey(month)]?.truncated ?? false);

  /// The zone hint is due when any held event runs in another zone than the
  /// one the calendar draws in.
  bool zoneDiffers(String? deviceZone) {
    if (deviceZone == null) return false;
    for (final month in months.values) {
      for (final event in month.events.values) {
        final zone = event.timezone;
        if (zone != null && zone != deviceZone) return true;
      }
    }
    return false;
  }

  ShiftCalendarState copyWith({
    DateTime? focused,
    ShiftCalendarSpan? span,
    String? projectId,
    bool clearProject = false,
    String? projectName,
    bool? understaffedOnly,
    Map<int, ShiftCalendar>? months,
    Map<int, String>? failed,
    Set<int>? loading,
    Set<String>? plannable,
    int? revision,
    Set<String>? moving,
  }) => ShiftCalendarState(
    focused: focused ?? this.focused,
    span: span ?? this.span,
    projectId: clearProject ? null : projectId ?? this.projectId,
    projectName: clearProject ? null : projectName ?? this.projectName,
    understaffedOnly: understaffedOnly ?? this.understaffedOnly,
    months: months ?? this.months,
    failed: failed ?? this.failed,
    loading: loading ?? this.loading,
    plannable: plannable ?? this.plannable,
    revision: revision ?? this.revision,
    moving: moving ?? this.moving,
  );

  @override
  List<Object?> get props => [
    focused,
    span,
    projectId,
    projectName,
    understaffedOnly,
    months,
    failed,
    loading,
    plannable,
    revision,
    moving,
  ];
}

/// What a move came to: the shift as it now stands and who collides, or why
/// it was refused.
class ShiftMoveOutcome extends Equatable {
  const ShiftMoveOutcome.done(this.edit) : errorKey = null;
  const ShiftMoveOutcome.failed(this.errorKey) : edit = null;

  final ShiftEdit? edit;
  final String? errorKey;

  bool get ok => errorKey == null;

  @override
  List<Object?> get props => [edit, errorKey];
}

/// The shift calendar (HIN-160): one month cache for the week, the day and the
/// month, read a month at a time as the reader gets near it.
///
/// Opening reads the month in focus and one either side; scrolling asks for
/// more through [ensureMonths], which never asks for a month it holds or is
/// already reading. A change made anywhere in the module ([ShiftChanges])
/// reads only the months that shift is in again.
class ShiftCalendarCubit extends Cubit<ShiftCalendarState> {
  ShiftCalendarCubit(
    this._shifts, {
    required DateTime focused,
    ShiftCalendarSpan span = ShiftCalendarSpan.week,
    String? projectId,
    Stream<ShiftChange>? changes,
    Future<String?> Function(String projectId)? projectNameOf,
  }) : _projectNameOf = projectNameOf,
       super(
         ShiftCalendarState(
           focused: DateTime(focused.year, focused.month, focused.day),
           span: span,
           projectId: projectId,
         ),
       ) {
    _changes = ShiftChangeDebouncer(_onChanges, changes: changes);
  }

  final ShiftRepository _shifts;
  late final ShiftChangeDebouncer _changes;

  /// Names the project an address narrowed the calendar to, for its pill.
  final Future<String?> Function(String projectId)? _projectNameOf;

  /// Bumped whenever the project changes, so an answer for the old one is
  /// dropped when it lands.
  int _generation = 0;

  /// The filtered shifts of each day, by [dayKey], built once per revision.
  Map<int, List<Shift>>? _byDay;
  int _byDayRevision = -1;

  /// Reads the month in focus and its neighbours, and names the project the
  /// calendar is narrowed to.
  Future<void> start() async {
    final projectId = state.projectId;
    final nameOf = _projectNameOf;
    if (projectId != null && state.projectName == null && nameOf != null) {
      unawaited(_name(projectId, nameOf));
    }
    await ensureMonths(_around(state.focused));
  }

  Future<void> _name(
    String projectId,
    Future<String?> Function(String) nameOf,
  ) async {
    try {
      final name = await nameOf(projectId);
      if (isClosed || name == null || state.projectId != projectId) return;
      emit(state.copyWith(projectName: name));
    } catch (_) {
      // The pill says "Projekt" until the name is known; nothing is lost.
    }
  }

  static List<DateTime> _around(DateTime day) => [
    DateTime(day.year, day.month - 1),
    DateTime(day.year, day.month),
    DateTime(day.year, day.month + 1),
  ];

  /// Reads the months of [months] not held and not on their way.
  Future<void> ensureMonths(List<DateTime> months) async {
    final wanted = <int, DateTime>{};
    for (final month in months) {
      final key = monthKey(month);
      if (state.months.containsKey(key) ||
          state.loading.contains(key) ||
          state.failed.containsKey(key)) {
        continue;
      }
      wanted[key] = DateTime(month.year, month.month);
    }
    if (wanted.isEmpty) return;
    emit(state.copyWith(loading: {...state.loading, ...wanted.keys}));
    await Future.wait([
      for (final entry in wanted.entries) _read(entry.key, entry.value),
    ]);
  }

  Future<void> _read(int key, DateTime month) async {
    final generation = _generation;
    try {
      final answer = await _shifts.calendar(
        from: month,
        to: DateTime(month.year, month.month + 1),
        projectId: state.projectId,
      );
      if (isClosed || generation != _generation) return;
      emit(
        state.copyWith(
          months: {...state.months, key: answer},
          failed: {...state.failed}..remove(key),
          loading: {...state.loading}..remove(key),
          plannable: {...state.plannable, ...answer.plannableProjectIds},
          revision: state.revision + 1,
        ),
      );
    } on ApiFailure catch (failure) {
      _fail(generation, key, failure.message);
    } catch (_) {
      _fail(generation, key, 'errors.unexpected');
    }
  }

  void _fail(int generation, int key, String message) {
    if (isClosed || generation != _generation) return;
    emit(
      state.copyWith(
        failed: {...state.failed, key: message},
        loading: {...state.loading}..remove(key),
        revision: state.revision + 1,
      ),
    );
  }

  /// Asks for a month that failed again.
  Future<void> retry(DateTime month) {
    emit(state.copyWith(failed: {...state.failed}..remove(monthKey(month))));
    return ensureMonths([month]);
  }

  /// Reads [months] again even though they are held: after a change that
  /// touched them. The old answer stays on screen until the new one lands.
  Future<void> refresh(Iterable<DateTime> months) async {
    final keys = {
      for (final m in months) monthKey(m): DateTime(m.year, m.month),
    };
    emit(state.copyWith(loading: {...state.loading, ...keys.keys}));
    await Future.wait([
      for (final entry in keys.entries) _read(entry.key, entry.value),
    ]);
  }

  /// Puts [day] in focus and reads what it needs.
  void focus(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (dayKey(d) == dayKey(state.focused)) return;
    emit(state.copyWith(focused: d));
    unawaited(ensureMonths(_around(d)));
  }

  /// One step back or on: a day on a phone, a week on a wide window, a month
  /// in the month.
  void step(int direction, {required bool byDay}) {
    final f = state.focused;
    focus(switch (state.span) {
      ShiftCalendarSpan.month => DateTime(f.year, f.month + direction, 1),
      ShiftCalendarSpan.week => addDays(f, byDay ? direction : 7 * direction),
    });
  }

  void today([DateTime? now]) => focus(now ?? DateTime.now());

  void setSpan(ShiftCalendarSpan span) {
    if (span == state.span) return;
    emit(state.copyWith(span: span));
  }

  /// A day tapped in the month: that day, in the week span.
  void openDay(DateTime day) {
    emit(state.copyWith(span: ShiftCalendarSpan.week));
    focus(day);
  }

  void toggleUnderstaffed() => emit(
    state.copyWith(
      understaffedOnly: !state.understaffedOnly,
      revision: state.revision + 1,
    ),
  );

  /// Narrows the calendar to [projectId], or widens it again with null. The
  /// cache belongs to the old scope and goes with it.
  void setProject(String? projectId, {String? name}) {
    if (projectId == state.projectId) {
      if (name != null && name != state.projectName) {
        emit(state.copyWith(projectName: name));
      }
      return;
    }
    _generation++;
    emit(
      ShiftCalendarState(
        focused: state.focused,
        span: state.span,
        projectId: projectId,
        projectName: projectId == null ? null : name,
        understaffedOnly: state.understaffedOnly,
        revision: state.revision + 1,
      ),
    );
    unawaited(start());
  }

  /// The shifts drawn on [day], after the filter: every shift touching it.
  List<Shift> shiftsOn(DateTime day) => _index()[dayKey(day)] ?? const [];

  Map<int, List<Shift>> _index() {
    final cached = _byDay;
    if (cached != null && _byDayRevision == state.revision) return cached;
    final index = <int, List<Shift>>{};
    final seen = <String>{};
    for (final month in state.months.values) {
      for (final shift in month.shifts) {
        if (!seen.add(shift.id)) continue;
        if (state.understaffedOnly && !_short(shift)) continue;
        var day = DateTime(
          shift.startsAt.year,
          shift.startsAt.month,
          shift.startsAt.day,
        );
        // A shift past midnight is on both days; a day-long one at most on two.
        final last = shift.endsAt.subtract(const Duration(microseconds: 1));
        for (var i = 0; i < 2 && !day.isAfter(last); i++) {
          (index[dayKey(day)] ??= []).add(shift);
          day = addDays(day, 1);
        }
      }
    }
    _byDay = index;
    _byDayRevision = state.revision;
    return index;
  }

  static bool _short(Shift shift) =>
      shift.coverage.state == CoverageState.under && !shift.cancelled;

  /// The event a held shift belongs to.
  ShiftEventHead? eventOf(Shift shift) {
    for (final month in state.months.values) {
      final head = month.events[shift.eventId];
      if (head != null) return head;
    }
    return null;
  }

  /// Moves [shift] to [start]..[end] (a planner's drag, once confirmed), and
  /// reads the months it left and the ones it landed in again. On an
  /// occurrence of a series [scope] says which occurrences move; all later
  /// ones mean every month held is read again.
  Future<ShiftMoveOutcome> move(
    Shift shift,
    DateTime start,
    DateTime end, {
    ShiftScope? scope,
  }) async {
    if (state.moving.contains(shift.id)) {
      return const ShiftMoveOutcome.failed('shifts.action.busy');
    }
    emit(state.copyWith(moving: {...state.moving, shift.id}));
    try {
      final edit = await _shifts.updateShift(shift.id, {
        'startsAt': start.toUtc().toIso8601String(),
        'endsAt': end.toUtc().toIso8601String(),
      }, scope: scope);
      if (isClosed) return ShiftMoveOutcome.done(edit);
      final all = scope == ShiftScope.future;
      ShiftChanges.instance.notify(
        ShiftChange(
          shiftId: all ? '' : shift.id,
          shift: edit.shift,
          origin: this,
        ),
      );
      unawaited(
        refresh({
          shift.startsAt,
          start,
          if (all)
            for (final key in state.months.keys)
              DateTime(key ~/ 100, key % 100),
        }),
      );
      return ShiftMoveOutcome.done(edit);
    } on ApiFailure catch (failure) {
      final code = failure.details['code'];
      return ShiftMoveOutcome.failed(
        code != null && code.startsWith('error.shifts.')
            ? code
            : failure.message,
      );
    } catch (_) {
      return const ShiftMoveOutcome.failed('errors.unexpected');
    } finally {
      if (!isClosed) {
        emit(state.copyWith(moving: {...state.moving}..remove(shift.id)));
      }
    }
  }

  void _onChanges(List<ShiftChange> changes) {
    final touched = <DateTime>{};
    for (final change in changes) {
      if (identical(change.origin, this)) continue;
      final shift = change.shift;
      if (shift != null) touched.add(shift.startsAt);
      for (final month in state.months.values) {
        for (final held in month.shifts) {
          if (held.id == change.shiftId) touched.add(held.startsAt);
        }
      }
      // An event-wide change names no single shift: everything held is
      // read again, which is still one request per month.
      if (change.shiftId.isEmpty) {
        touched.addAll([
          for (final key in state.months.keys) DateTime(key ~/ 100, key % 100),
        ]);
      }
    }
    if (touched.isEmpty) return;
    unawaited(refresh(touched));
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
