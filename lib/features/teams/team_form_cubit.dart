import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/team_models.dart';
import '../../core/repositories/team_repository.dart';

/// The create- and edit-team modal's requests.
///
/// The form keeps its fields, busy flag and error text itself, as it did
/// before; this only stands between it and the repository. Every method
/// answers what the repository answered and throws what it threw.
class TeamFormCubit extends Cubit<void> {
  TeamFormCubit(this._teams) : super(null);

  final TeamRepository _teams;

  Future<Team> create({
    required String name,
    required String key,
    String? description,
    required int colorHue,
    required String icon,
  }) => _teams.createTeam(
    name: name,
    key: key,
    description: description,
    colorHue: colorHue,
    icon: icon,
  );

  /// Writes the edited fields of team [teamId].
  Future<Team> update(String teamId, Map<String, dynamic> patch) =>
      _teams.updateTeam(teamId, patch);

  Future<String> uploadAvatar(String teamId, MultipartFile file) =>
      _teams.uploadTeamAvatar(teamId, file);

  Future<void> removeAvatar(String teamId) => _teams.deleteTeamAvatar(teamId);
}
