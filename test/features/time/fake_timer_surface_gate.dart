import 'package:hinata/core/timer_surfaces/surface_platform.dart';
import 'package:hinata/features/time/timer_surface_options.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

/// A permission gate that answers from fields, so no test reaches a plugin.
class FakeTimerSurfaceGate extends TimerSurfacePermissionGate {
  FakeTimerSurfaceGate({this.grants = true, this.exact = false});

  bool grants;
  bool exact;
  int requests = 0;
  int exactRequests = 0;

  @override
  Future<bool> request(SurfacePlatform platform) async {
    requests++;
    return grants;
  }

  @override
  Future<bool> canScheduleExact(SurfacePlatform platform) async => exact;

  @override
  Future<void> requestExact(SurfacePlatform platform) async {
    exactRequests++;
  }

  @override
  Uri? settingsUri(SurfacePlatform platform) => null;
}

/// A hydrated-bloc store that lives for one test.
class MemoryStorage implements Storage {
  final Map<String, dynamic> _values = {};

  @override
  dynamic read(String key) => _values[key];

  @override
  Future<void> write(String key, dynamic value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> clear() async => _values.clear();

  @override
  Future<void> close() async {}
}
