import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/shift_repository.dart';
import 'shift_changes.dart';

class ShiftEventState extends Equatable {
  const ShiftEventState({
    this.loading = false,
    this.detail,
    this.understaffedOnly = false,
    this.errorKey,
  });

  final bool loading;
  final ShiftEventDetail? detail;

  /// The "Nur unterbesetzt" filter.
  final bool understaffedOnly;
  final String? errorKey;

  /// The shifts the page lists, after the filter.
  List<Shift> get visibleShifts => [
    for (final s in detail?.shifts ?? const <Shift>[])
      if (!understaffedOnly || s.coverage.state == CoverageState.under) s,
  ];

  ShiftEventState copyWith({
    bool? loading,
    ShiftEventDetail? detail,
    bool? understaffedOnly,
    String? errorKey,
  }) => ShiftEventState(
    loading: loading ?? this.loading,
    detail: detail ?? this.detail,
    understaffedOnly: understaffedOnly ?? this.understaffedOnly,
    errorKey: errorKey,
  );

  @override
  List<Object?> get props => [loading, detail, understaffedOnly, errorKey];
}

/// One event with its shifts, for the helper (HIN-44).
class ShiftEventCubit extends Cubit<ShiftEventState> {
  ShiftEventCubit(this._shifts, this.eventId, {Stream<ShiftChange>? changes})
    : super(const ShiftEventState()) {
    _changes = ShiftChangeDebouncer(_onChanges, changes: changes);
  }

  final ShiftRepository _shifts;
  final String eventId;
  late final ShiftChangeDebouncer _changes;

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    try {
      final detail = await _shifts.event(eventId);
      if (isClosed) return;
      emit(state.copyWith(loading: false, detail: detail));
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      emit(state.copyWith(loading: false, errorKey: failure.message));
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(loading: false, errorKey: 'errors.unexpected'));
    }
  }

  void toggleUnderstaffed() =>
      emit(state.copyWith(understaffedOnly: !state.understaffedOnly));

  /// Replaces one row with the shift an action answered with.
  void applyShift(Shift shift) {
    final detail = state.detail;
    if (detail == null || shift.eventId != detail.summary.id) return;
    emit(state.copyWith(detail: detail.withShift(shift)));
  }

  /// Takes the event as an action answered with it (an edit, a cancellation).
  void applyEvent(ShiftEventDetail detail) {
    if (detail.summary.id != eventId) return;
    emit(state.copyWith(detail: detail));
  }

  void _onChanges(List<ShiftChange> changes) {
    final detail = state.detail;
    if (detail == null) return;
    final ours = {for (final s in detail.shifts) s.id};
    // A shift of this event, a new one in it, or a change to events at large.
    final touching = changes.where(
      (c) =>
          ours.contains(c.shiftId) ||
          c.shift?.eventId == eventId ||
          c.shiftId.isEmpty,
    );
    if (touching.isEmpty) return;
    // The rows were replaced as the answers came; the totals and the names in
    // the head are read again once.
    unawaited(load());
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
