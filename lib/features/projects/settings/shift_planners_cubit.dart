import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/shift_repository.dart';

class ShiftPlannersState extends Equatable {
  const ShiftPlannersState({
    this.loading = true,
    this.busy = false,
    this.planners,
    this.errorKey,
  });

  final bool loading;

  /// A grant or a revoke is under way.
  final bool busy;
  final ShiftPlanners? planners;
  final String? errorKey;

  ShiftPlannersState copyWith({
    bool? loading,
    bool? busy,
    ShiftPlanners? planners,
    String? errorKey,
  }) => ShiftPlannersState(
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    planners: planners ?? this.planners,
    errorKey: errorKey,
  );

  @override
  List<Object?> get props => [loading, busy, planners, errorKey];
}

/// Project settings → Schichtplanung (HIN-45): who may plan a project's
/// shifts besides its leads and team admins.
class ShiftPlannersCubit extends Cubit<ShiftPlannersState> {
  ShiftPlannersCubit(this._shifts, this.projectId)
    : super(const ShiftPlannersState());

  final ShiftRepository _shifts;
  final String projectId;

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    try {
      final planners = await _shifts.planners(projectId);
      if (isClosed) return;
      emit(ShiftPlannersState(loading: false, planners: planners));
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      emit(state.copyWith(loading: false, errorKey: _key(failure)));
    }
  }

  /// Grants each of [userIds] in turn, then reads the list once. Null when
  /// all went through, else the key of the first refusal.
  Future<String?> add(List<String> userIds) => _write(() async {
    for (final id in userIds) {
      await _shifts.addPlanner(projectId, id);
    }
  });

  Future<String?> remove(String userId) =>
      _write(() => _shifts.removePlanner(projectId, userId));

  Future<String?> _write(Future<void> Function() write) async {
    emit(state.copyWith(busy: true, errorKey: state.errorKey));
    String? error;
    try {
      await write();
    } on ApiFailure catch (failure) {
      error = _key(failure);
    }
    if (isClosed) return error;
    emit(state.copyWith(busy: false, errorKey: state.errorKey));
    await load();
    return error;
  }

  static String _key(ApiFailure failure) {
    final code = failure.details['code'];
    if (code != null && code.startsWith('error.shifts.')) return code;
    // A refusal without a code is the lead-only check.
    if (failure.statusCode == 403) return 'error.shifts.notPlanner';
    return failure.message;
  }
}
