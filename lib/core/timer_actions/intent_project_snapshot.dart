import 'package:flutter/foundation.dart';

import '../repositories/project_repository.dart';
import '../timer_surfaces/adapters/app_intents_surface.dart';

/// The projects Siri and the Shortcuts app offer for a timer start (HIN-105).
///
/// Only the person's visible projects, by name, at most [limit], with id and
/// name and nothing else. Read again when it is older than [maxAge] and the
/// app comes to the front or signs in; no sync in the background. Signing out
/// removes it ([AppIntentsSurface.clear]), and [invalidate] drops an answer
/// still on its way.
class IntentProjectSnapshot {
  IntentProjectSnapshot(
    this._projects, {
    AppIntentsChannel channel = const AppIntentsChannel(),
    this.maxAge = const Duration(minutes: 15),
    DateTime Function() clock = DateTime.now,
  }) : _channel = channel,
       _clock = clock;

  static const int limit = 200;

  /// What the server hands out per page.
  static const int pageSize = 100;

  final ProjectRepository _projects;
  final AppIntentsChannel _channel;
  final Duration maxAge;
  final DateTime Function() _clock;

  DateTime? _at;
  bool _loading = false;

  /// Bumped by [invalidate]; an answer read under an older one is dropped.
  int _generation = 0;

  /// Reads the projects again unless the last read is younger than [maxAge].
  Future<void> refresh() async {
    final at = _at;
    if (_loading || (at != null && _clock().difference(at) < maxAge)) return;
    _loading = true;
    final generation = _generation;
    try {
      final projects = await _read();
      if (generation != _generation) return;
      await _channel.setProjects(projects);
      _at = _clock();
    } catch (error) {
      debugPrint('Intent projects not refreshed: $error');
    } finally {
      _loading = false;
    }
  }

  /// Signed out or the module off: forget the last read and drop one that is
  /// still on its way.
  void invalidate() {
    _generation++;
    _at = null;
  }

  Future<List<IntentProject>> _read() async {
    final all = <IntentProject>[];
    for (var page = 0; all.length < limit; page++) {
      final (:projects, :total) = await _projects.searchProjects(
        page: page,
        size: pageSize,
      );
      all.addAll(
        projects
            .where((project) => !project.template)
            .map((project) => (id: project.id, name: project.name)),
      );
      if (projects.length < pageSize || (page + 1) * pageSize >= total) break;
    }
    return all.take(limit).toList();
  }
}
