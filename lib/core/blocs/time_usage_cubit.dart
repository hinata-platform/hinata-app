import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/time_usage_models.dart';
import '../repositories/time_usage_repository.dart';

/// What every visible project has used against its budget, held once for the
/// whole app (HIN-152).
///
/// A board head, the project list, the dashboard's honeycomb, the project
/// settings and later the entry form all show the same project's figures, and
/// a fetch per surface would be as many requests and as many ways to disagree.
/// Surfaces call [watch] with the projects they draw and read one project each
/// through a selector; the cubit asks the server once for whatever is missing
/// or older than [freshFor], in steps the server accepts.
///
/// [enabled] answers whether the extended module is on: with it off the
/// server has no such route, and the cubit asks nothing.
class TimeUsageCubit extends Cubit<TimeUsageState> {
  TimeUsageCubit(this._repository, {required bool Function() enabled})
    : _enabled = enabled,
      super(const TimeUsageState());

  final TimeUsageRepository _repository;
  final bool Function() _enabled;

  /// How long a project's figures count as current. The server holds its
  /// sums for 30 seconds too, so asking sooner would mostly return the same.
  static const freshFor = Duration(seconds: 30);

  final Map<String, DateTime> _fetchedAt = {};
  final Set<String> _inFlight = {};

  final Set<String> _queued = {};
  Completer<void>? _flush;

  /// Makes sure [projectIds] have current figures; returns when they do.
  ///
  /// Calls made in the same turn of the event loop are gathered into one
  /// request: a list of thirty project cards each asking for its own project
  /// costs one round trip, not thirty.
  Future<void> watch(Iterable<String> projectIds) {
    if (!_enabled() || isClosed) return Future.value();
    final now = DateTime.now();
    for (final id in projectIds) {
      if (id.isEmpty || _inFlight.contains(id)) continue;
      final at = _fetchedAt[id];
      if (at == null || now.difference(at) > freshFor) _queued.add(id);
    }
    if (_queued.isEmpty) return Future.value();
    final flush = _flush ??= Completer<void>();
    if (!_scheduled) {
      _scheduled = true;
      Timer.run(_run);
    }
    return flush.future;
  }

  bool _scheduled = false;

  Future<void> _run() async {
    _scheduled = false;
    final flush = _flush;
    _flush = null;
    final asked = Set.of(_queued);
    _queued.clear();
    _inFlight.addAll(asked);
    try {
      if (asked.isEmpty || isClosed) return;
      final found = await _repository.projects(asked);
      if (isClosed) return;
      final at = DateTime.now();
      for (final id in asked) {
        _fetchedAt[id] = at;
      }
      emit(
        state.copyWith(
          projects: {...state.projects, ...found},
          // A project that came back without figures cannot be seen or does
          // not exist; forget whatever was held for it.
          without: asked.difference(found.keys.toSet()),
        ),
      );
    } on Object {
      // Figures are a side note on every surface that shows them: a failed
      // read leaves the surface without the note, never with an error. The
      // next watch asks again.
    } finally {
      _inFlight.removeAll(asked);
      flush?.complete();
    }
  }

  /// Marks a project's figures stale and asks again: after an entry was
  /// saved, moved or deleted, or a budget was changed.
  Future<void> refresh(String projectId) {
    _fetchedAt.remove(projectId);
    return watch([projectId]);
  }

  /// Forgets everything; for a sign-out, where the next session may be another
  /// server.
  void reset() {
    _fetchedAt.clear();
    if (!isClosed) emit(const TimeUsageState());
  }
}

class TimeUsageState extends Equatable {
  const TimeUsageState({this.projects = const {}});

  final Map<String, ProjectTimeUsage> projects;

  ProjectTimeUsage? of(String projectId) => projects[projectId];

  TimeUsageState copyWith({
    Map<String, ProjectTimeUsage>? projects,
    Set<String> without = const {},
  }) {
    final next = Map.of(projects ?? this.projects)
      ..removeWhere((id, _) => without.contains(id));
    return TimeUsageState(projects: next);
  }

  @override
  List<Object?> get props => [projects];
}
