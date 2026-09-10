import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/time_approval_models.dart';
import '../models/time_policy_models.dart';
import '../repositories/time_repository.dart';

/// The operator's time-tracking rules, held once for the whole app.
///
/// Four readers need the same answer — the entry sheet marking a required
/// field and choosing whether the tag picker offers "create it", the list
/// drawing a lock on a frozen day, the timesheet grid refusing to compose into
/// one, and the timer bar deciding whether stopping is a question for the
/// person before it is a request to the server — and a value each of them read
/// for itself would be four requests and four ways to be stale.
///
/// The bar is the newest of them and the one that reads it for a decision
/// rather than for a mark. A timer starts with nothing and may be stopped
/// hours later against rules that have changed in between, so the bar's copy
/// can be wrong in a way the others' cannot: it is refreshed on a refusal —
/// see `endTimerAndAdvise` — rather than trusted for ever.
///
/// It starts on [TimePolicySnapshot.none], which is what a fresh instance
/// demands: nothing. That is the safe direction to be wrong in. Assuming a
/// field is required when it is not blocks a save the server would have
/// accepted, with no way for the person to find out why; assuming it is not
/// costs one refusal that names the field.
class TimePolicyCubit extends Cubit<TimePolicySnapshot> {
  TimePolicyCubit(this._time) : super(TimePolicySnapshot.none);

  final TimeRepository _time;

  /// Whether a load has already succeeded, so the screens that ask on open do
  /// not each pay for a request.
  bool _loaded = false;
  Future<void>? _inFlight;

  /// Reads the policy once. Repeated calls while a read is in flight join it.
  ///
  /// Callers await it only when they cannot draw without it; the rest fire it
  /// and rebuild on the emit.
  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  /// Re-reads it — after an administrator saves the settings, and whenever the
  /// module is switched on while the app is running.
  Future<void> refresh() {
    _loaded = false;
    return ensureLoaded();
  }

  /// Forgets the rules of the session that just ended.
  ///
  /// A new sign-in may be against another server with another lock date, and a
  /// stale one would grey out a day that is perfectly editable there.
  void reset() {
    _loaded = false;
    _inFlight = null;
    if (state != TimePolicySnapshot.none) emit(TimePolicySnapshot.none);
  }

  Future<void> _load() async {
    try {
      final policy = await _time.policy();
      _loaded = true;
      // The freezing submissions come with the rules, because "is this day of
      // mine frozen" is asked by the list, the entry sheet, the timesheet cell
      // and the calendar — and a copy each would be four requests and four ways
      // to be stale. Only when the instance has approvals at all: on every other
      // instance the route does not exist and the answer is already known.
      final withPeriods = policy.approvalsEnabled
          ? policy.withFrozenPeriods(await _frozenPeriods())
          : policy;
      if (!isClosed && withPeriods != state) emit(withPeriods);
    } catch (_) {
      // Nothing here is worth an error message: with the module off the route
      // does not exist, and with a server that cannot answer, "nothing is
      // required" is both the old behaviour and the one that lets people work.
      // The next screen that opens asks again.
    }
  }

  /// The reader's own submissions that make something immutable.
  ///
  /// One page, and the page is the bound: a hundred submissions is years of them,
  /// and a period older than that is behind the lock date anyway. A failure here
  /// is not a failure of the rules — the policy still emits, and a lock the app
  /// did not draw is one the server still refuses, which is the safe direction.
  Future<List<TimesheetApproval>> _frozenPeriods() async {
    try {
      final page = await _time.approvals(scope: 'mine', size: 100);
      return [
        for (final approval in page.items)
          if (approval.status.freezes) approval,
      ];
    } catch (_) {
      return const [];
    }
  }
}
