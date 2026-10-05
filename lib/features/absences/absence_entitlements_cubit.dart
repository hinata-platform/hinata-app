import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/models/absence_models.dart';
import '../../core/models/core_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/repositories/user_repository.dart';

/// What the entitlements page asks: the catalogue it picks a type from, one
/// page of where people stand, and the names beside them.
///
/// Holds no state of its own. The page keeps its type, year, search and
/// selection as before; this is where its reads go.
class AbsenceEntitlementsCubit extends Cubit<void> {
  AbsenceEntitlementsCubit(this._absences, this._users) : super(null);

  final AbsenceRepository _absences;
  final UserRepository _users;

  /// Every type, the inactive ones too: the page decides which can be granted.
  Future<List<AbsenceType>> types() => _absences.types(includeInactive: true);

  Future<PageResult<AbsenceStanding>> overview({
    required String typeId,
    required int year,
    required String query,
    required int page,
    required int size,
  }) => _absences.overview(
    typeId: typeId,
    year: year,
    query: query,
    page: page,
    size: size,
  );

  Future<List<DirectoryUser>> usersByIds(List<String> ids) =>
      _users.usersByIds(ids);
}
