import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/absence_models.dart' show AbsenceType;
import '../../core/models/availability_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/repositories/availability_repository.dart';

/// The form for one absence entered directly: the operator's types it can
/// name, and the write it ends in.
///
/// Holds no state of its own: the form keeps its draft, and these calls answer
/// or fail as the repositories do.
class TimeOffCubit extends Cubit<void> {
  TimeOffCubit(this._availability, this._absences) : super(null);

  final AvailabilityRepository _availability;
  final AbsenceRepository _absences;

  Future<List<AbsenceType>> types() => _absences.types();

  Future<TimeOff?> create(TimeOffDraft draft) =>
      _availability.createTimeOff(draft);

  Future<TimeOff?> update(String id, TimeOffDraft draft) =>
      _availability.updateTimeOff(id, draft);

  Future<void> delete(String id) => _availability.deleteTimeOff(id);
}
