import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/core_models.dart';
import '../../../core/repositories/user_repository.dart';

/// The names behind the absence keepers' ids, so a chip reads as a person.
///
/// Holds no state: the card keeps the names it has already read and tops them
/// up from the picker, as before. Failures pass through untouched.
class AbsenceManagersCubit extends Cubit<void> {
  AbsenceManagersCubit(this._users) : super(null);

  final UserRepository _users;

  Future<List<DirectoryUser>> usersByIds(List<String> ids) =>
      _users.usersByIds(ids);
}
