import 'package:hinata/core/timer_surfaces/timer_surface.dart';

/// Records what a surface asked of the app.
class FakeHost implements TimerSurfaceHost {
  final List<String> calls = [];

  @override
  bool get isForeground => true;

  @override
  Future<void> end() async => calls.add('end');

  @override
  Future<void> start() async => calls.add('start');

  @override
  Future<void> advancePhase() async => calls.add('advance');

  @override
  void openFocus() => calls.add('focus');

  @override
  void openRoute(String route) => calls.add('route $route');

  @override
  Future<void> showWindow() async => calls.add('show');

  @override
  Future<void> quit() async => calls.add('quit');
}
