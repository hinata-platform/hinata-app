import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/absence_models.dart';
import '../../../core/models/absence_report_models.dart';
import '../../../core/repositories/absence_repository.dart';

/// The absence report's calls (HIN-119): its pages, the catalogue its pills
/// offer, whether the reader keeps absences, and the files it comes out as.
///
/// Holds no state: the tab keeps its rows and pills, the page its question.
/// Failures pass through as the repository's `ApiFailure`.
class ReportAbsencesCubit extends Cubit<void> {
  ReportAbsencesCubit(this._absences) : super(null);

  final AbsenceRepository _absences;

  Future<AbsenceReportPage> report(
    AbsenceReportQuery query, {
    required int page,
    required int size,
  }) => _absences.report(query, page: page, size: size);

  Future<List<AbsenceType>> types() => _absences.types();

  Future<bool> isKeeper() => _absences.isKeeper();

  /// The report as a [format] file, in memory.
  Future<({Uint8List bytes, bool truncated})> exportReport(
    AbsenceReportQuery query,
    String format,
  ) => _absences.exportReport(query, format);

  /// The report as a [format] file, written to [path]. True when cut short.
  Future<bool> exportReportTo(
    AbsenceReportQuery query,
    String format,
    String path,
  ) => _absences.exportReportTo(query, format, path);
}
