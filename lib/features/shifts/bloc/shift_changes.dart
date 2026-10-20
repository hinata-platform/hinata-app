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
