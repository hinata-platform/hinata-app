import 'dart:async';

import '../../../core/blocs/paged_cubit.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/shift_repository.dart';
import 'shift_changes.dart';

/// "Meine Schichten": the caller's own places from now on, paged (HIN-44).
///
/// Only a fresh first page is handed to [onFirstPage], which is where the
/// offline snapshot is written: a later page appended by scrolling is never
/// stored, so the snapshot stays the first fifty rows and nothing more.
///
/// A change made anywhere in the module is put into the rows held, from the
/// shift the answer carried. Only what cannot be placed from it (a new place,
/// a shift that moved, an event-wide change) reads the held rows again, in
/// one request, and only while the view is on screen.
class MyShiftsCubit extends PagedCubit<MyShift> with ShiftStaleWhileHidden {
  MyShiftsCubit(
    ShiftRepository shifts, {
    this.onFirstPage,
    Stream<ShiftChange>? changes,
    super.pageSize = 25,
  }) : super(
         (page, size) => shifts.myShifts(page: page, size: size),
         keyOf: (row) => row.assignmentId,
       ) {
    _changes = ShiftChangeDebouncer(_onChanges, changes: changes);
  }

  final void Function(List<MyShift> rows)? onFirstPage;
  late final ShiftChangeDebouncer _changes;

  @override
  Future<void> load() async {
    await super.load();
    _recordFirstRows();
  }

  @override
  Future<void> refreshLoaded({int maxRows = 100}) async {
    await super.refreshLoaded(maxRows: maxRows);
    _recordFirstRows();
  }

  void _recordFirstRows() {
    if (isClosed) return;
    if (state.hasData && state.errorKey == null) {
      onFirstPage?.call(state.items);
    }
  }

  @override
  void refreshStale() => unawaited(refreshLoaded());

  void _onChanges(List<ShiftChange> changes) {
    if (isClosed || !state.hasData) return;
    var reread = false;
    for (final change in changes) {
      final shift = change.shift;
      if (shift == null || change.shiftId.isEmpty) {
        reread = true;
        continue;
      }
      MyShift? held;
      for (final row in state.items) {
        if (row.shift.id == shift.id) held = row;
      }
      if (held == null) {
        // A new place of the caller's: where it goes, only the server says.
        if (shift.mine) reread = true;
        continue;
      }
      if (!shift.mine) {
        removeItem(held.assignmentId);
        continue;
      }
      if (shift.startsAt != held.shift.startsAt) reread = true;
      final status = shift.myStatus ?? held.status;
      replaceItem(
        held.copyWith(
          shift: shift,
          status: status,
          clearConfirmBy: status == ShiftAssignmentStatus.confirmed,
        ),
      );
    }
    if (reread) markStale();
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
