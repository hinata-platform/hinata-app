import 'package:flutter/foundation.dart';

import '../repositories/project_repository.dart';
import '../timer_surfaces/adapters/app_intents_surface.dart';

/// The projects Siri and the Shortcuts app offer for a timer start (HIN-105).
///
/// Only the person's visible projects, by name, at most [limit], with id and
/// name and nothing else. Read again when it is older than [maxAge] and the
/// app comes to the front or signs in, at once for another server or person;
/// no sync in the background. Signing out and "Delete now" remove it
/// ([clear]), and [invalidate] drops an answer still on its way.
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
  String? _owner;
  bool _loading = false;

  /// The list last handed to the system, so an unchanged one is not written
  /// again (each write rebuilds the App Shortcuts' parameters).
  List<IntentProject>? _written;

  /// Bumped by [invalidate]; an answer read under an older one is dropped.
  int _generation = 0;

  /// Reads the projects again unless the last read of the same [owner]
  /// (server and person) is younger than [maxAge].
  Future<void> refresh({String? owner}) async {
    final at = _at;
    final fresh =
        owner == _owner && at != null && _clock().difference(at) < maxAge;
    if (_loading || fresh) return;
    _loading = true;
    final generation = _generation;
    try {
      // Another server or person: the last one's projects go first, so a
      // failed read never leaves them offered under the new account.
      if (_owner != null && owner != _owner) {
        _owner = null;
        _written = null;
        await _channel.setProjects(null);
      }
      final projects = await _read();
      if (generation != _generation) return;
      if (!listEquals(projects, _written)) {
        await _channel.setProjects(projects);
        _written = projects;
      }
      _at = _clock();
      _owner = owner;
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

  /// Signed out, or the local copies deleted: the list goes from the device.
  Future<void> clear() async {
    invalidate();
    _owner = null;
    _written = null;
    try {
      await _channel.setProjects(null);
    } catch (error) {
      debugPrint('Intent projects not removed: $error');
    }
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
