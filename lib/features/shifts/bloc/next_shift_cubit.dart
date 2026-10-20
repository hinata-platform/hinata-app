import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/shift_repository.dart';
import 'shift_changes.dart';

/// The head and the foot of "Meine Schichten": the next shift for the hero
/// card, the people on it, the caller's waiting lists (HIN-162), and up to
/// three open shifts in the caller's projects over the next two weeks.
class NextShiftState extends Equatable {
  const NextShiftState({
    this.loading = false,
    this.loaded = false,
    this.next,
    this.nextDetail,
    this.open = const ShiftCalendar(),
    this.waiting = const [],
    this.errorKey,
  });

  final bool loading;

  /// Whether an answer has arrived at least once.
  final bool loaded;
  final MyShift? next;

  /// The next shift's detail, for the names of the people on it. Null while
  /// it loads or when it could not be read; the hero then counts instead.
  final ShiftDetail? nextDetail;
  final ShiftCalendar open;

  /// The shifts the caller waits for, by start; never in the hero.
  final List<MyShift> waiting;
  final String? errorKey;

  NextShiftState copyWith({
    bool? loading,
    bool? loaded,
    MyShift? next,
    bool clearNext = false,
    ShiftDetail? nextDetail,
    bool clearDetail = false,
    ShiftCalendar? open,
    List<MyShift>? waiting,
    String? errorKey,
  }) => NextShiftState(
    loading: loading ?? this.loading,
    loaded: loaded ?? this.loaded,
    next: clearNext ? null : (next ?? this.next),
    nextDetail: clearDetail ? null : (nextDetail ?? this.nextDetail),
    open: open ?? this.open,
    waiting: waiting ?? this.waiting,
    errorKey: errorKey,
  );

  @override
  List<Object?> get props => [
    loading,
    loaded,
    next,
    nextDetail,
    open,
    waiting,
    errorKey,
  ];
}

class NextShiftCubit extends Cubit<NextShiftState> {
  NextShiftCubit(
    this._shifts, {
    this.onNext,
    DateTime Function()? now,
    Stream<ShiftChange>? changes,
  }) : _now = now ?? DateTime.now,
       super(const NextShiftState()) {
    _changes = ShiftChangeDebouncer((_) => unawaited(load()), changes: changes);
  }

  final ShiftRepository _shifts;
  final DateTime Function() _now;

  /// Called with each fresh answer, for the offline snapshot.
  final void Function(MyShift? next)? onNext;
  late final ShiftChangeDebouncer _changes;
  int _token = 0;

  /// How far ahead the open shifts are looked for.
  static const openWindowDays = 14;

  Future<void> load() async {
    final token = ++_token;
    emit(state.copyWith(loading: true, errorKey: state.errorKey));
    final now = _now();
    try {
      final results = await Future.wait<Object?>([
        _shifts.nextShift(),
        _shifts
            .openShifts(
              from: now,
              to: now.add(const Duration(days: openWindowDays)),
              limit: 3,
            )
            // The open shifts are a suggestion; failing to read them must not
            // take the caller's own shifts down with them.
            .catchError((Object _) => const ShiftCalendar()),
        // The same for the waiting lists: an older server has no such route.
        _shifts.myWaitingShifts().catchError((Object _) => const <MyShift>[]),
      ]);
      if (isClosed || token != _token) return;
      final next = results[0] as MyShift?;
      final open = results[1] as ShiftCalendar;
      final waiting = results[2] as List<MyShift>;
      final keepDetail = state.nextDetail?.shift.id == next?.shift.id;
      emit(
        NextShiftState(
          loaded: true,
          next: next,
          nextDetail: keepDetail ? state.nextDetail : null,
          open: ShiftCalendar(
            // Never offer a shift the caller is already on or waits for.
            shifts: [
              for (final s in open.shifts)
                if (!s.mine && !s.waiting) s,
            ],
            events: open.events,
            truncated: open.truncated,
          ),
          waiting: [
            for (final w in waiting)
              if (w.status == ShiftAssignmentStatus.waiting) w,
          ],
        ),
      );
      onNext?.call(next);
      if (next != null) unawaited(_loadDetail(next.shift.id, token));
    } on ApiFailure catch (failure) {
      if (isClosed || token != _token) return;
      emit(state.copyWith(loading: false, errorKey: failure.message));
    } catch (_) {
      if (isClosed || token != _token) return;
      emit(state.copyWith(loading: false, errorKey: 'errors.unexpected'));
    }
  }

  Future<void> _loadDetail(String shiftId, int token) async {
    try {
      final detail = await _shifts.shift(shiftId);
      if (isClosed || token != _token) return;
      emit(state.copyWith(nextDetail: detail, errorKey: state.errorKey));
    } catch (_) {
      // The hero counts the others instead of naming them.
    }
  }

  /// Takes a waiting place off the list right away, once it is left.
  void dropWaiting(String assignmentId) => emit(
    state.copyWith(
      waiting: [
        for (final w in state.waiting)
          if (w.assignmentId != assignmentId) w,
      ],
      errorKey: state.errorKey,
    ),
  );

  /// Puts a changed shift into the open list or the hero right away, before
  /// the reload the change triggers anyway.
  void applyShift(Shift shift) {
    final next = state.next;
    emit(
      state.copyWith(
        next: next != null && next.shift.id == shift.id
            ? next.copyWith(shift: shift)
            : null,
        open: ShiftCalendar(
          shifts: [
            for (final s in state.open.shifts)
              if (s.id != shift.id)
                s
              else if (!shift.mine && !shift.waiting)
                shift,
          ],
          events: state.open.events,
          truncated: state.open.truncated,
        ),
        errorKey: state.errorKey,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
