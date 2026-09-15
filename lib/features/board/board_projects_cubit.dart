import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/api/api_client.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/project_repository.dart';

/// The projects a board spans, as far as they could be read.
class BoardProjectsState extends Equatable {
  const BoardProjectsState({
    this.projectIds = const [],
    this.byId = const {},
    this.names = const {},
  });

  /// No project read yet.
  static const none = BoardProjectsState();

  /// The projects the board named when they were read, in the board's order.
  final List<String> projectIds;

  /// The projects read, by id. A project the viewer may not read is missing.
  final Map<String, Project> byId;

  /// The names of [byId], by id.
  final Map<String, String> names;

  /// The projects in the board's order: what a board's composer may create
  /// into. More than one only on a merged board.
  List<Project> get inBoardOrder => [for (final id in projectIds) ?byId[id]];

  @override
  List<Object?> get props => [projectIds, byId, names];
}

/// Reads the projects a board spans once the board names them, and again only
/// when it names others.
///
/// A cross-project board needs the whole project, not only its name, to tell
/// which of a column's states a dropped card's own project has, and the
/// board's project names and colours come from them. The wall reads without
/// them, so projects that do not come leave plain names and colours until the
/// board names its projects again.
class BoardProjectsCubit extends Cubit<BoardProjectsState> {
  BoardProjectsCubit({required ProjectRepository projects})
    : _projects = projects,
      super(BoardProjectsState.none);

  final ProjectRepository _projects;

  /// The projects asked for last, while they are read or once they were.
  List<String>? _asked;

  /// Reads the projects [projectIds], unless they are the ones read or being
  /// read already.
  Future<void> resolve(List<String> projectIds) async {
    final asked = _asked;
    if (asked != null && _sameIds(asked, projectIds)) return;
    _asked = projectIds;
    try {
      final projects = await _projects.resolveProjects(projectIds);
      if (isClosed || !identical(_asked, projectIds)) return;
      emit(
        BoardProjectsState(
          projectIds: projectIds,
          byId: {for (final project in projects) project.id: project},
          names: {for (final project in projects) project.id: project.name},
        ),
      );
    } on ApiFailure {
      // Asked for again the next time the board names them.
      if (identical(_asked, projectIds)) _asked = null;
    }
  }

  static bool _sameIds(List<String> asked, List<String> named) {
    if (asked.length != named.length) return false;
    for (var i = 0; i < asked.length; i++) {
      if (asked[i] != named[i]) return false;
    }
    return true;
  }
}
