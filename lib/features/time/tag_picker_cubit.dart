import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/models/time_policy_models.dart';
import '../../core/repositories/time_repository.dart';

/// The tag catalogue behind the tag picker: searched on the server, and grown
/// by a word where the operator lets the reader coin one.
///
/// Holds no state: the picker keeps the list, the picked words and its request
/// token. Failures pass through as the repository's `ApiFailure`.
class TagPickerCubit extends Cubit<void> {
  TagPickerCubit(this._time) : super(null);

  final TimeRepository _time;

  /// Tags matching [query]; null lists them all.
  Future<PageResult<TimeTag>> tags({String? query, required int size}) =>
      _time.tags(query: query, size: size);

  Future<TimeTag> createTag(String name) => _time.createTag(name);
}
