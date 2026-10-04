import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/sprint_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../knowledge/data/knowledge_repository.dart';

/// Where the create-issue form sends its requests: the pickers' options, the
/// smart-link lookups of the description and, at the end, the new issue.
///
/// Holds no state of its own: the form keeps every field, the per-project load
/// generation that drops a slow answer for a project no longer selected, and
/// its own loading and error state, and awaits these calls the way it awaited
/// the repositories.
class IssueCreateCubit extends Cubit<void> {
  IssueCreateCubit({
    required IssueRepository issues,
    required ProjectRepository projects,
    required SprintRepository sprints,
    required UserRepository users,
    required this.knowledge,
  }) : _issues = issues,
       _projects = projects,
       _sprints = sprints,
       _users = users,
       super(null);

  final IssueRepository _issues;
  final ProjectRepository _projects;
  final SprintRepository _sprints;
  final UserRepository _users;

  /// The shared article cache the description's smart-link chips look
  /// articles up in while they build; [seedKnowledge] fills it.
  final KnowledgeRepository knowledge;

  Future<List<Project>> projects() => _projects.projects();

  Future<List<DirectoryUser>> users() => _users.users();

  Future<Issue> issue(String id) => _issues.issue(id);

  Future<List<Sprint>> sprintsForProject(String projectId) =>
      _sprints.sprintsForProject(projectId);

  /// Seeds the article cache once, so `{{doc:…}}` chips resolve.
  Future<void> seedKnowledge() => knowledge.init();

  Future<List<Issue>> resolveIssues(List<String> keys) =>
      _issues.resolveIssues(keys);

  Future<List<IssueRef>> mentionSearch({
    String? projectId,
    required String query,
  }) => _issues.mentionSearch(projectId: projectId, query: query);

  /// The first [size] issues anywhere matching [query].
  Future<({List<Issue> issues, int total})> searchIssues(
    String query, {
    required int size,
  }) => _issues.issues(query: query, size: size);

  /// The first [size] epics of [projectId] — the parents a new issue can get.
  Future<({List<Issue> issues, int total})> epics(
    String projectId, {
    required int size,
  }) => _issues.issues(projectId: projectId, types: const ['EPIC'], size: size);

  Future<Issue> createIssue(Map<String, dynamic> body) =>
      _issues.createIssue(body);

  Future<void> deleteProjectLabel(String projectId, String label) =>
      _projects.deleteProjectLabel(projectId, label);

  Future<DateTime?> resolveOffset(
    String projectId, {
    required RelativeDate offset,
  }) => _projects.resolveOffset(projectId, offset: offset);
}
