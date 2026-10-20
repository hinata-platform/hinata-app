import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/shift_repository.dart';
import '../shift_zones.dart';
import 'shift_actions_cubit.dart' show ShiftActionsCubit;
import 'shift_changes.dart';

/// What can be wrong with the shift as typed, before anything is sent.
enum ShiftEditorProblem {
  /// Ends when it starts (or before, where it cannot be a night shift).
  endBeforeStart,

  /// Runs outside its event.
  outsideEvent,
}

/// The shift editor's form (HIN-160): a name, a day, from and until, how many
/// are needed and how many may come, and the other days of the event to put
/// the same shift on.
class ShiftEditorState extends Equatable {
  const ShiftEditorState({
    required this.title,
    required this.day,
    required this.fromMinutes,
    required this.toMinutes,
    this.requiredHelpers = 1,
    this.maxHelpers,
    this.extraDays = const {},
    this.saving = false,
    this.errorKey,
    this.errorDetails = const {},
    this.dayErrors = const {},
    this.attempted = false,
  });

  final String title;

  /// The day it starts, a date in the event's zone.
  final DateTime day;

  /// Start and end as minutes after midnight. An end at or before the start
  /// is on the next day: a night shift.
  final int fromMinutes;
  final int toMinutes;

  final int requiredHelpers;

  /// Null: no upper limit.
  final int? maxHelpers;

  /// The other days of the event the same shift goes on.
  final Set<DateTime> extraDays;

  final bool saving;

  /// Why the last save was refused, as a message key.
  final String? errorKey;
  final Map<String, String> errorDetails;

  /// The days of a refused batch, each with why.
  final Map<DateTime, String> dayErrors;

  /// Whether a save was tried, so problems show only after the first try.
  final bool attempted;

  DateTime get startWall => DateTime(
    day.year,
    day.month,
    day.day,
    fromMinutes ~/ 60,
    fromMinutes % 60,
  );

  DateTime get endWall {
    final sameDay = toMinutes > fromMinutes;
    final end = DateTime(
      day.year,
      day.month,
      day.day + (sameDay ? 0 : 1),
      toMinutes ~/ 60,
      toMinutes % 60,
    );
    return end;
  }

  ShiftEditorState copyWith({
    String? title,
    DateTime? day,
    int? fromMinutes,
    int? toMinutes,
    int? requiredHelpers,
    int? maxHelpers,
    bool clearMax = false,
    Set<DateTime>? extraDays,
    bool? saving,
    String? errorKey,
    Map<String, String>? errorDetails,
    Map<DateTime, String>? dayErrors,
    bool? attempted,
    bool clearError = false,
  }) => ShiftEditorState(
    title: title ?? this.title,
    day: day ?? this.day,
    fromMinutes: fromMinutes ?? this.fromMinutes,
    toMinutes: toMinutes ?? this.toMinutes,
    requiredHelpers: requiredHelpers ?? this.requiredHelpers,
    maxHelpers: clearMax ? null : maxHelpers ?? this.maxHelpers,
    extraDays: extraDays ?? this.extraDays,
    saving: saving ?? this.saving,
    errorKey: clearError ? null : errorKey ?? this.errorKey,
    errorDetails: clearError ? const {} : errorDetails ?? this.errorDetails,
    dayErrors: clearError ? const {} : dayErrors ?? this.dayErrors,
    attempted: attempted ?? this.attempted,
  );

  @override
  List<Object?> get props => [
    title,
    day,
    fromMinutes,
    toMinutes,
    requiredHelpers,
    maxHelpers,
    extraDays,
    saving,
    errorKey,
    errorDetails,
    dayErrors,
    attempted,
  ];
}

/// Creates a shift on one or more days of an event, or changes one.
///
/// The times are wall clocks in the event's zone, like everything the event
/// page shows; they become instants only when they are sent. Saving a new
/// shift is always one batch call, so "Auf weitere Tage übernehmen" puts the
/// shift on every chosen day or on none.
class ShiftEditorCubit extends Cubit<ShiftEditorState> {
  ShiftEditorCubit(
    this._shifts, {
    required this.event,
    this.shift,
    DateTime? day,
    ({DateTime start, DateTime end})? wallSpan,
    String? deviceZone,
  }) : assert(day == null || wallSpan == null, 'a day or a span, not both'),
       assert(
         wallSpan == null || wallSpan.end.isAfter(wallSpan.start),
         'a span ends after it starts',
       ),
       _deviceZone = deviceZone,
       super(_initial(event, shift, day, wallSpan));

  final ShiftRepository _shifts;

  /// The event the shift belongs to.
  final ShiftEventSummary event;

  /// The shift being changed; null for a new one.
  final Shift? shift;

  final String? _deviceZone;

  bool get editing => shift != null;

  static DateTime _date(DateTime t) => DateTime(t.year, t.month, t.day);

  static ShiftEditorState _initial(
    ShiftEventSummary event,
    Shift? shift,
    DateTime? day,
    ({DateTime start, DateTime end})? wallSpan,
  ) {
    if (shift != null) {
      final s = shift.startsLocal;
      final e = shift.endsLocal;
      return ShiftEditorState(
        title: shift.title,
        day: _date(s),
        fromMinutes: s.hour * 60 + s.minute,
        toMinutes: e.hour * 60 + e.minute,
        requiredHelpers: shift.requiredHelpers,
        maxHelpers: shift.maxHelpers,
      );
    }
    if (wallSpan case (:final start, :final end)) {
      // A span swept out on the calendar (HIN-166), as wall clocks in the
      // event's zone: exactly that time. Whether it fits into the event is
      // the editor's question, not something cut short here.
      return ShiftEditorState(
        title: '',
        day: _date(start),
        fromMinutes: start.hour * 60 + start.minute,
        toMinutes: end.hour * 60 + end.minute,
      );
    }
    final opens = event.startsLocal;
    final first = _date(opens);
    final chosen = day == null ? first : _date(day);
    final onFirst = chosen == first;
    // A new shift opens where the event does on its first day, three hours
    // long, and at nine on any other; never past the event's end.
    final from = onFirst ? opens.hour * 60 + opens.minute : 9 * 60;
    final to = (from + 180).clamp(0, 24 * 60 - 1);
    return ShiftEditorState(
      title: '',
      day: chosen,
      fromMinutes: from,
      toMinutes: to,
    );
  }

  /// The event's days, in its own zone, first to last.
  List<DateTime> get eventDays {
    final first = _date(event.startsLocal);
    // An event ending at midnight does not reach into that day.
    final endsAt = event.endsLocal.subtract(const Duration(minutes: 1));
    final last = _date(
      endsAt.isBefore(event.startsLocal) ? event.startsLocal : endsAt,
    );
    return [
      for (
        var d = first;
        !d.isAfter(last);
        d = DateTime(d.year, d.month, d.day + 1)
      )
        d,
    ];
  }

  void setTitle(String value) => emit(state.copyWith(title: value));

  void setDay(DateTime day) {
    final d = _date(day);
    emit(
      state.copyWith(
        day: d,
        extraDays: {...state.extraDays}..remove(d),
        clearError: true,
      ),
    );
  }

  void setFrom(int minutes) =>
      emit(state.copyWith(fromMinutes: minutes, clearError: true));

  void setTo(int minutes) =>
      emit(state.copyWith(toMinutes: minutes, clearError: true));

  /// One more or one fewer needed; never below one, never above the limit.
  void stepRequired(int by) {
    final next = (state.requiredHelpers + by).clamp(1, 500);
    final max = state.maxHelpers;
    // Raising the need past the limit raises the limit with it.
    emit(
      state.copyWith(
        requiredHelpers: next,
        maxHelpers: max != null && max < next ? next : max,
        clearError: true,
      ),
    );
  }

  /// One more or one fewer at most. Below the need it cannot go; from "none"
  /// it starts at the need.
  void stepMax(int by) {
    final max = state.maxHelpers;
    if (max == null) {
      if (by > 0) {
        emit(
          state.copyWith(maxHelpers: state.requiredHelpers, clearError: true),
        );
      }
      return;
    }
    final next = max + by;
    if (next < state.requiredHelpers) return;
    emit(state.copyWith(maxHelpers: next.clamp(1, 500), clearError: true));
  }

  bool get canLowerMax =>
      state.maxHelpers != null && state.maxHelpers! > state.requiredHelpers;

  void clearMax() => emit(state.copyWith(clearMax: true, clearError: true));

  void toggleExtraDay(DateTime day) {
    final d = _date(day);
    if (d == state.day) return;
    final days = {...state.extraDays};
    if (!days.remove(d)) days.add(d);
    emit(state.copyWith(extraDays: days, clearError: true));
  }

  /// What is wrong with the shift as typed, or null.
  ShiftEditorProblem? get problem {
    if (state.toMinutes == state.fromMinutes) {
      return ShiftEditorProblem.endBeforeStart;
    }
    if (!_inside(state.day)) return ShiftEditorProblem.outsideEvent;
    return null;
  }

  /// Whether the shift fits into the event when it starts on [day].
  bool _inside(DateTime day) {
    final shifted = state.copyWith(day: day);
    return !shifted.startWall.isBefore(event.startsLocal) &&
        !shifted.endWall.isAfter(event.endsLocal);
  }

  /// The chosen other days on which the shift would not fit into the event.
  Set<DateTime> get extraDaysOutside => {
    for (final d in state.extraDays)
      if (!_inside(d)) d,
  };

  ShiftInput _input() => ShiftInput(
    title: state.title,
    startsAt: ShiftZones.toInstant(
      state.startWall,
      event.timezone,
      _deviceZone,
    ),
    endsAt: ShiftZones.toInstant(state.endWall, event.timezone, _deviceZone),
    requiredHelpers: state.requiredHelpers,
    maxHelpers: state.maxHelpers,
  );

  ShiftInput _before(Shift shift) => ShiftInput(
    title: shift.title,
    startsAt: shift.startsAt,
    endsAt: shift.endsAt,
    requiredHelpers: shift.requiredHelpers,
    maxHelpers: shift.maxHelpers,
  );

  /// Whether saving has to ask which occurrences it applies to: the event is
  /// an occurrence of a series (HIN-161) and something is to be written.
  Future<bool> asksScope() async {
    if (!event.inSeries || problem != null) return false;
    final existing = shift;
    if (existing == null) return true;
    if (event.timezone != null && event.timezone != _deviceZone) {
      await ShiftZones.ensureLoaded();
    }
    return _input().toPatchJson(_before(existing)).isNotEmpty;
  }

  /// Saves; true when it went through. A refusal stays in the state. On an
  /// occurrence of a series [scope] says which occurrences it applies to; a
  /// shift put on several days at once only ever goes on this one.
  Future<bool> save({ShiftScope? scope}) async {
    if (state.saving) return false;
    emit(state.copyWith(attempted: true, clearError: true));
    if (problem != null) return false;
    final outside = extraDaysOutside;
    if (outside.isNotEmpty) {
      emit(
        state.copyWith(
          errorKey: 'error.shifts.batchInvalid',
          dayErrors: {
            for (final d in outside) d: 'error.shifts.shiftOutsideEvent',
          },
        ),
      );
      return false;
    }
    emit(state.copyWith(saving: true));
    try {
      if (event.timezone != null && event.timezone != _deviceZone) {
        await ShiftZones.ensureLoaded();
      }
      final input = _input();
      final existing = shift;
      final inSeries = event.inSeries;
      // A change for every later occurrence names no single shift: every
      // surface of the module reads again.
      final wide = inSeries && scope == ShiftScope.future;
      if (existing == null && wide && state.extraDays.isEmpty) {
        final created = await _shifts.createShift(
          event.id,
          input,
          scope: ShiftScope.future,
        );
        ShiftChanges.instance.notify(
          ShiftChange(shiftId: '', shift: created, origin: this),
        );
      } else if (existing == null) {
        final days = [state.day, ...state.extraDays.toList()..sort()];
        final created = await _shifts.createShifts(
          event.id,
          input,
          days,
          scope: inSeries ? ShiftScope.single : null,
        );
        // Each new shift on its own, so a surface holding the days can put
        // every one of them in from the answer (HIN-166).
        if (created.isEmpty) {
          ShiftChanges.instance.notify(ShiftChange(shiftId: '', origin: this));
        }
        for (final shift in created) {
          ShiftChanges.instance.notify(
            ShiftChange(shiftId: shift.id, shift: shift, origin: this),
          );
        }
      } else {
        final patch = input.toPatchJson(_before(existing));
        if (patch.isNotEmpty) {
          final edit = await _shifts.updateShift(
            existing.id,
            patch,
            scope: inSeries ? scope : null,
          );
          ShiftChanges.instance.notify(
            ShiftChange(
              shiftId: wide ? '' : existing.id,
              shift: edit.shift,
              origin: this,
            ),
          );
        }
      }
      if (!isClosed) emit(state.copyWith(saving: false));
      return true;
    } on ApiFailure catch (failure) {
      if (isClosed) return false;
      final key = ShiftActionsCubit.errorKeyOf(failure);
      emit(
        state.copyWith(
          saving: false,
          errorKey: key,
          errorDetails: failure.details,
          dayErrors: key == 'error.shifts.batchInvalid'
              ? _daysOf(failure.details)
              : const {},
        ),
      );
      return false;
    } catch (_) {
      if (!isClosed) {
        emit(state.copyWith(saving: false, errorKey: 'errors.unexpected'));
      }
      return false;
    }
  }

  /// The failed days of a batch refusal: every detail keyed by a date.
  static Map<DateTime, String> _daysOf(Map<String, String> details) => {
    for (final entry in details.entries)
      if (DateTime.tryParse(entry.key) case final day?
          when entry.key.length == 10)
        DateTime(day.year, day.month, day.day): entry.value,
  };
}
