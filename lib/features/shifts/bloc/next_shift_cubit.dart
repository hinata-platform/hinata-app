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
    this.waitingFailed = false,
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

  /// The waiting lists could not be read: [waiting] is what was held before,
  /// and the page says that it may be out of date.
  final bool waitingFailed;
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
    bool? waitingFailed,
    String? errorKey,
  }) => NextShiftState(
    loading: loading ?? this.loading,
    loaded: loaded ?? this.loaded,
    next: clearNext ? null : (next ?? this.next),
    nextDetail: clearDetail ? null : (nextDetail ?? this.nextDetail),
    open: open ?? this.open,
    waiting: waiting ?? this.waiting,
    waitingFailed: waitingFailed ?? this.waitingFailed,
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
    waitingFailed,
    errorKey,
  ];
}

/// A change made anywhere in the module is put in from the shift the answer
/// carried. What that cannot settle is read again on its own, and only while
/// the view is on screen: the next shift when the caller's places moved, the
/// waiting lists when they joined one, everything after an event-wide change.
class NextShiftCubit extends Cubit<NextShiftState> with ShiftStaleWhileHidden {
  NextShiftCubit(
    this._shifts, {
    this.onNext,
    DateTime Function()? now,
    Stream<ShiftChange>? changes,
  }) : _now = now ?? DateTime.now,
       super(const NextShiftState()) {
    _changes = ShiftChangeDebouncer(_onChanges, changes: changes);
  }

  final ShiftRepository _shifts;
  final DateTime Function() _now;

  /// Called with each fresh answer, for the offline snapshot.
  final void Function(MyShift? next)? onNext;
  late final ShiftChangeDebouncer _changes;
  int _token = 0;

  /// What a change left to read again, until [refreshStale] does.
  bool _staleAll = false;
  bool _staleNext = false;
  bool _staleWaiting = false;

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
        // The waiting lists must not take the caller's shifts down either,
        // but a failure is said: whoever waits must not think they do not.
        _shifts.myWaitingShifts().then<List<MyShift>?>(
          (w) => w,
          onError: (Object _) => null,
        ),
      ]);
      if (isClosed || token != _token) return;
      final next = results[0] as MyShift?;
      final open = results[1] as ShiftCalendar;
      final fresh = results[2] as List<MyShift>?;
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
          waiting: fresh == null
              ? state.waiting
              : [
                  for (final w in fresh)
                    if (w.status == ShiftAssignmentStatus.waiting) w,
                ],
          waitingFailed: fresh == null,
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

  /// Reads the next shift alone, and its people when it is another one or
  /// [withDetail] says so.
  Future<void> _reloadNext({bool withDetail = false}) async {
    final token = _token;
    try {
      final next = await _shifts.nextShift();
      if (isClosed || token != _token) return;
      final same = state.next?.shift.id == next?.shift.id;
      emit(
        state.copyWith(
          next: next,
          clearNext: next == null,
          clearDetail: !same,
          errorKey: state.errorKey,
        ),
      );
      onNext?.call(next);
      if (next != null && (!same || withDetail)) {
        unawaited(_loadDetail(next.shift.id, token));
      }
    } catch (_) {
      // What is shown stands until the next full read.
    }
  }

  /// Reads the waiting lists alone.
  Future<void> _reloadWaiting() async {
    final token = _token;
    try {
      final fresh = await _shifts.myWaitingShifts();
      if (isClosed || token != _token) return;
      emit(
        state.copyWith(
          waiting: [
            for (final w in fresh)
              if (w.status == ShiftAssignmentStatus.waiting) w,
          ],
          waitingFailed: false,
          errorKey: state.errorKey,
        ),
      );
    } catch (_) {
      if (isClosed || token != _token) return;
      emit(state.copyWith(waitingFailed: true, errorKey: state.errorKey));
    }
  }

  void _onChanges(List<ShiftChange> changes) {
    if (isClosed) return;
    var detail = false;
    for (final change in changes) {
      final shift = change.shift;
      if (shift == null || change.shiftId.isEmpty) {
        _staleAll = true;
        continue;
      }
      final next = state.next;
      final isNext = next != null && next.shift.id == shift.id;
      final wasWaiting = state.waiting.any((w) => w.shift.id == shift.id);
      applyShift(shift);
      if (shift.waiting && !wasWaiting) _staleWaiting = true;
      if (!shift.waiting && wasWaiting) _dropWaitingShift(shift.id);
      if (isNext) {
        // Given away or moved: which one is next, only the server says. Still
        // the caller's: the people on it may have changed.
        if (!shift.mine || shift.startsAt != next.shift.startsAt) {
          _staleNext = true;
        } else {
          detail = true;
        }
      } else if (shift.mine &&
          (next == null || shift.startsAt.isBefore(next.shift.startsAt))) {
        _staleNext = true;
      }
    }
    if (detail && !_staleNext && !_staleAll) {
      final next = state.next;
      if (next != null) unawaited(_loadDetail(next.shift.id, _token));
    }
    if (_staleAll || _staleNext || _staleWaiting) markStale();
  }

  @override
  void refreshStale() {
    final all = _staleAll;
    final next = _staleNext;
    final waiting = _staleWaiting;
    _staleAll = _staleNext = _staleWaiting = false;
    if (all) {
      unawaited(load());
      return;
    }
    if (next) unawaited(_reloadNext());
    if (waiting) unawaited(_reloadWaiting());
  }

  void _dropWaitingShift(String shiftId) => emit(
    state.copyWith(
      waiting: [
        for (final w in state.waiting)
          if (w.shift.id != shiftId) w,
      ],
      errorKey: state.errorKey,
    ),
  );

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
            ? _withShift(next, shift)
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

  /// The hero's place with the shift as it now stands, and its status when
  /// the shift says (a confirmation ends the deadline).
  static MyShift _withShift(MyShift next, Shift shift) {
    final status = shift.mine ? shift.myStatus ?? next.status : next.status;
    return next.copyWith(
      shift: shift,
      status: status,
      clearConfirmBy: status == ShiftAssignmentStatus.confirmed,
    );
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
