import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/absence_models.dart';
import '../../core/repositories/absence_repository.dart';

/// What the absence types page and its editor ask and write.
///
/// Holds no state of its own. The page keeps its list and switch, the editor
/// its form, as before; this is where their requests go.
class AbsenceTypesCubit extends Cubit<void> {
  AbsenceTypesCubit(this._absences) : super(null);

  final AbsenceRepository _absences;

  /// Every type, the inactive ones too: the page filters what it draws.
  Future<List<AbsenceType>> types() => _absences.types(includeInactive: true);

  /// Saves [draft] as a new type, or over [existingId].
  Future<AbsenceType> save(AbsenceTypeDraft draft, {String? existingId}) =>
      existingId == null
      ? _absences.createType(draft)
      : _absences.updateType(existingId, draft);

  Future<void> delete(String id) => _absences.deleteType(id);
}
