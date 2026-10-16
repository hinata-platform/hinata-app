import 'timer_surface_state.dart';

/// The arithmetic of the one notification planned for the end of an interval.
///
/// There is only ever one: the next phase of a Pomodoro does not exist before
/// the person turns to it, so nothing can be planned beyond the current one.
abstract final class PhaseEndSchedule {
  /// The id of the planned notification on every platform.
  static const int notificationId = 7100;

  /// After the end, so the app in front gets to cancel it first when its own
  /// toast says the same thing.
  static const Duration grace = Duration(seconds: 2);

  /// How long a delivered notification stays before the system drops it.
  static const Duration expiry = Duration(minutes: 10);

  /// When the notification for [state] fires, in UTC; null when there is
  /// nothing to plan (no end, switched off, or already over at [now]). Also
  /// null while an alarm says it instead (iOS 26, HIN-106).
  static DateTime? fireAt(TimerSurfaceState state, DateTime now) =>
      state.alarmMode ? null : _endAt(state, now);

  /// When the alarm for [state] rings: the same moment the notification
  /// would come, so the app in front withdraws it first as well.
  static DateTime? alarmAt(TimerSurfaceState state, DateTime now) =>
      state.alarmMode ? _endAt(state, now) : null;

  static DateTime? _endAt(TimerSurfaceState state, DateTime now) {
    final endsAt = state.endsAt;
    if (!state.running || !state.phaseEndNotification || endsAt == null) {
      return null;
    }
    final at = endsAt.toUtc().add(grace);
    return at.isAfter(now.toUtc()) ? at : null;
  }
}

/// What to do with the planned notification when the state changes.
sealed class PhaseEndAction {
  const PhaseEndAction();
}

/// Leave whatever is planned alone.
class PhaseEndKeep extends PhaseEndAction {
  const PhaseEndKeep();
}

/// Withdraw the planned notification.
class PhaseEndCancel extends PhaseEndAction {
  const PhaseEndCancel();
}

/// Plan (or re-plan) the notification for [at].
class PhaseEndPlan extends PhaseEndAction {
  const PhaseEndPlan(this.at);

  final DateTime at;
}

/// Remembers what is planned, so applying the same state twice plans once.
class PhaseEndPlanner {
  DateTime? _planned;

  DateTime? get planned => _planned;

  PhaseEndAction next(TimerSurfaceState state, DateTime now) {
    final at = PhaseEndSchedule.fireAt(state, now);
    if (at == _planned) return const PhaseEndKeep();
    final previous = _planned;
    _planned = at;
    if (at == null) {
      if (previous == null) return const PhaseEndKeep();
      // A countdown stops itself the moment it ends, a grace period before its
      // notification fires. Withdrawing it then would mean an app running in
      // the background never says the interval is over; a notification that
      // is due stays. In front, [TimerSurface.phaseEnded] withdraws it.
      final due = !previous.isAfter(
        now.toUtc().add(PhaseEndSchedule.grace + const Duration(seconds: 1)),
      );
      return due ? const PhaseEndKeep() : const PhaseEndCancel();
    }
    return PhaseEndPlan(at);
  }

  /// Forgets the plan, after the notification was withdrawn or delivered.
  void reset() => _planned = null;
}
