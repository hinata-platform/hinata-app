import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/shift_repository.dart';

class ShiftSheetState extends Equatable {
  const ShiftSheetState({
    this.loading = true,
    this.detail,
    this.assignment,
    this.errorKey,
  });

  final bool loading;
  final ShiftDetail? detail;

  /// The caller's place on the shift as far as the sheet knows: what the
  /// opener said, then what the server or the last action said.
  final ShiftAssignmentRef? assignment;
  final String? errorKey;

  @override
  List<Object?> get props => [loading, detail, assignment, errorKey];
}

/// The shift sheet's data: one shift, its event, the people on it, and the
/// caller's own place.
class ShiftSheetCubit extends Cubit<ShiftSheetState> {
  ShiftSheetCubit(this._shifts, this.shiftId, {ShiftAssignmentRef? assignment})
    : super(ShiftSheetState(assignment: assignment));

  final ShiftRepository _shifts;
  final String shiftId;

  Future<void> load() async {
    emit(ShiftSheetState(detail: state.detail, assignment: state.assignment));
    try {
      final detail = await _shifts.shift(shiftId);
      if (isClosed) return;
      emit(
        ShiftSheetState(
          loading: false,
          detail: detail,
          // The server's word wins; a shift that is not the caller's has no
          // place to act on, whatever the opener thought.
          assignment: !detail.shift.mine
              ? null
              : detail.myAssignment ?? state.assignment,
        ),
      );
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      emit(_failed(failure.message));
    } catch (_) {
      if (isClosed) return;
      emit(_failed('errors.unexpected'));
    }
  }

  ShiftSheetState _failed(String key) => ShiftSheetState(
    loading: false,
    detail: state.detail,
    assignment: state.assignment,
    errorKey: key,
  );

  /// Takes the caller's place from an action's answer, before the reload.
  void adoptAssignment(ShiftAssignmentRef? assignment) => emit(
    ShiftSheetState(
      loading: state.loading,
      detail: state.detail,
      assignment: assignment,
      errorKey: state.errorKey,
    ),
  );
}
