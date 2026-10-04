import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/meta_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/user_repository.dart';

/// What the issues list asks the server for: the facets the backend narrows
/// by and the order it sorts in. Null facets do not narrow.
typedef IssueListQuery = ({
  String? projectId,
  bool archived,
  List<String>? states,
  List<String>? priorities,
  List<String>? types,
  List<String>? assigneeIds,
  String? sort,
});

/// The issues list: its pages, the reference data its rows are drawn with,
/// and the bulk deadline it can set on a selection.
///
/// [query] is read on every fetch, so a page always asks for what the head
/// shows at that moment — the filter and the sort stay with the screen.
class IssuesListCubit extends PagedCubit<Issue> {
  IssuesListCubit({
    required IssueRepository issues,
    required ProjectRepository projects,
    required UserRepository users,
    required IssueListQuery Function() query,
    super.pageSize,
  }) : _issues = issues,
       _projects = projects,
       _users = users,
       super((page, size) async {
         final q = query();
         final result = await issues.issues(
           projectId: q.projectId,
           archived: q.archived,
           states: q.states,
           priorities: q.priorities,
           types: q.types,
           assigneeIds: q.assigneeIds,
           sort: q.sort,
           page: page,
           size: size,
         );
         return (items: result.issues, total: result.total);
       }, keyOf: (issue) => issue.id);

  final IssueRepository _issues;
  final ProjectRepository _projects;
  final UserRepository _users;

  /// The directory and the projects, read side by side: the rows' names,
  /// avatars and state hues, and the order of the status groups. A failure
  /// is the caller's to handle.
  Future<({List<DirectoryUser> users, List<Project> projects})>
  reference() async {
    final results = await Future.wait([_users.users(), _projects.projects()]);
    return (
      users: results[0] as List<DirectoryUser>,
      projects: results[1] as List<Project>,
    );
  }

  /// Sets — or with [clearDueDate] clears — the deadline of every one of
  /// [issueIds]; answers the issues as they now are.
  Future<List<Issue>> bulkSetDeadline(
    List<String> issueIds, {
    DateTime? dueDate,
    RelativeDate? dueOffset,
    bool clearDueDate = false,
  }) => _issues.bulkSetDeadline(
    issueIds,
    dueDate: dueDate,
    dueOffset: dueOffset,
    clearDueDate: clearDueDate,
  );

  /// The day [offset] falls on in the project [projectId].
  Future<DateTime?> resolveOffset(
    String projectId, {
    required RelativeDate offset,
  }) => _projects.resolveOffset(projectId, offset: offset);
}

/// What an export of the issues list reads: every matching issue, not only the
/// pages scrolled into view, and for the PDF the organisation's name and logo.
///
/// Holds no state of its own; the screen keeps its exporting flag.
class IssuesExportCubit extends Cubit<void> {
  IssuesExportCubit({
    required IssueRepository issues,
    required MetaRepository meta,
  }) : _issues = issues,
       _meta = meta,
       super(null);

  final IssueRepository _issues;
  final MetaRepository _meta;

  /// Every issue [query] matches, all pages drained.
  Future<List<Issue>> all(IssueListQuery query) => _issues.allIssues(
    projectId: query.projectId,
    archived: query.archived,
    states: query.states,
    priorities: query.priorities,
    types: query.types,
    assigneeIds: query.assigneeIds,
    sort: query.sort,
  );

  Future<ServerMeta> meta() => _meta.meta();

  Future<({List<int> bytes, bool isSvg})?> organizationLogo() =>
      _meta.organizationLogo();
}
