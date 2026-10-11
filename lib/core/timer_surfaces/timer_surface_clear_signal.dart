import 'dart:ui';

/// "Delete local copies now": a request to clear every surface outside the
/// app at once, from the settings to the host that owns the surfaces.
///
/// Not a `Listenable` on purpose: it is handed down as a plain service, and
/// nothing rebuilds when it fires.
class TimerSurfaceClearSignal {
  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void request() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void dispose() => _listeners.clear();
}
