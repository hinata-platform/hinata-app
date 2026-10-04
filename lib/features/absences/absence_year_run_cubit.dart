import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/models/absence_models.dart';
import '../../core/models/absence_report_models.dart';
import '../../core/repositories/absence_repository.dart';

/// What the yearly-run page asks and does: the last run, the two lists it
/// leaves to a person, a notice sent by hand and a proposal decided.
///
/// Holds no state of its own. The page keeps the run, its lists and which rows
/// are busy as before; this is where its requests go.
class AbsenceYearRunCubit extends Cubit<void> {
  AbsenceYearRunCubit(this._absences) : super(null);

  final AbsenceRepository _absences;

  /// The last run beside every type it may name, asked at once.
  Future<({AbsenceYearRun run, List<AbsenceType> types})> overview() async {
    final answers = await Future.wait([
      _absences.yearRun(),
      _absences.types(includeInactive: true),
    ]);
    return (
      run: answers[0] as AbsenceYearRun,
      types: answers[1] as List<AbsenceType>,
    );
  }

  Future<PageResult<AbsenceMissingNotice>> missingNotices({
    required int page,
    required int size,
  }) => _absences.missingNotices(page: page, size: size);

  Future<PageResult<AbsenceProposal>> proposals({
    required int page,
    required int size,
  }) => _absences.proposals(page: page, size: size);

  Future<AbsenceNotice> sendNotice({
    required String userId,
    required String typeId,
    required int year,
  }) => _absences.sendNotice(userId: userId, typeId: typeId, year: year);

  /// Confirms the lapse [id] proposes when [lapse], dismisses it otherwise.
  Future<void> decide(
    String id, {
    required bool lapse,
    required String reason,
  }) => lapse
      ? _absences.confirmProposal(id, reason)
      : _absences.dismissProposal(id, reason);
}
