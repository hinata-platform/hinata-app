import 'package:bloc/bloc.dart';

import '../models/core_models.dart';
import '../repositories/user_repository.dart';

/// The directory search behind the people picker.
///
/// Holds no state: the picker keeps its own pages, request token and error,
/// because a debounced search that lands late is dropped by the panel, not
/// here. Failures pass through as the repository's `ApiFailure`.
class PersonPickerCubit extends Cubit<void> {
  PersonPickerCubit(this._users, {PersonSearch? source})
    : assert(_users != null || source != null),
      _source = source,
      super(null);

  /// The directory; not needed when [source] says where people come from.
  final UserRepository? _users;

  /// Where the people come from when not the whole directory — the members of
  /// one project, say. Null searches the directory.
  final PersonSearch? _source;

  /// One page of people matching [query].
  Future<({List<DirectoryUser> items, int total})> search(
    String query, {
    required int page,
    required int size,
  }) =>
      _source?.call(query, page, size) ??
      _users!.searchUsers(query, page: page, size: size);
}

/// A narrower list of people for the picker to page through.
typedef PersonSearch =
    Future<({List<DirectoryUser> items, int total})> Function(
      String query,
      int page,
      int size,
    );
