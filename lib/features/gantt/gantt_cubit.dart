import 'package:bloc/bloc.dart';

import '../../core/models/work_models.dart';
import '../../core/repositories/project_repository.dart';

/// The reads behind the timeline: the projects to choose from and the chosen
/// project's bars and links.
///
/// Holds no state: the timeline keeps its own data, loading flag, error and
/// scroll position. Failures pass through as the repository's `ApiFailure`.
class GanttCubit extends Cubit<void> {
  GanttCubit(this._projects) : super(null);

  final ProjectRepository _projects;

  Future<List<Project>> projects() => _projects.projects();

  Future<GanttView> gantt(String projectId) => _projects.gantt(projectId);
}
