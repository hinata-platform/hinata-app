import 'package:bloc/bloc.dart';

import '../models/core_models.dart';
import '../repositories/user_repository.dart';

/// The directory search behind the people picker.
///
/// Holds no state: the picker keeps its own pages, request token and error,
/// because a debounced search that lands late is dropped by the panel, not
/// here. Failures pass through as the repository's `ApiFailure`.
class PersonPickerCubit extends Cubit<void> {
  PersonPickerCubit(this._users) : super(null);

  final UserRepository _users;

  /// One page of people matching [query].
  Future<({List<DirectoryUser> items, int total})> search(
    String query, {
    required int page,
    required int size,
  }) => _users.searchUsers(query, page: page, size: size);
}
