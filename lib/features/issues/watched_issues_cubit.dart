import '../../core/blocs/paged_cubit.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/user_repository.dart';

/// The issues the signed-in user watches, paged, plus the reference data
/// their rows are drawn with.
class WatchedIssuesCubit extends PagedCubit<Issue> {
  WatchedIssuesCubit({
    required IssueRepository issues,
    required UserRepository users,
    required ProjectRepository projects,
    super.pageSize = 25,
  }) : _users = users,
       _projects = projects,
       super(
         (page, size) => issues.watchedIssues(page: page, size: size),
         keyOf: (issue) => issue.id,
       );

  final UserRepository _users;
  final ProjectRepository _projects;

  /// The directory and the projects, read side by side: the rows' names,
  /// avatars and state hues. A failure is the caller's to swallow.
  Future<({List<DirectoryUser> users, List<Project> projects})>
  reference() async {
    final results = await Future.wait([_users.users(), _projects.projects()]);
    return (
      users: results[0] as List<DirectoryUser>,
      projects: results[1] as List<Project>,
    );
  }
}
