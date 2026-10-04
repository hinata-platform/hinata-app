import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/models/absence_models.dart';
import '../../core/models/absence_report_models.dart';
import '../../core/repositories/absence_repository.dart';

/// What the four sheets over the entitlements list ask and write: a grant and
/// its preview, a correction, the employment dates with the settlement they
/// lead to, and the journal.
///
/// Holds no state of its own. Each sheet keeps its draft, its spinner and its
/// toasts as before; this is where their requests go, and every method answers
/// with what the repository answered, or throws its failure.
class AbsenceEntitlementSheetCubit extends Cubit<void> {
  AbsenceEntitlementSheetCubit(this._absences) : super(null);

  final AbsenceRepository _absences;

  // --- a grant -------------------------------------------------------------------

  Future<List<AbsenceGrantPreview>> previewGrant({
    required String typeId,
    required int year,
    required List<String> userIds,
    int? allowanceMilliDays,
  }) => _absences.previewGrant(
    typeId: typeId,
    year: year,
    userIds: userIds,
    allowanceMilliDays: allowanceMilliDays,
  );

  Future<List<AbsenceEntitlement>> grantMany({
    required String typeId,
    required int year,
    required List<String> userIds,
    int? allowanceMilliDays,
  }) => _absences.grantMany(
    typeId: typeId,
    year: year,
    userIds: userIds,
    allowanceMilliDays: allowanceMilliDays,
  );

  // --- a correction --------------------------------------------------------------

  Future<AbsenceLedgerEntry> adjust({
    required String userId,
    required String typeId,
    required int year,
    required int milliDays,
    required String reason,
    DateTime? effectiveOn,
  }) => _absences.adjust(
    userId: userId,
    typeId: typeId,
    year: year,
    milliDays: milliDays,
    reason: reason,
    effectiveOn: effectiveOn,
  );

  // --- joining and leaving -------------------------------------------------------

  Future<EmploymentDates> employment(String userId) =>
      _absences.employment(userId);

  Future<EmploymentDates> saveEmployment({
    required String userId,
    DateTime? hiredOn,
    DateTime? leftOn,
    String? note,
  }) => _absences.saveEmployment(
    userId: userId,
    hiredOn: hiredOn,
    leftOn: leftOn,
    note: note,
  );

  /// What settling [userId]'s leave takes, beside every type it may name —
  /// the inactive ones too, since a settlement can be about a type that has
  /// been switched off since. Both asked at once, as the sheet did.
  Future<({List<AbsenceSettlement> settlement, List<AbsenceType> types})>
  settlement(String userId) async {
    final answers = await Future.wait([
      _absences.settlement(userId),
      _absences.types(includeInactive: true),
    ]);
    return (
      settlement: answers[0] as List<AbsenceSettlement>,
      types: answers[1] as List<AbsenceType>,
    );
  }

  Future<AbsenceLedgerEntry> payout({
    required String userId,
    required String typeId,
    required int year,
    required int milliDays,
    required String reason,
  }) => _absences.payout(
    userId: userId,
    typeId: typeId,
    year: year,
    milliDays: milliDays,
    reason: reason,
  );

  // --- the journal ---------------------------------------------------------------

  Future<PageResult<AbsenceLedgerEntry>> ledger({
    required String userId,
    required String typeId,
    required int year,
    required int page,
    required int size,
  }) => _absences.ledger(
    userId: userId,
    typeId: typeId,
    year: year,
    page: page,
    size: size,
  );
}
