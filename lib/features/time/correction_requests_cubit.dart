import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/models/time_privacy_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/time_repository.dart';

/// The requests the reader can answer, as calls: a page of them, the projects
/// they name, and the two answers.
///
/// Holds no state: the list keeps its own pages, its labels and the answers on
/// their way. Failures pass through as the repository's `ApiFailure`.
class CorrectionRequestsCubit extends Cubit<void> {
  CorrectionRequestsCubit(this._time, this._projects) : super(null);

  final TimeRepository _time;
  final ProjectRepository _projects;

  Future<PageResult<TimeCorrectionRequest>> correctionRequests({
    required int page,
    required int size,
  }) => _time.correctionRequests(page: page, size: size);

  /// The projects behind [ids], for the key under each request.
  Future<List<Project>> resolveProjects(List<String> ids) =>
      _projects.resolveProjects(ids);

  /// Answers [requestId] with a sentence and nothing else.
  Future<TimeCorrectionRequest> answer(String requestId, String note) =>
      _time.answerCorrection(requestId, note);

  /// Opens the days for the person who asked, with an optional sentence.
  Future<TimeCorrectionRequest> grant(String requestId, String note) =>
      _time.grantCorrection(requestId, note);
}
