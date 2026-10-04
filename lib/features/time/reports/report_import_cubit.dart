import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/time_report_models.dart';
import '../../../core/repositories/time_report_repository.dart';

/// The import wizard's calls: check a file, page through the rows that fail,
/// write the rows that passed, or throw the check away.
///
/// Holds no state: the wizard keeps the file, the mapping and where it stands.
/// Failures pass through as the repository's `ApiFailure`.
class ReportImportCubit extends Cubit<void> {
  ReportImportCubit(this._reports) : super(null);

  final TimeReportRepository _reports;

  Future<ImportPreview> previewImport({
    required String fileName,
    Uint8List? bytes,
    String? path,
    Map<ImportColumn, int> mapping = const {},
    String? userId,
  }) => _reports.previewImport(
    fileName: fileName,
    bytes: bytes,
    path: path,
    mapping: mapping,
    userId: userId,
  );

  Future<({List<ImportRowError> items, int total})> importErrors(
    String importId, {
    required int page,
  }) => _reports.importErrors(importId, page: page);

  /// Writes the checked rows; answers how many entries were written.
  Future<int> commitImport(String importId) => _reports.commitImport(importId);

  Future<void> discardImport(String importId) =>
      _reports.discardImport(importId);
}
