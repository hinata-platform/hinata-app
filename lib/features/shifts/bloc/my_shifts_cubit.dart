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
class MyShiftsCubit extends PagedCubit<MyShift> {
  MyShiftsCubit(
    ShiftRepository shifts, {
    this.onFirstPage,
    Stream<ShiftChange>? changes,
    super.pageSize = 25,
  }) : super(
         (page, size) => shifts.myShifts(page: page, size: size),
         keyOf: (row) => row.assignmentId,
       ) {
    _changes = ShiftChangeDebouncer((_) => unawaited(load()), changes: changes);
  }

  final void Function(List<MyShift> rows)? onFirstPage;
  late final ShiftChangeDebouncer _changes;

  @override
  Future<void> load() async {
    await super.load();
    if (isClosed) return;
    if (state.hasData && state.page == 0 && state.errorKey == null) {
      onFirstPage?.call(state.items);
    }
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
