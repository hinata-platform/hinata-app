import 'dart:async';

/// Runs the last of a burst of calls once the burst has paused for [delay],
/// so a search follows typing without running once per key.
class KbDebouncer {
  KbDebouncer({this.delay = const Duration(milliseconds: 180)});

  final Duration delay;
  Timer? _timer;

  /// Runs [action] after [delay], dropping one still waiting. [immediately]
  /// runs it now and drops the waiting one too, for a change that should
  /// show at once (a cleared field).
  void run(void Function() action, {bool immediately = false}) {
    _timer?.cancel();
    _timer = null;
    if (immediately) {
      action();
    } else {
      _timer = Timer(delay, action);
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
