import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/repositories/shift_repository.dart';

/// The projects the caller may plan (HIN-160), for the "+ Event" of the
/// events list: empty for a helper, so the button never shows to them.
class ShiftPlannableCubit extends Cubit<Set<String>> {
  ShiftPlannableCubit(this._shifts) : super(const {});

  final ShiftRepository _shifts;

  Future<void> load() async {
    try {
      final ids = await _shifts.plannableProjectIds();
      if (!isClosed) emit(ids);
    } catch (_) {
      // Nothing to offer then; reading the list does not depend on it.
    }
  }
}
