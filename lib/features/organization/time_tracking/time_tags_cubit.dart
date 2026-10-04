import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/blocs/paged_cubit.dart';
import '../../../core/models/time_policy_models.dart';
import '../../../core/repositories/time_repository.dart';

/// The time tags as the organisation keeps them: the catalogue with how many
/// entries carry each word, and every change to it.
///
/// Holds no state: the card keeps its pages, search and request token, and
/// re-reads after every change, as before. Failures pass through as the
/// repository's `ApiFailure`.
class TimeTagsCubit extends Cubit<void> {
  TimeTagsCubit(this._time) : super(null);

  final TimeRepository _time;

  /// One page of the catalogue; [withUsage] adds the number of entries behind
  /// each tag.
  Future<PageResult<TimeTag>> tags({
    String? query,
    required int page,
    required int size,
    bool withUsage = false,
  }) => _time.tags(query: query, page: page, size: size, withUsage: withUsage);

  Future<TimeTag> create(String name) => _time.createTag(name);

  Future<TimeTag> rename(String id, String name) =>
      _time.updateTag(id, name: name);

  Future<void> delete(String id) => _time.deleteTag(id);
}
