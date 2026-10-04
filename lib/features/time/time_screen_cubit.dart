import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/models/availability_models.dart';
import '../../core/models/time_models.dart';
import '../../core/models/time_privacy_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/availability_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/time_repository.dart';

/// The time list's reads and its one removal: a page of the reader's entries,
/// the hints and day markings of the windows they fall in, and the projects
/// they name.
///
/// Holds no state: the list keeps its pages, its filter and what it worked out
/// per window. Failures pass through as the repository's `ApiFailure`.
class TimeScreenCubit extends Cubit<void> {
  TimeScreenCubit(this._time, this._availability, this._projects) : super(null);

  final TimeRepository _time;
  final AvailabilityRepository _availability;
  final ProjectRepository _projects;

  /// One page of the reader's own entries, narrowed by [filter].
  Future<PageResult<WorkItem>> entries({
    required TimeEntryFilter filter,
    required int page,
    required int size,
  }) => _time.entries(filter: filter, page: page, size: size);

  /// The reader's self-hints for the days [from] to [to].
  Future<List<TimeHint>> hints(DateTime from, DateTime to) =>
      _time.hints(from, to);

  /// Capacity and day markings for the days [from] to [to].
  Future<Capacity> capacity(DateTime from, DateTime to) =>
      _availability.capacity(from, to);

  Future<List<Project>> resolveProjects(List<String> ids) =>
      _projects.resolveProjects(ids);

  Future<void> delete(String entryId) => _time.delete(entryId);
}
