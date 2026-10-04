import '../../core/blocs/fetch_cubit.dart';
import '../../core/models/content_models.dart';
import '../../core/models/team_models.dart' show Team;
import '../../core/models/work_models.dart';
import '../../core/repositories/dashboard_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/team_repository.dart';

/// Where a load reads the unsaved personalisation from. A holder rather than a
/// field, because the loader is handed to the super constructor before the
/// cubit exists.
class _Preview {
  DashboardPrefs? Function()? of;
}

/// The dashboard: its payload, the projects and teams its scope pickers offer,
/// and saving the reader's personalisation.
///
/// The page decides whether a load previews unsaved prefs — it keeps the
/// draft and the edit mode, and reloads on events from elsewhere at any time
/// — so it hands the cubit a [previewSource] that every load asks.
class DashboardCubit extends FetchCubit<DashboardData> {
  factory DashboardCubit(
    DashboardRepository dashboard,
    ProjectRepository projects,
    TeamRepository teams,
  ) {
    final preview = _Preview();
    return DashboardCubit._(
      dashboard,
      projects,
      teams,
      preview,
      () => dashboard.dashboard(override: preview.of?.call()),
    );
  }

  DashboardCubit._(
    this._dashboard,
    this._projects,
    this._teams,
    this._preview,
    Future<DashboardData> Function() loader,
  ) : super(loader);

  final DashboardRepository _dashboard;
  final ProjectRepository _projects;
  final TeamRepository _teams;
  final _Preview _preview;

  /// The prefs a load previews, null for the saved ones.
  set previewSource(DashboardPrefs? Function() source) => _preview.of = source;

  /// What the scope pickers offer, read one after the other.
  Future<({List<Project> projects, List<Team> teams})> pickerData() async {
    final projects = await _projects.projects();
    final teams = await _teams.teams();
    return (projects: projects, teams: teams);
  }

  Future<DashboardPrefs> savePrefs(DashboardPrefs prefs) =>
      _dashboard.saveDashboardPrefs(prefs);
}
