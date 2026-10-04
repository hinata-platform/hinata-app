import 'package:bloc/bloc.dart';

import '../models/work_models.dart';
import '../repositories/project_repository.dart';

/// The project search behind the project picker.
///
/// Holds no state: the picker keeps its own pages, working selection and
/// request token. Failures pass through as the repository's `ApiFailure`.
class ProjectPickerCubit extends Cubit<void> {
  ProjectPickerCubit(this._projects) : super(null);

  final ProjectRepository _projects;

  /// One page of projects matching [query]; null lists them all.
  Future<({List<Project> projects, int total})> search({
    String? query,
    required int page,
    required int size,
  }) => _projects.searchProjects(query: query, page: page, size: size);

  /// The projects behind [ids], for selected rows the caller only knew by id.
  Future<List<Project>> resolve(List<String> ids) =>
      _projects.resolveProjects(ids);
}
