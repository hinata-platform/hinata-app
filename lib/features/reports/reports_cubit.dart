import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/core_models.dart';
import '../../core/models/report_overview_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/dashboard_repository.dart';
import '../../core/repositories/meta_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/user_repository.dart';

/// The requests of the report overview (HIN-157): the project it opens on,
/// that project's figures, the names of the people they mention, and the
/// branding a PDF export carries.
///
/// The view keeps what it loaded and its loading and error flags itself; this
/// stands between it and the repositories. Every method answers what the
/// repository answered and throws what it threw.
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

  /// The project [id] names, or the first the reader sees when it names none;
  /// null when there is no project at all. One page of one, never the list.
  Future<Project?> project(String? id) async => id != null
      ? await _projects.project(id)
      : (await _projects.searchProjects(size: 1)).projects.firstOrNull;

  /// Every figure of one project over the last [days], in one request.
  Future<ReportOverview> overview(String projectId, {required int days}) =>
      _dashboard.overview(projectId, days: days);

  /// The people the report names, and only those.
  Future<List<DirectoryUser>> usersByIds(List<String> ids) =>
      _users.usersByIds(ids);

  /// The freshest server meta, for the branding of a PDF.
  Future<ServerMeta> meta() => _meta.meta();

  /// The organisation's logo through the server's proxy, or null for none.
  Future<({List<int> bytes, bool isSvg})?> organizationLogo() =>
      _meta.organizationLogo();
}
