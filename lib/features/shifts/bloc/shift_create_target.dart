import 'package:equatable/equatable.dart';

import '../../../core/models/shift_models.dart';
import '../../../core/util/dates.dart' show addDays;

/// Where a shift swept out on the calendar, or asked for with its "+", goes
/// (HIN-166): the planner's events the time touches, worked out from what the
/// calendar already holds, so asking costs no request.
///
/// One event: the shift editor opens on it straight away. Several: the
/// planner picks one. None: the calendar offers a new event with this time.
class ShiftCreateTarget extends Equatable {
  const ShiftCreateTarget({
    required this.start,
    required this.end,
    this.events = const [],
    this.wholeDay = false,
  });

  /// The span asked for, as instants on the device's clock (what the grid
  /// draws in).
  final DateTime start;
  final DateTime end;

  /// The events on offer, earliest first: only ones the caller plans, never
  /// cancelled ones, and within the calendar's project filter.
  final List<ShiftEventSummary> events;

  /// Whether the events were looked for on the whole day of [start] rather
  /// than at the time itself: the "+" knows the day, not the hour.
  final bool wholeDay;

  /// The one event that is preselected, if exactly one fits.
  ShiftEventSummary? get only => events.length == 1 ? events.single : null;

  bool get none => events.isEmpty;

  /// The events [held] holds that [start] to [end] touches.
  ///
  /// Touches, not lies inside: a sweep that runs past the event's end still
  /// offers the event, and the shift editor says the shift is outside it
  /// rather than the calendar cutting it short. [plannable] are the projects
  /// the caller plans, [projectId] the filter of the calendar; an event is
  /// offered only when the server said the caller plans it and its project
  /// is in both.
  static ShiftCreateTarget resolve({
    required DateTime start,
    required DateTime end,
    required Iterable<ShiftEventSummary> held,
    required Set<String> plannable,
    String? projectId,
    bool wholeDay = false,
  }) {
    final from = wholeDay
        ? DateTime(start.year, start.month, start.day)
        : start;
    final until = wholeDay ? addDays(from, 1) : end;
    final seen = <String>{};
    final events = <ShiftEventSummary>[
      for (final event in held)
        if (seen.add(event.id) &&
            !event.cancelled &&
            event.canPlan &&
            plannable.contains(event.projectId) &&
            (projectId == null || event.projectId == projectId) &&
            event.startsAt.isBefore(until) &&
            event.endsAt.isAfter(from))
          event,
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return ShiftCreateTarget(
      start: start,
      end: end,
      events: events,
      wholeDay: wholeDay,
    );
  }

  /// The span the shift editor opens with for [event].
  ///
  /// What was asked for, unless the events were found by the day and the hour
  /// asked for misses [event]: then an hour from where the event begins on
  /// that day, never past its end.
  ({DateTime start, DateTime end}) spanFor(ShiftEventSummary event) {
    final touches = event.startsAt.isBefore(end) && event.endsAt.isAfter(start);
    if (!wholeDay || touches) return (start: start, end: end);
    final dayStart = DateTime(start.year, start.month, start.day);
    final from = event.startsAt.isAfter(dayStart) ? event.startsAt : dayStart;
    final length = end.difference(start);
    final until = from.add(length);
    return (
      start: from,
      end: until.isAfter(event.endsAt) ? event.endsAt : until,
    );
  }

  @override
  List<Object?> get props => [start, end, events, wholeDay];
}
