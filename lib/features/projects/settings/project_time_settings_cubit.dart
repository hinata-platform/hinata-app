import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/time_policy_models.dart';
import '../../../core/repositories/time_repository.dart';

/// The project's own time-tracking settings, read and written by the section
/// that shows them.
///
/// The section keeps its draft, its busy flag and its error text, as it did
/// before; this only stands between it and the repository. Both methods
/// answer what the repository answered and throw what it threw.
class ProjectTimeSettingsCubit extends Cubit<void> {
  ProjectTimeSettingsCubit(this._time, {required this.projectId}) : super(null);

  final TimeRepository _time;
  final String projectId;

  Future<ProjectTimeSettings> load() => _time.projectSettings(projectId);

  Future<ProjectTimeSettings> save(ProjectTimeSettings settings) =>
      _time.saveProjectSettings(projectId, settings);
}
