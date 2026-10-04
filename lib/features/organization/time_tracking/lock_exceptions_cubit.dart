import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/time_approval_models.dart';
import '../../../core/repositories/time_repository.dart';

/// Opening and closing a span inside the lock date.
///
/// Holds no state: the card reads the open spans from the time policy and
/// keeps them, as before. Both calls answer with every exception still open;
/// failures pass through as the repository's `ApiFailure`.
class LockExceptionsCubit extends Cubit<void> {
  LockExceptionsCubit(this._time) : super(null);

  final TimeRepository _time;

  Future<List<TimeLockException>> add({
    required DateTime from,
    required DateTime to,
    required String note,
  }) => _time.addLockException(from: from, to: to, note: note);

  Future<List<TimeLockException>> remove(String id) =>
      _time.removeLockException(id);
}
