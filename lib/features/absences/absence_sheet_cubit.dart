import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/absence_request_models.dart';
import '../../core/models/core_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/repositories/availability_repository.dart';
import '../../core/repositories/user_repository.dart';

/// What the sheet for one absence asks and does: the request behind it, its
/// stand-in, the steps a request still allows, and deleting an absence that
/// was entered directly.
///
/// Holds no state of its own. The sheet keeps what it shows, its spinner and
/// its toasts as before; this is where its requests go.
class AbsenceSheetCubit extends Cubit<void> {
  AbsenceSheetCubit({
    required AbsenceRepository absences,
    required AvailabilityRepository availability,
    required UserRepository users,
  }) : _absences = absences,
       _availability = availability,
       _users = users,
       super(null);

  final AbsenceRepository _absences;
  final AvailabilityRepository _availability;
  final UserRepository _users;

  Future<AbsenceRequest> request(String id) => _absences.request(id);

  Future<List<DirectoryUser>> people(List<String> ids) =>
      _users.usersByIds(ids);

  Future<AbsenceRequest> withdraw(String id) => _absences.withdraw(id);

  Future<AbsenceRequest> cancel(String id, {String? note}) =>
      _absences.cancel(id, note: note);

  Future<AbsenceRequest> approve(String id) => _absences.approve(id);

  Future<AbsenceRequest> reject(String id, {required String note}) =>
      _absences.reject(id, note: note);

  /// Deletes an absence entered directly, which no request stands behind.
  Future<void> deleteEntered(String id) => _availability.deleteTimeOff(id);
}
