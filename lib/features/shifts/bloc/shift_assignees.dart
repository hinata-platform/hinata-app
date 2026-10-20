import '../../../core/models/core_models.dart' show DirectoryUser;
import '../../../core/repositories/project_repository.dart';
import '../../../core/repositories/user_repository.dart';

/// The people a planner can put on a shift of one project: its members and
/// leads, searched and paged on the device (HIN-160).
///
/// Read once per picker: the project names its people, and their cards come
/// in one request per hundred. Somebody who reaches the project only through
/// a team is not in that list; the server would accept them, and they are the
/// one case this does not offer.
class ShiftAssignees {
  ShiftAssignees(this._projects, this._users, this.projectId);

  final ProjectRepository _projects;
  final UserRepository _users;
  final String projectId;

  Future<List<DirectoryUser>>? _all;

  Future<List<DirectoryUser>> _load() async {
    final project = await _projects.project(projectId);
    final ids = <String>{...project.leadIds, ...project.memberIds}.toList();
    final users = await _users.usersByIds(ids);
    users.sort(
      (a, b) => _name(a).toLowerCase().compareTo(_name(b).toLowerCase()),
    );
    return users;
  }

  static String _name(DirectoryUser u) =>
      u.displayName.isEmpty ? u.username : u.displayName;

  /// One page of the people matching [query].
  Future<({List<DirectoryUser> items, int total})> search(
    String query,
    int page,
    int size,
  ) async {
    final all = await (_all ??= _load());
    final q = query.trim().toLowerCase();
    final hits = q.isEmpty
        ? all
        : [
            for (final u in all)
              if (_name(u).toLowerCase().contains(q) ||
                  u.username.toLowerCase().contains(q))
                u,
          ];
    final from = (page * size).clamp(0, hits.length);
    final to = (from + size).clamp(0, hits.length);
    return (items: hits.sublist(from, to), total: hits.length);
  }
}
