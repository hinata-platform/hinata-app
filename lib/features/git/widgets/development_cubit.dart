import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/git_dev_info.dart';
import '../../../core/models/work_models.dart';
import '../../../core/repositories/git_repository.dart';

/// An issue's development panel: its linked git activity and the pull
/// request actions run from it.
///
/// Holds no state of its own: the panel applies its optimistic transition
/// and reconciles it with what the server answers, as it did before.
class DevelopmentCubit extends Cubit<void> {
  DevelopmentCubit(this._git) : super(null);

  final GitRepository _git;

  Future<DevInfo> devInfo(String issueKey) => _git.gitDevInfo(issueKey);

  Future<({DevInfo devInfo, Issue issue})> mergePr(
    String issueKey,
    int number,
  ) => _git.gitMergePr(issueKey, number);

  Future<({DevInfo devInfo, Issue issue})> readyPr(
    String issueKey,
    int number,
  ) => _git.gitReadyPr(issueKey, number);
}
