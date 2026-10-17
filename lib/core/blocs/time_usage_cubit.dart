import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
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
///
/// It is also the one way a budget widget reads anything else about budgets
/// (an issue's estimate, a forecast, a sprint, a history, the report's pages):
/// those widgets never hold the repository, every read is behind the same
/// module gate, and forecasts are held like the figures.
class TimeUsageCubit extends Cubit<TimeUsageState> {
  TimeUsageCubit(this._repository, {required bool Function() enabled})
    : _enabled = enabled,
      super(const TimeUsageState());

  /// The app-wide cubit, or null where none is provided (a test of one sheet,
  /// a tree outside the app) or the extended module is off. A surface then
  /// shows no figures.
  static TimeUsageCubit? maybeOf(BuildContext context) {
    try {
      final cubit = BlocProvider.of<TimeUsageCubit>(context, listen: false);
      return cubit._enabled() ? cubit : null;
    } on FlutterError {
      // BlocProvider.of reports a missing provider as a FlutterError.
      return null;
    } on ProviderNotFoundException {
      return null;
    }
  }

  final TimeUsageRepository _repository;
  final bool Function() _enabled;

  /// How long a project's figures count as current. The server holds its
  /// sums for 30 seconds too, so asking sooner would mostly return the same.
  static const freshFor = Duration(seconds: 30);

  final Map<String, DateTime> _fetchedAt = {};
  final Set<String> _inFlight = {};

  /// Asked again while a read of them was under way: that read may carry the
  /// figures from before the save that asked, so they are read once more
  /// when it lands.
  final Set<String> _dirty = {};

  final Map<String, ({BudgetForecast forecast, DateTime at})> _forecasts = {};

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
      final again = _dirty.intersection(asked);
      _dirty.removeAll(again);
      if (again.isNotEmpty && !isClosed) {
        // What just landed is from before the save: not fresh.
        again.forEach(_fetchedAt.remove);
        unawaited(watch(again));
      }
    }
  }

  /// Marks a project's figures stale and asks again: after an entry was
  /// saved, moved or deleted, or a budget was changed.
  Future<void> refresh(String projectId) {
    _fetchedAt.remove(projectId);
    _forecasts.remove(projectId);
    if (_inFlight.contains(projectId)) _dirty.add(projectId);
    if (!isClosed) {
      emit(TimeUsageState(projects: state.projects, saves: state.saves + 1));
    }
    return watch([projectId]);
  }

  /// When [projectId]'s budget runs out at the present pace; null with the
  /// module off or when the read fails. Held like the figures.
  Future<BudgetForecast?> forecast(String projectId) async {
    if (!_enabled()) return null;
    final held = _forecasts[projectId];
    if (held != null && DateTime.now().difference(held.at) <= freshFor) {
      return held.forecast;
    }
    try {
      final forecast = await _repository.forecast(projectId);
      _remember({projectId: forecast});
      return forecast;
    } on Object {
      return null;
    }
  }

  /// The forecast already held for [projectId], without asking.
  BudgetForecast? heldForecast(String projectId) {
    final held = _forecasts[projectId];
    return held != null && DateTime.now().difference(held.at) <= freshFor
        ? held.forecast
        : null;
  }

  void _remember(Map<String, BudgetForecast> forecasts) {
    final at = DateTime.now();
    if (_forecasts.length > 500) _forecasts.clear();
    forecasts.forEach(
      (id, forecast) => _forecasts[id] = (forecast: forecast, at: at),
    );
  }

  /// The fullest budgets, for the dashboard; their forecasts are held.
  Future<TopBudgets> top({
    int limit = 3,
    List<String> projectIds = const [],
  }) async {
    final top = await _repository.top(limit: limit, projectIds: projectIds);
    _remember(top.forecasts);
    return top;
  }

  /// One page of the budget report; its forecasts are held.
  Future<BudgetReportPage> budgetReport({
    int page = 0,
    int size = 20,
    List<String> projectIds = const [],
  }) async {
    final report = await _repository.budgetReport(
      page: page,
      size: size,
      projectIds: projectIds,
    );
    _remember(report.budgets.forecasts);
    return report;
  }

  /// A project's recorded minutes per day.
  Future<BudgetHistory> history(String projectId) =>
      _repository.history(projectId);

  /// An issue's estimate and what it used; null with the module off or when
  /// the read fails, since it is a side note wherever it is shown.
  Future<IssueTimeUsage?> issue(String issueIdOrKey) async {
    if (!_enabled()) return null;
    try {
      return await _repository.issue(issueIdOrKey);
    } on Object {
      return null;
    }
  }

  /// A sprint's budget; null with the module off or when the read fails.
  Future<SprintTimeUsage?> sprint(String sprintId) async {
    if (!_enabled()) return null;
    try {
      return await _repository.sprint(sprintId);
    } on Object {
      return null;
    }
  }

  /// Sets or, with null, removes a sprint's budget; throws what the server
  /// refused.
  Future<SprintTimeUsage> setSprintBudget(String sprintId, int? minutes) =>
      _repository.setSprintBudget(sprintId, minutes);

  /// Forgets everything; for a sign-out, where the next session may be another
  /// server.
  void reset() {
    _fetchedAt.clear();
    _forecasts.clear();
    _dirty.clear();
    if (!isClosed) emit(const TimeUsageState());
  }
}

class TimeUsageState extends Equatable {
  const TimeUsageState({this.projects = const {}, this.saves = 0});

  final Map<String, ProjectTimeUsage> projects;

  /// Counts the saved entries this cubit was told of, for a surface whose
  /// figures it does not hold (a sprint's) to read them again.
  final int saves;

  ProjectTimeUsage? of(String projectId) => projects[projectId];

  TimeUsageState copyWith({
    Map<String, ProjectTimeUsage>? projects,
    Set<String> without = const {},
  }) {
    final next = Map.of(projects ?? this.projects)
      ..removeWhere((id, _) => without.contains(id));
    return TimeUsageState(projects: next, saves: saves);
  }

  @override
  List<Object?> get props => [projects, saves];
}
