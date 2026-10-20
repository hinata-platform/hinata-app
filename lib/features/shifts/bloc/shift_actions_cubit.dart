import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/shift_repository.dart';
import 'shift_changes.dart';

/// What one action came to: a message to say, and the shift as it now stands.
class ShiftActionOutcome extends Equatable {
  const ShiftActionOutcome.done(
    this.messageKey, {
    this.shift,
    this.myShift,
    this.absent = false,
  }) : errorKey = null;

  const ShiftActionOutcome.failed(this.errorKey)
    : messageKey = null,
      shift = null,
      myShift = null,
      absent = false;

  final String? messageKey;
  final String? errorKey;
  final Shift? shift;

  /// The caller's place after a confirmation.
  final MyShift? myShift;

  /// The caller is entered as absent on that day.
  final bool absent;

  bool get ok => errorKey == null;

  @override
  List<Object?> get props => [messageKey, errorKey, shift, myShift, absent];
}

/// The shifts being acted on right now, so their buttons show progress and
/// cannot be pressed twice.
class ShiftActionsState extends Equatable {
  const ShiftActionsState({this.busy = const {}});

  final Set<String> busy;

  bool isBusy(String shiftId) => busy.contains(shiftId);

  @override
  List<Object?> get props => [busy];
}

/// The one place the helper's four actions run (HIN-44): sign up, confirm,
/// decline, give up. Each announces itself on [ShiftChanges] so every surface
/// of the module catches up.
class ShiftActionsCubit extends Cubit<ShiftActionsState> {
  ShiftActionsCubit(this._shifts, {ShiftChanges? changes})
    : _changes = changes ?? ShiftChanges.instance,
      super(const ShiftActionsState());

  final ShiftRepository _shifts;
  final ShiftChanges _changes;

  /// The key a refusal is shown with: the module's own code where the server
  /// sent one, so the app says it in its own words, else the server's text.
  static String errorKeyOf(ApiFailure failure) {
    final code = failure.details['code'];
    if (code != null && code.startsWith('error.shifts.')) return code;
    return failure.message;
  }

  Future<ShiftActionOutcome> join(Shift shift) => _run(shift.id, () async {
    final result = await _shifts.selfAssign(shift.id);
    return ShiftActionOutcome.done(
      'shifts.done.joined',
      shift: result.shift,
      absent: result.absent,
    );
  });

  Future<ShiftActionOutcome> confirm(String shiftId, String assignmentId) =>
      _run(shiftId, () async {
        final mine = await _shifts.confirm(assignmentId);
        return ShiftActionOutcome.done(
          'shifts.done.confirmed',
          shift: mine.shift.copyWith(
            mine: true,
            myAssignmentId: mine.assignmentId,
            myStatus: mine.status,
          ),
          myShift: mine,
        );
      });

  Future<ShiftActionOutcome> decline(String shiftId, String assignmentId) =>
      _run(shiftId, () async {
        final result = await _shifts.decline(assignmentId);
        return ShiftActionOutcome.done(
          'shifts.done.declined',
          shift: result?.shift,
        );
      });

  Future<ShiftActionOutcome> release(String shiftId, String assignmentId) =>
      _run(shiftId, () async {
        final result = await _shifts.release(assignmentId);
        return ShiftActionOutcome.done(
          'shifts.done.released',
          shift: result?.shift,
        );
      });

  Future<ShiftActionOutcome> _run(
    String shiftId,
    Future<ShiftActionOutcome> Function() action,
  ) async {
    if (state.isBusy(shiftId)) {
      return const ShiftActionOutcome.failed('shifts.action.busy');
    }
    emit(ShiftActionsState(busy: {...state.busy, shiftId}));
    try {
      final outcome = await action();
      _changes.notify(
        ShiftChange(shiftId: shiftId, shift: outcome.shift, origin: this),
      );
      return outcome;
    } on ApiFailure catch (failure) {
      return ShiftActionOutcome.failed(errorKeyOf(failure));
    } catch (_) {
      return const ShiftActionOutcome.failed('errors.unexpected');
    } finally {
      if (!isClosed) {
        emit(ShiftActionsState(busy: {...state.busy}..remove(shiftId)));
      }
    }
  }
}
