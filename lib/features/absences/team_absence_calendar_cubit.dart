import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/models/team_absence_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/repositories/team_repository.dart';

/// What the team absence calendar asks: a page of rows, the capacity band
/// above them, and the teams its group picker offers.
///
/// Holds no state of its own. The page keeps its window, its group and the
/// rows and band cubits as before; this is where their reads go.
class TeamAbsenceCalendarCubit extends Cubit<void> {
  TeamAbsenceCalendarCubit(this._absences, this._teams) : super(null);

  final AbsenceRepository _absences;
  final TeamRepository _teams;

  Future<TeamAbsencePage> rows({
    required DateTime from,
    required DateTime to,
    required TeamAbsenceScope scope,
    required bool awayOnly,
    required int page,
    required int size,
  }) => _absences.teamCalendar(
    from: from,
    to: to,
    scope: scope,
    awayOnly: awayOnly,
    page: page,
    size: size,
  );

  /// The band for [scope], or null for a reader the server does not give it.
  Future<CapacityBand?> band({
    required DateTime from,
    required DateTime to,
    required TeamAbsenceScope scope,
    required CapacityResolution resolution,
  }) async {
    try {
      return await _absences.capacityBand(
        from: from,
        to: to,
        scope: scope,
        resolution: resolution,
      );
    } on ApiFailure catch (failure) {
      // Not somebody who plans this group, or a group too small to add up
      // without showing one person: the band is simply not shown.
      if (failure.statusCode == 403) return null;
      rethrow;
    }
  }

  /// The teams the reader can pick, as id and name.
  Future<List<({String id, String name})>> teams() async => [
    for (final team in await _teams.teams()) (id: team.id, name: team.name),
  ];
}
