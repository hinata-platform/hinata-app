import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/absence_request_models.dart';
import '../../core/models/core_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/repositories/user_repository.dart';

/// What the request form sends: a preview of the days, the stand-in it names,
/// and the request itself.
///
/// Holds no state of its own. The form keeps its draft, its spinner and its
/// toasts as before; this is where its requests go.
class AbsenceRequestSheetCubit extends Cubit<void> {
  AbsenceRequestSheetCubit(this._absences, this._users) : super(null);

  final AbsenceRepository _absences;
  final UserRepository _users;

  /// The people behind [ids] — the stand-in a template named.
  Future<List<DirectoryUser>> people(List<String> ids) =>
      _users.usersByIds(ids);

  Future<AbsencePreview> preview(AbsenceRequestDraft draft) =>
      _absences.preview(draft);

  /// Files [draft] as a new request, or as the new state of [existingId].
  Future<AbsenceRequest> file(
    AbsenceRequestDraft draft, {
    String? existingId,
  }) => existingId == null
      ? _absences.submit(draft)
      : _absences.edit(existingId, draft);
}

/// What the sick report sends. Apart from the request form on purpose, as the
/// two sheets are: reporting sickness asks nobody and names no stand-in.
class SickReportCubit extends Cubit<void> {
  SickReportCubit(this._absences) : super(null);

  final AbsenceRepository _absences;

  Future<SickReport> reportSick({
    required DateTime from,
    DateTime? to,
    bool halfDay = false,
    String? typeId,
  }) => _absences.reportSick(
    from: from,
    to: to,
    halfDay: halfDay,
    typeId: typeId,
  );
}
