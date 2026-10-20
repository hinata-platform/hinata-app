import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/shift_repository.dart';
import 'shift_actions_cubit.dart' show ShiftActionsCubit;
import 'shift_changes.dart';

/// What one planner action came to.
class ShiftPlanOutcome extends Equatable {
  const ShiftPlanOutcome.done(
    this.messageKey, {
    this.shift,
    this.event,
    this.absent = false,
    this.warnings = const [],
  }) : errorKey = null,
       errorDetails = const {};

  const ShiftPlanOutcome.failed(this.errorKey, {this.errorDetails = const {}})
    : messageKey = null,
      shift = null,
      event = null,
      absent = false,
      warnings = const [];

  final String? messageKey;
  final String? errorKey;

  /// The refusal's details, for a message that names a number.
  final Map<String, String> errorDetails;

  /// The shift as it now stands, where the answer carried it.
  final Shift? shift;

  /// The event as it now stands, after a cancellation.
  final ShiftEventDetail? event;

  /// The person put on the shift is entered as absent that day (only said to
  /// a planner who may see absences; the server decides).
  final bool absent;

  /// Who now collides after a change.
  final List<ShiftWarning> warnings;

  bool get ok => errorKey == null;

  @override
  List<Object?> get props => [
    messageKey,
    errorKey,
    errorDetails,
    shift,
    event,
    absent,
    warnings,
  ];
}

/// Which planner actions are running, by what they act on, so their buttons
/// show progress and cannot be pressed twice.
class ShiftPlanningState extends Equatable {
  const ShiftPlanningState({this.busy = const {}});

  final Set<String> busy;

  bool isBusy(String id) => busy.contains(id);

  @override
  List<Object?> get props => [busy];
}

/// The planner's actions outside the editors (HIN-160): put somebody on a
/// shift, take somebody off, delete a shift, call an event off, delete it.
/// Each announces itself on [ShiftChanges], like the helper's actions.
class ShiftPlanningCubit extends Cubit<ShiftPlanningState> {
  ShiftPlanningCubit(this._shifts) : super(const ShiftPlanningState());

  final ShiftRepository _shifts;

  Future<ShiftPlanOutcome> assign(Shift shift, String userId) =>
      _run(shift.id, () async {
        final result = await _shifts.assign(shift.id, userId);
        return ShiftPlanOutcome.done(
          'shifts.plan.done.assigned',
          shift: result.shift,
          absent: result.absent,
        );
      });

  /// Takes the person of [place] off [shift] (the server's `release`).
  Future<ShiftPlanOutcome> remove(Shift shift, ShiftPlace place) =>
      _run(shift.id, () async {
        final result = await _shifts.release(place.id);
        return ShiftPlanOutcome.done(
          'shifts.plan.done.removed',
          shift: result?.shift,
        );
      });

  /// [scope] where the shift's event is an occurrence of a series.
  Future<ShiftPlanOutcome> deleteShift(Shift shift, {ShiftScope? scope}) =>
      _run(shift.id, () async {
        await _shifts.deleteShift(shift.id, scope: scope);
        return const ShiftPlanOutcome.done('shifts.plan.done.shiftDeleted');
      }, eventWide: scope == ShiftScope.future);

  Future<ShiftPlanOutcome> cancelEvent(String eventId, {ShiftScope? scope}) =>
      _run(eventId, () async {
        final event = await _shifts.cancelEvent(eventId, scope: scope);
        return ShiftPlanOutcome.done(
          'shifts.plan.done.eventCancelled',
          event: event,
        );
      }, eventWide: true);

  Future<ShiftPlanOutcome> deleteEvent(String eventId, {ShiftScope? scope}) =>
      _run(eventId, () async {
        await _shifts.deleteEvent(eventId, scope: scope);
        return const ShiftPlanOutcome.done('shifts.plan.done.eventDeleted');
      }, eventWide: true);

  Future<ShiftPlanOutcome> _run(
    String id,
    Future<ShiftPlanOutcome> Function() action, {
    bool eventWide = false,
  }) async {
    if (state.isBusy(id)) {
      return const ShiftPlanOutcome.failed('shifts.action.busy');
    }
    emit(ShiftPlanningState(busy: {...state.busy, id}));
    try {
      final outcome = await action();
      ShiftChanges.instance.notify(
        // An event-wide change names no shift: every surface reads again.
        ShiftChange(
          shiftId: eventWide ? '' : id,
          shift: outcome.shift,
          origin: this,
        ),
      );
      return outcome;
    } on ApiFailure catch (failure) {
      return ShiftPlanOutcome.failed(
        ShiftActionsCubit.errorKeyOf(failure),
        errorDetails: failure.details,
      );
    } catch (_) {
      return const ShiftPlanOutcome.failed('errors.unexpected');
    } finally {
      if (!isClosed) {
        emit(ShiftPlanningState(busy: {...state.busy}..remove(id)));
      }
    }
  }
}
