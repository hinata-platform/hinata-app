import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/models/absence_models.dart';
import '../../core/models/absence_report_models.dart';
import '../../core/repositories/absence_repository.dart';

/// What the reader's own balances panel asks the server: one year's balances,
/// the journal behind one of them, and the notices they received.
///
/// Holds no state of its own. The panel keeps its year, its open journal and
/// its lists as before; this is where their reads go, so the panel no longer
/// talks to the repository.
class AbsenceBalancesCubit extends Cubit<void> {
  AbsenceBalancesCubit(this._absences) : super(null);

  final AbsenceRepository _absences;

  /// The reader's own balances for [year].
  Future<AbsenceBalances> balances({required int year}) =>
      _absences.balances(year: year);

  /// One page of the journal behind one balance.
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

  /// One page of the notices the reader received.
  Future<PageResult<AbsenceNotice>> notices({
    required int page,
    required int size,
  }) => _absences.notices(page: page, size: size);
}
