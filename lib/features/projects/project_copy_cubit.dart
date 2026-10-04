import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/project_template_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/project_repository.dart';

/// What the copy sheet asks of the server: the scope of a copy, and the copy
/// itself in either of its two shapes.
///
/// The sheet keeps its own form, busy flag and error text, as it did before;
/// this only stands between it and the repository. Every method answers what
/// the repository answered and throws what it threw.
class ProjectCopyCubit extends Cubit<void> {
  ProjectCopyCubit(this._projects) : super(null);

  final ProjectRepository _projects;

  /// What copying [projectId] would involve, with a free key to suggest.
  Future<ProjectCopyScope> scopeOfCopy(String projectId) =>
      _projects.scopeOfCopy(projectId);

  /// "Copy …" and "Make a template from …": every switch as the sheet set it.
  Future<ProjectCopyResult> copy(
    String projectId, {
    required String name,
    required String key,
    DateTime? eventDate,
    required bool includeMembers,
    required bool includeAttachments,
    required bool includeTimeSettings,
    required bool includeBoard,
    required bool asTemplate,
    RelativeDateBasis? deadlineBasis,
  }) => _projects.copyProject(
    projectId,
    name: name,
    key: key,
    eventDate: eventDate,
    includeMembers: includeMembers,
    includeAttachments: includeAttachments,
    includeTimeSettings: includeTimeSettings,
    includeBoard: includeBoard,
    asTemplate: asTemplate,
    deadlineBasis: deadlineBasis,
  );

  /// "Create a project from this": the copy with its scope already decided.
  Future<ProjectCopyResult> instantiate(
    String templateId, {
    required String name,
    required String key,
    DateTime? eventDate,
    RelativeDateBasis? deadlineBasis,
  }) => _projects.instantiateTemplate(
    templateId,
    name: name,
    key: key,
    eventDate: eventDate,
    deadlineBasis: deadlineBasis,
  );
}
