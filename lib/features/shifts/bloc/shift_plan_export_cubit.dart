import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/shift_models.dart';
import '../../../core/models/shift_plan_export.dart';
import '../../../core/repositories/shift_repository.dart';

class ShiftPlanExportState extends Equatable {
  const ShiftPlanExportState({
    this.format = ShiftPlanFormat.pdf,
    this.names = false,
    this.running = false,
  });

  final ShiftPlanFormat format;

  /// "Mit Namen": only ever true for a planner.
  final bool names;

  /// A file is on its way; a second press does nothing.
  final bool running;

  ShiftPlanExportState copyWith({
    ShiftPlanFormat? format,
    bool? names,
    bool? running,
  }) => ShiftPlanExportState(
    format: format ?? this.format,
    names: names ?? this.names,
    running: running ?? this.running,
  );

  @override
  List<Object?> get props => [format, names, running];
}

/// "Schichtplan exportieren" for one event (HIN-163): the format, whether the
/// file names people, and the file itself.
///
/// Names are a planner's decision: the file leaves the access control the app
/// keeps, so for anybody else [setNames] does nothing and the request never
/// asks for them, whatever the dialog showed.
class ShiftPlanExportCubit extends Cubit<ShiftPlanExportState> {
  ShiftPlanExportCubit(this._shifts, this.event)
    : super(const ShiftPlanExportState());

  final ShiftRepository _shifts;
  final ShiftEventSummary event;

  bool get mayName => event.canPlan;

  void selectFormat(ShiftPlanFormat format) =>
      emit(state.copyWith(format: format));

  void setNames(bool names) {
    if (!mayName) return;
    emit(state.copyWith(names: names));
  }

  bool get _names => mayName && state.names;

  /// The name the file is saved under: the server's rule with [word], the
  /// file-name word of the caller's language.
  String fileName(String word) => shiftPlanFileName(
    word: word,
    title: event.title,
    startsLocal: event.startsLocal,
    format: state.format,
  );

  /// The plan in memory. Null while another export is still running.
  Future<ShiftPlanFile?> fetch() =>
      _run(() => _shifts.exportPlan(event.id, state.format, names: _names));

  /// The plan written to [path]; answers whether it was cut short, or null
  /// while another export is still running.
  Future<bool?> fetchTo(String path) => _run(
    () => _shifts.exportPlanTo(event.id, state.format, path, names: _names),
  );

  Future<T?> _run<T>(Future<T> Function() fetch) async {
    if (state.running || isClosed) return null;
    emit(state.copyWith(running: true));
    try {
      return await fetch();
    } finally {
      if (!isClosed) emit(state.copyWith(running: false));
    }
  }
}
