import 'dart:async';

import '../../../core/models/shift_models.dart';

/// One change to somebody's place on a shift, made from anywhere in the
/// module: the row, the hero, the sheet.
class ShiftChange {
  const ShiftChange({required this.shiftId, this.shift, this.origin});

  final String shiftId;

  /// The shift as it now stands, when the answer carried it.
  final Shift? shift;

  /// Who made the change, so a surface that already applied it can skip it.
  final Object? origin;
}

/// The module's own in-app bus, the way `IssueEvents` is the issues'.
///
/// A sign-up in the sheet over the event page has to reach "Meine Schichten"
/// behind it, which holds no handle to the sheet. Listeners debounce, so a
/// burst of changes costs one reload.
class ShiftChanges {
  ShiftChanges._();

  static final ShiftChanges instance = ShiftChanges._();

  final StreamController<ShiftChange> _controller =
      StreamController<ShiftChange>.broadcast();

  Stream<ShiftChange> get changes => _controller.stream;

  void notify(ShiftChange change) => _controller.add(change);
}

/// Collects a burst of [ShiftChanges] into one call of [onSettled], [delay]
/// after the last one.
class ShiftChangeDebouncer {
  ShiftChangeDebouncer(
    this.onSettled, {
    Stream<ShiftChange>? changes,
    this.delay = const Duration(milliseconds: 250),
  }) {
    _sub = (changes ?? ShiftChanges.instance.changes).listen(_on);
  }

  final void Function(List<ShiftChange> changes) onSettled;
  final Duration delay;
  late final StreamSubscription<ShiftChange> _sub;
  final List<ShiftChange> _pending = [];
  Timer? _timer;

  void _on(ShiftChange change) {
    _pending.add(change);
    _timer?.cancel();
    _timer = Timer(delay, () {
      final batch = List<ShiftChange>.of(_pending);
      _pending.clear();
      onSettled(batch);
    });
  }

  Future<void> cancel() async {
    _timer?.cancel();
    await _sub.cancel();
  }
}

/// For a view the module keeps built behind the others: what a change asks to
/// read again waits until the view is on screen, and is read then.
///
/// A change made in one view used to reload every view kept alive, seen or
/// not. Now a hidden view only notes that it is stale; [refreshStale] runs
/// once it is shown, as often as changes arrived meanwhile: one time.
mixin ShiftStaleWhileHidden {
  bool _visible = true;
  bool _stale = false;

  /// Whether the view is the one on screen.
  bool get visible => _visible;

  /// Told by the view as it is shown and hidden.
  void setVisible(bool visible) {
    if (visible == _visible) return;
    _visible = visible;
    if (visible && _stale) {
      _stale = false;
      refreshStale();
    }
  }

  /// Reads again now when on screen, else once the view is shown.
  void markStale() {
    if (_visible) {
      refreshStale();
    } else {
      _stale = true;
    }
  }

  /// Reads what changed while the view was hidden, or just now.
  void refreshStale();
}
