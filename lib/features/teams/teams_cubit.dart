import '../../core/blocs/fetch_cubit.dart';
import '../../core/models/core_models.dart';
import '../../core/models/team_models.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/widgets/user_pronouns.dart';

/// What the team list shows: the teams, and the names, pictures and pronouns
/// of the people on their cards.
typedef TeamsData = ({
  List<Team> teams,
  Map<String, String> names,
  Map<String, String> avatars,
  Map<String, String> pronouns,
});

/// The team list.
class TeamsCubit extends FetchCubit<TeamsData> {
  TeamsCubit({required TeamRepository teams, required UserRepository users})
    : super(() => _read(teams, users));

  static Future<TeamsData> _read(
    TeamRepository teamRepository,
    UserRepository userRepository,
  ) async {
    final results = await Future.wait([
      teamRepository.teams(),
      userRepository.users(),
    ]);
    final teams = results[0] as List<Team>;
    final users = results[1] as List<DirectoryUser>;
    final names = {for (final u in users) u.id: u.displayName};
    final avatars = {
      for (final u in users)
        if (u.avatarUrl != null && u.avatarUrl!.isNotEmpty) u.id: u.avatarUrl!,
    };
    final pronouns = pronounsById(users);
    return (teams: teams, names: names, avatars: avatars, pronouns: pronouns);
  }
}
