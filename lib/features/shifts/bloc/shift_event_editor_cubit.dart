import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/models/shift_series.dart';
import '../../../core/repositories/shift_repository.dart';
import '../shift_zones.dart';
import 'shift_actions_cubit.dart' show ShiftActionsCubit;
import 'shift_changes.dart';

/// What can be wrong with the event as typed.
enum ShiftEventProblem { titleMissing, projectMissing, endBeforeStart, tooLong }

/// The longest an event may run (the server's rule).
const Duration kShiftEventMax = Duration(days: 14);

/// What "Wiederholen" is set to (HIN-161). The presets follow the start: a
/// weekly event moved to a Tuesday repeats on Tuesdays.
enum SeriesRepeat { never, daily, weekly, monthly, custom }

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
    this.repeat = SeriesRepeat.never,
    this.customRule,
    this.seriesRule,
    this.preview,
    this.previewing = false,
    this.previewErrorKey,
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

  /// "Wiederholen", and the rule behind "Eigene Regel".
  final SeriesRepeat repeat;
  final SeriesRule? customRule;

  /// The rule the series of the occurrence being changed has, once read.
  final SeriesRule? seriesRule;

  /// What the server makes of the rule: its words and the next dates.
  final SeriesPreview? preview;
  final bool previewing;
  final String? previewErrorKey;

  /// The rule as it stands, or null for "Nie".
  SeriesRule? get rule => switch (repeat) {
    SeriesRepeat.never => null,
    SeriesRepeat.daily => const SeriesRule.daily(),
    SeriesRepeat.weekly => SeriesRule.weekly(start),
    SeriesRepeat.monthly => SeriesRule.monthly(start),
    SeriesRepeat.custom => _filled(customRule ?? SeriesRule.weekly(start)),
  };

  /// A weekly rule without days repeats on the start's weekday, a monthly one
  /// without a day on the start's day.
  SeriesRule _filled(SeriesRule r) => switch (r.frequency) {
    SeriesFrequency.weekly when r.weekdays.isEmpty => r.copyWith(
      weekdays: {start.weekday},
    ),
    SeriesFrequency.monthly when r.monthDay == null => r.copyWith(
      monthDay: start.day,
    ),
    _ => r,
  };

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
    SeriesRepeat? repeat,
    SeriesRule? customRule,
    SeriesRule? seriesRule,
    SeriesPreview? preview,
    bool clearPreview = false,
    bool? previewing,
    String? previewErrorKey,
    bool clearPreviewError = false,
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
    repeat: repeat ?? this.repeat,
    customRule: customRule ?? this.customRule,
    seriesRule: seriesRule ?? this.seriesRule,
    preview: clearPreview ? null : preview ?? this.preview,
    previewing: previewing ?? this.previewing,
    previewErrorKey: clearPreviewError
        ? null
        : previewErrorKey ?? this.previewErrorKey,
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
    repeat,
    customRule,
    seriesRule,
    preview,
    previewing,
    previewErrorKey,
  ];
}

/// What saving an event came to: the event, and who collides after a move;
/// for a new series the series and the id of its first occurrence, where it
/// could be found.
class ShiftEventSaved extends Equatable {
  const ShiftEventSaved(
    this.event, {
    this.warnings = const [],
    this.series,
    this.firstEventId,
  });

  final ShiftEventDetail? event;
  final List<ShiftWarning> warnings;
  final ShiftSeries? series;
  final String? firstEventId;

  /// The event to open next, if there is one.
  String? get eventId => event?.summary.id ?? firstEventId;

  @override
  List<Object?> get props => [event, warnings, series, firstEventId];
}

/// Creates an event or changes one (HIN-160).
///
/// The times are wall clocks in the event's zone. Changing the zone keeps
/// them: "18:00" stays "18:00", now in the other zone, and the instants are
/// worked out from that when the event is saved. The server moves the shifts
/// with the event, so they keep their wall clocks too.
///
/// "Wiederholen" (HIN-161) turns a new event into a series. What the rule
/// reads like comes from the server's preview, asked a moment after the last
/// change ([previewDelay]); the cubit builds the rule, never its words. An
/// occurrence of a series is saved with a [ShiftScope] the planner picked; a
/// changed rule only ever applies to the occurrences from this one on.
class ShiftEventEditorCubit extends Cubit<ShiftEventEditorState> {
  ShiftEventEditorCubit(
    this._shifts, {
    this.existing,
    String? projectId,
    String? projectName,
    String? deviceZone,
    DateTime? day,
    ({DateTime start, DateTime end})? deviceSpan,
    this.previewDelay = const Duration(milliseconds: 400),
  }) : assert(day == null || deviceSpan == null, 'a day or a span, not both'),
       assert(
         deviceSpan == null || deviceSpan.end.isAfter(deviceSpan.start),
         'a span ends after it starts',
       ),
       _deviceZone = deviceZone,
       super(
         _initial(
           existing,
           projectId,
           projectName,
           deviceZone,
           day,
           deviceSpan,
         ),
       );

  final ShiftRepository _shifts;

  /// How long the form has to rest before the preview is asked.
  final Duration previewDelay;

  Timer? _previewTimer;
  int _previewTicket = 0;

  /// The event being changed; null for a new one.
  final ShiftEventDetail? existing;

  final String? _deviceZone;

  bool get editing => existing != null;

  /// The occurrence being changed belongs to a series.
  bool get inSeries => existing?.summary.inSeries ?? false;

  /// Whether "Wiederholen" is offered: for a new event, and for an
  /// occurrence (a single event cannot become a series afterwards).
  bool get canRepeat => existing == null || inSeries;

  /// Reads the rule of the occurrence's series, so "Wiederholen" opens on
  /// it. Without it the field still shows the server's words.
  Future<void> loadSeries() async {
    final id = existing?.summary.seriesId;
    if (id == null) return;
    try {
      final rule = (await _shifts.series(id)).rule;
      if (rule == null || isClosed) return;
      emit(
        state.copyWith(
          seriesRule: rule,
          repeat: _presetOf(rule, state.start),
          customRule: rule,
        ),
      );
    } catch (_) {
      // The field keeps the server's words; the rule just cannot be changed.
    }
  }

  static SeriesRepeat _presetOf(SeriesRule rule, DateTime start) {
    if (rule == const SeriesRule.daily()) return SeriesRepeat.daily;
    if (rule == SeriesRule.weekly(start)) return SeriesRepeat.weekly;
    if (rule == SeriesRule.monthly(start)) return SeriesRepeat.monthly;
    return SeriesRepeat.custom;
  }

  /// Whether the rule differs from the series' (an occurrence only).
  bool get ruleChanged {
    final before = state.seriesRule;
    return inSeries && before != null && state.rule != before;
  }

  /// Sets "Wiederholen"; [custom] is the rule behind "Eigene Regel".
  void setRepeat(SeriesRepeat repeat, {SeriesRule? custom}) {
    emit(
      state.copyWith(
        repeat: repeat,
        customRule: custom,
        clearError: true,
        clearPreview: repeat == SeriesRepeat.never,
        clearPreviewError: true,
      ),
    );
    _schedulePreview();
  }

  /// Whether the server's words are wanted: a new series, or a new rule.
  bool get _wantsPreview =>
      state.rule != null &&
      state.projectId != null &&
      (existing == null || ruleChanged);

  void _schedulePreview() {
    _previewTimer?.cancel();
    if (!_wantsPreview) {
      _previewTicket++;
      if (state.previewing) emit(state.copyWith(previewing: false));
      return;
    }
    emit(state.copyWith(previewing: true));
    _previewTimer = Timer(previewDelay, () => unawaited(_preview()));
  }

  Future<void> _preview() async {
    final ticket = ++_previewTicket;
    try {
      final zone = state.timezone;
      if (zone != null && zone != _deviceZone) await ShiftZones.ensureLoaded();
      final preview = await _shifts.previewSeries(state.projectId!, _draft());
      if (isClosed || ticket != _previewTicket) return;
      emit(
        state.copyWith(
          preview: preview,
          previewing: false,
          clearPreviewError: true,
        ),
      );
    } on ApiFailure catch (failure) {
      if (isClosed || ticket != _previewTicket) return;
      emit(
        state.copyWith(
          previewing: false,
          clearPreview: true,
          previewErrorKey: ShiftActionsCubit.errorKeyOf(failure),
        ),
      );
    } catch (_) {
      if (isClosed || ticket != _previewTicket) return;
      emit(state.copyWith(previewing: false, clearPreview: true));
    }
  }

  SeriesDraft _draft() {
    return SeriesDraft(
      title: state.title,
      firstStart: state.start,
      durationMinutes: state.end.difference(state.start).inMinutes,
      rule: state.rule!,
      description: state.description,
      location: state.location,
      timezone: state.timezone,
      selfAssignable: state.selfAssignable,
    );
  }

  @override
  Future<void> close() {
    _previewTimer?.cancel();
    return super.close();
  }

  static ShiftEventEditorState _initial(
    ShiftEventDetail? existing,
    String? projectId,
    String? projectName,
    String? deviceZone,
    DateTime? day,
    ({DateTime start, DateTime end})? deviceSpan,
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
    if (deviceSpan case (:final start, :final end)) {
      // "Neues Event mit dieser Zeit" (HIN-166): the span swept out on the
      // calendar, in the device's zone the calendar draws in.
      return ShiftEventEditorState(
        projectId: projectId,
        projectName: projectName,
        start: start,
        end: end,
        timezone: deviceZone,
      );
    }
    final base = day ?? DateTime.now().add(const Duration(days: 7));
    final opens = DateTime(base.year, base.month, base.day, 10);
    return ShiftEventEditorState(
      projectId: projectId,
      projectName: projectName,
      start: opens,
      end: opens.add(const Duration(hours: 8)),
      timezone: deviceZone,
    );
  }

  void setProject(String id, String name) {
    emit(state.copyWith(projectId: id, projectName: name, clearError: true));
    _schedulePreview();
  }

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
    _schedulePreview();
  }

  void setEnd(DateTime value) {
    emit(state.copyWith(end: value, clearError: true));
    _schedulePreview();
  }

  /// A new zone, keeping the wall clocks.
  void setTimezone(String zone) {
    emit(state.copyWith(timezone: zone, clearError: true));
    _schedulePreview();
  }

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

  /// A new series, and its first occurrence to open as the server names it.
  /// None named, the series still stands and the list shows it.
  Future<ShiftEventSaved> _createSeries() async {
    final series = await _shifts.createSeries(state.projectId!, _draft());
    return ShiftEventSaved(
      null,
      series: series,
      firstEventId: series.firstEventId,
    );
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

  Map<String, dynamic> _patch(ShiftEventSummary s) => _input().toPatchJson(
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

  /// Whether saving has to ask which occurrences it applies to: an
  /// occurrence of a series with something changed.
  Future<bool> asksScope() async {
    final e = existing;
    if (e == null || !inSeries || problem != null) return false;
    if (ruleChanged) return true;
    if (state.timezone != null && state.timezone != _deviceZone) {
      await ShiftZones.ensureLoaded();
    }
    return _patch(e.summary).isNotEmpty;
  }

  /// Saves; the event when it went through, null when it did not (the reason
  /// stays in the state). An occurrence of a series needs [scope]; a changed
  /// rule goes along only with [ShiftScope.future].
  Future<ShiftEventSaved?> save({ShiftScope? scope}) async {
    if (state.saving) return null;
    emit(state.copyWith(attempted: true, clearError: true));
    if (problem != null) return null;
    emit(state.copyWith(saving: true));
    try {
      if (state.timezone != null && state.timezone != _deviceZone) {
        await ShiftZones.ensureLoaded();
      }
      final e = existing;
      final ShiftEventSaved saved;
      if (e == null && state.rule != null) {
        saved = await _createSeries();
      } else if (e == null) {
        saved = ShiftEventSaved(
          await _shifts.createEvent(state.projectId!, _input()),
        );
      } else {
        final s = e.summary;
        final patch = {
          ..._patch(s),
          if (ruleChanged && scope == ShiftScope.future)
            'rrule': state.rule!.toRrule(),
        };
        if (patch.isEmpty) {
          saved = ShiftEventSaved(e);
        } else {
          final change = await _shifts.updateEvent(
            s.id,
            patch,
            scope: s.inSeries ? scope : null,
          );
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
