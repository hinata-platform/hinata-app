import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/shift_repository.dart';
import '../shift_zones.dart';
import 'shift_actions_cubit.dart' show ShiftActionsCubit;
import 'shift_changes.dart';

/// What can be wrong with the event as typed.
enum ShiftEventProblem { titleMissing, projectMissing, endBeforeStart, tooLong }

/// The longest an event may run (the server's rule).
const Duration kShiftEventMax = Duration(days: 14);

class ShiftEventEditorState extends Equatable {
  const ShiftEventEditorState({
    this.projectId,
    this.projectName,
    this.title = '',
    required this.start,
    required this.end,
    this.location = '',
    this.description = '',
    this.timezone,
    this.selfAssignable = true,
    this.saving = false,
    this.attempted = false,
    this.errorKey,
  });

  final String? projectId;
  final String? projectName;
  final String title;

  /// Start and end as wall clocks in [timezone].
  final DateTime start;
  final DateTime end;

  final String location;
  final String description;

  /// The event's zone; null until the device has said its own.
  final String? timezone;
  final bool selfAssignable;

  final bool saving;
  final bool attempted;
  final String? errorKey;

  ShiftEventEditorState copyWith({
    String? projectId,
    String? projectName,
    String? title,
    DateTime? start,
    DateTime? end,
    String? location,
    String? description,
    String? timezone,
    bool? selfAssignable,
    bool? saving,
    bool? attempted,
    String? errorKey,
    bool clearError = false,
  }) => ShiftEventEditorState(
    projectId: projectId ?? this.projectId,
    projectName: projectName ?? this.projectName,
    title: title ?? this.title,
    start: start ?? this.start,
    end: end ?? this.end,
    location: location ?? this.location,
    description: description ?? this.description,
    timezone: timezone ?? this.timezone,
    selfAssignable: selfAssignable ?? this.selfAssignable,
    saving: saving ?? this.saving,
    attempted: attempted ?? this.attempted,
    errorKey: clearError ? null : errorKey ?? this.errorKey,
  );

  @override
  List<Object?> get props => [
    projectId,
    projectName,
    title,
    start,
    end,
    location,
    description,
    timezone,
    selfAssignable,
    saving,
    attempted,
    errorKey,
  ];
}

/// What saving an event came to: the event, and who collides after a move.
class ShiftEventSaved extends Equatable {
  const ShiftEventSaved(this.event, {this.warnings = const []});

  final ShiftEventDetail event;
  final List<ShiftWarning> warnings;

  @override
  List<Object?> get props => [event, warnings];
}

/// Creates an event or changes one (HIN-160).
///
/// The times are wall clocks in the event's zone. Changing the zone keeps
/// them: "18:00" stays "18:00", now in the other zone, and the instants are
/// worked out from that when the event is saved. The server moves the shifts
/// with the event, so they keep their wall clocks too.
class ShiftEventEditorCubit extends Cubit<ShiftEventEditorState> {
  ShiftEventEditorCubit(
    this._shifts, {
    this.existing,
    String? projectId,
    String? projectName,
    String? deviceZone,
    DateTime? day,
  }) : _deviceZone = deviceZone,
       super(_initial(existing, projectId, projectName, deviceZone, day));

  final ShiftRepository _shifts;

  /// The event being changed; null for a new one.
  final ShiftEventDetail? existing;

  final String? _deviceZone;

  bool get editing => existing != null;

  static ShiftEventEditorState _initial(
    ShiftEventDetail? existing,
    String? projectId,
    String? projectName,
    String? deviceZone,
    DateTime? day,
  ) {
    final e = existing?.summary;
    if (e != null) {
      return ShiftEventEditorState(
        projectId: e.projectId,
        projectName: projectName,
        title: e.title,
        start: e.startsLocal,
        end: e.endsLocal,
        location: e.location ?? '',
        description: e.description ?? '',
        timezone: e.timezone ?? deviceZone,
        selfAssignable: e.selfAssignable,
      );
    }
    final base = day ?? DateTime.now().add(const Duration(days: 7));
    final start = DateTime(base.year, base.month, base.day, 10);
    return ShiftEventEditorState(
      projectId: projectId,
      projectName: projectName,
      start: start,
      end: start.add(const Duration(hours: 8)),
      timezone: deviceZone,
    );
  }

  void setProject(String id, String name) =>
      emit(state.copyWith(projectId: id, projectName: name, clearError: true));

  void setTitle(String value) => emit(state.copyWith(title: value));
  void setLocation(String value) => emit(state.copyWith(location: value));
  void setDescription(String value) => emit(state.copyWith(description: value));
  void setSelfAssignable(bool value) =>
      emit(state.copyWith(selfAssignable: value));

  /// A new start keeps the length; an end before it moves along.
  void setStart(DateTime value) {
    final length = state.end.difference(state.start);
    emit(
      state.copyWith(
        start: value,
        end: length.isNegative ? value : value.add(length),
        clearError: true,
      ),
    );
  }

  void setEnd(DateTime value) =>
      emit(state.copyWith(end: value, clearError: true));

  /// A new zone, keeping the wall clocks.
  void setTimezone(String zone) =>
      emit(state.copyWith(timezone: zone, clearError: true));

  /// Whether saving moves an event that has shifts to another zone, which the
  /// planner is asked to confirm.
  bool get zoneChangeMovesShifts {
    final e = existing;
    if (e == null || e.shifts.isEmpty) return false;
    return (state.timezone ?? '') != (e.summary.timezone ?? '');
  }

  /// When the event will start on this device's clock once saved, for the
  /// confirmation of a zone change.
  Future<DateTime> startOnDevice() async {
    await ShiftZones.ensureLoaded();
    return ShiftZones.toInstant(state.start, state.timezone, _deviceZone);
  }

  ShiftEventProblem? get problem {
    if (state.title.trim().isEmpty) return ShiftEventProblem.titleMissing;
    if (state.projectId == null) return ShiftEventProblem.projectMissing;
    if (!state.end.isAfter(state.start)) {
      return ShiftEventProblem.endBeforeStart;
    }
    if (state.end.difference(state.start) > kShiftEventMax) {
      return ShiftEventProblem.tooLong;
    }
    return null;
  }

  ShiftEventInput _input() => ShiftEventInput(
    title: state.title,
    startsAt: ShiftZones.toInstant(state.start, state.timezone, _deviceZone),
    endsAt: ShiftZones.toInstant(state.end, state.timezone, _deviceZone),
    description: state.description,
    location: state.location,
    timezone: state.timezone,
    selfAssignable: state.selfAssignable,
  );

  /// Saves; the event when it went through, null when it did not (the reason
  /// stays in the state).
  Future<ShiftEventSaved?> save() async {
    if (state.saving) return null;
    emit(state.copyWith(attempted: true, clearError: true));
    if (problem != null) return null;
    emit(state.copyWith(saving: true));
    try {
      if (state.timezone != null && state.timezone != _deviceZone) {
        await ShiftZones.ensureLoaded();
      }
      final input = _input();
      final e = existing;
      final ShiftEventSaved saved;
      if (e == null) {
        saved = ShiftEventSaved(
          await _shifts.createEvent(state.projectId!, input),
        );
      } else {
        final s = e.summary;
        final patch = input.toPatchJson(
          ShiftEventInput(
            title: s.title,
            startsAt: s.startsAt,
            endsAt: s.endsAt,
            description: s.description,
            location: s.location,
            timezone: s.timezone,
            selfAssignable: s.selfAssignable,
          ),
        );
        if (patch.isEmpty) {
          saved = ShiftEventSaved(e);
        } else {
          final change = await _shifts.updateEvent(s.id, patch);
          saved = ShiftEventSaved(change.event, warnings: change.warnings);
        }
      }
      // An event-wide change: every surface of the module reads again.
      ShiftChanges.instance.notify(ShiftChange(shiftId: '', origin: this));
      if (!isClosed) emit(state.copyWith(saving: false));
      return saved;
    } on ApiFailure catch (failure) {
      if (!isClosed) {
        emit(
          state.copyWith(
            saving: false,
            errorKey: ShiftActionsCubit.errorKeyOf(failure),
          ),
        );
      }
      return null;
    } catch (_) {
      if (!isClosed) {
        emit(state.copyWith(saving: false, errorKey: 'errors.unexpected'));
      }
      return null;
    }
  }
}
