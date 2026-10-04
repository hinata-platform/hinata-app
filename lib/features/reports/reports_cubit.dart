import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/content_models.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/dashboard_repository.dart';
import '../../core/repositories/meta_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/user_repository.dart';

/// The requests of the reports page: the projects to pick from, the directory
/// that names assignees, the distributions and the trend of one project, and
/// the branding a PDF export carries.
///
/// The page keeps what it loaded and its loading and error flags itself, as it
/// did before; this stands between it and the repositories. Every method
/// answers what the repository answered and throws what it threw.
class ReportsCubit extends Cubit<void> {
  ReportsCubit({
    required ProjectRepository projects,
    required UserRepository users,
    required DashboardRepository dashboard,
    required MetaRepository meta,
  }) : _projects = projects,
       _users = users,
       _dashboard = dashboard,
       _meta = meta,
       super(null);

  final ProjectRepository _projects;
  final UserRepository _users;
  final DashboardRepository _dashboard;
  final MetaRepository _meta;

  /// The projects and the directory, at once.
  Future<({List<Project> projects, List<DirectoryUser> users})>
  projectsAndUsers() async {
    final results = await Future.wait([_projects.projects(), _users.users()]);
    return (
      projects: results[0] as List<Project>,
      users: results[1] as List<DirectoryUser>,
    );
  }

  /// One distribution report: `report name → (key → count)`.
  Future<Map<String, int>> report(String name, Map<String, dynamic> query) =>
      _dashboard.report(name, query);

  Future<List<TrendPoint>> createdVsResolved(
    String projectId, {
    required int days,
  }) => _dashboard.createdVsResolved(projectId, days: days);

  /// The freshest server meta, for the branding of a PDF.
  Future<ServerMeta> meta() => _meta.meta();

  /// The organisation's logo through the server's proxy, or null for none.
  Future<({List<int> bytes, bool isSvg})?> organizationLogo() =>
      _meta.organizationLogo();
}
