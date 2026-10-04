import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/time_privacy_models.dart';
import '../../core/repositories/time_repository.dart';

/// What a person asks about their own frozen time: a correction to an entry,
/// or older days opened for them — and what became of an earlier ask.
///
/// Holds no state: the lock notice and the entry sheet that ask keep their own.
/// Failures pass through as the repository's `ApiFailure`.
class TimeRequestsCubit extends Cubit<void> {
  TimeRequestsCubit(this._time) : super(null);

  final TimeRepository _time;

  /// Asks for a correction to the frozen entry [entryId], with the reason.
  Future<void> requestCorrection(String entryId, String note) =>
      _time.requestCorrection(entryId, note);

  /// Asks the administrators to open the days [from] to [to].
  Future<void> requestBackfill({
    required DateTime from,
    required DateTime to,
    required String note,
  }) => _time.requestBackfill(from: from, to: to, note: note);

  /// The reader's own requests about [entryId], newest first.
  Future<List<TimeCorrectionRequest>> entryCorrectionRequests(String entryId) =>
      _time.entryCorrectionRequests(entryId);
}
