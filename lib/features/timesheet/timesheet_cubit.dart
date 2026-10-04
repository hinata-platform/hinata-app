import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/models/availability_models.dart';
import '../../core/models/core_models.dart';
import '../../core/models/time_approval_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/availability_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/time_repository.dart';
import '../../core/repositories/timesheet_repository.dart';
import '../../core/repositories/user_repository.dart';

/// The timesheet's reads: the rows of a window from either route, the period
/// around a day, the names behind the rows, the two filter searches and the
/// reader's own capacity.
///
/// Holds no state: the page keeps its window, its filters, its rows and the
/// labels it resolved. Failures pass through as the repository's `ApiFailure`.
class TimesheetCubit extends Cubit<void> {
  TimesheetCubit({
    required TimeRepository time,
    required TimesheetRepository timesheets,
    required UserRepository users,
    required ProjectRepository projects,
    required AvailabilityRepository availability,
  }) : _time = time,
       _timesheets = timesheets,
       _users = users,
       _projects = projects,
       _availability = availability,
       super(null);

  final TimeRepository _time;
  final TimesheetRepository _timesheets;
  final UserRepository _users;
  final ProjectRepository _projects;
  final AvailabilityRepository _availability;

  /// One page of rows from the time module's route.
  Future<PageResult<TimesheetRow>> moduleRows({
    required DateTime from,
    required DateTime to,
    String? userId,
    String? projectId,
    required int size,
  }) => _time.timesheet(
    from: from,
    to: to,
    userId: userId,
    projectId: projectId,
    size: size,
  );

  /// Every row of the window from the base route, which answers in one array.
  Future<List<TimesheetRow>> rows(
    DateTime from,
    DateTime to, {
    String? userId,
    String? projectId,
  }) => _timesheets.timesheet(from, to, userId: userId, projectId: projectId);

  /// The approval periods touching [from] to [to].
  Future<List<ApprovalPeriod>> approvalPeriods({
    required DateTime from,
    required DateTime to,
    String? projectId,
  }) => _time.approvalPeriods(from: from, to: to, projectId: projectId);

  Future<List<DirectoryUser>> usersByIds(List<String> ids) =>
      _users.usersByIds(ids);

  Future<List<Project>> resolveProjects(List<String> ids) =>
      _projects.resolveProjects(ids);

  /// One page of the directory, for the person filter.
  Future<({List<DirectoryUser> items, int total})> searchUsers(
    String query, {
    required int page,
    required int size,
  }) => _users.searchUsers(query, page: page, size: size);

  /// One page of the catalogue, for the project filter.
  Future<({List<Project> projects, int total})> searchProjects({
    required String query,
    required int page,
    required int size,
  }) => _projects.searchProjects(query: query, page: page, size: size);

  /// The reader's capacity for [from] to [to].
  Future<Capacity> capacity(DateTime from, DateTime to) =>
      _availability.capacity(from, to);
}
