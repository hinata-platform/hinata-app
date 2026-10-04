import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/core_models.dart';
import '../../core/repositories/user_repository.dart';

/// The one lookup the project form makes by itself: the person creating the
/// project, so the lead field opens filled with them.
///
/// Answers what the repository answered and throws what it threw; the form
/// decides what an empty answer or a failure means.
class ProjectLeadCubit extends Cubit<void> {
  ProjectLeadCubit(this._users) : super(null);

  final UserRepository _users;

  /// The directory entries for [ids], without paging the whole directory.
  Future<List<DirectoryUser>> usersByIds(List<String> ids) =>
      _users.usersByIds(ids);
}
