import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/repositories/time_repository.dart';

/// The copy of the reader's own time entries the time settings hand out
/// (Art. 20 DSGVO).
///
/// Holds no state of its own: the section shows the outcome as a toast, and
/// these calls answer or fail as the repository does.
class TimeExportCubit extends Cubit<void> {
  TimeExportCubit(this._time) : super(null);

  final TimeRepository _time;

  /// Every entry as CSV bytes, for the web, where nothing can be written to
  /// disk directly.
  Future<({Uint8List bytes, bool truncated})> csv() => _time.exportCsv();

  /// Every entry as CSV, written straight to [path]. Answers whether the
  /// server stopped at its row limit.
  Future<bool> csvTo(String path) => _time.exportCsvTo(path);
}
