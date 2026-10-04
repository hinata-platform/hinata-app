import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/core_models.dart';
import '../../../core/models/time_report_models.dart';
import '../../../core/repositories/time_report_repository.dart';
import '../../../core/repositories/user_repository.dart';

/// The report page's calls (HIN-93): the three reports, the kept ones and
/// what can happen to them, the files a report comes out as, and the names of
/// the people a kept report mentions.
///
/// Holds no state: the page keeps its question, its lists and its labels.
/// Failures pass through as the repository's `ApiFailure`.
class TimeReportsCubit extends Cubit<void> {
  TimeReportsCubit(this._reports, this._users) : super(null);

  final TimeReportRepository _reports;
  final UserRepository _users;

  Future<ReportSummary> summary(
    ReportQuery query, {
    required int page,
    required int size,
    required int weekStart,
  }) => _reports.summary(query, page: page, size: size, weekStart: weekStart);

  Future<({List<ReportEntry> items, int total})> detailed(
    ReportQuery query, {
    required int page,
    required int size,
    required int weekStart,
  }) => _reports.detailed(query, page: page, size: size, weekStart: weekStart);

  Future<WorkloadPage> workload(
    ReportQuery query, {
    String? projectId,
    required int page,
    required int size,
    required int weekStart,
  }) => _reports.workload(
    query,
    projectId: projectId,
    page: page,
    size: size,
    weekStart: weekStart,
  );

  Future<({List<SavedReport> items, int total})> savedReports({
    required int page,
    required int size,
  }) => _reports.savedReports(page: page, size: size);

  Future<SavedReport> openShared(String token) => _reports.openShared(token);

  Future<SavedReport> openSaved(String id) => _reports.openSaved(id);

  Future<SavedReport> saveReport(String name, ReportQuery query) =>
      _reports.saveReport(name, query);

  Future<SavedReport> updateReport(
    String id, {
    String? name,
    ReportQuery? query,
  }) => _reports.updateReport(id, name: name, query: query);

  /// A new share token for [id]; the one before stops working.
  Future<String> shareReport(String id) => _reports.shareReport(id);

  Future<void> unshareReport(String id) => _reports.unshareReport(id);

  Future<SavedReport> scheduleReport(String id, ReportSchedule schedule) =>
      _reports.scheduleReport(id, schedule);

  Future<SavedReport> unscheduleReport(String id) =>
      _reports.unscheduleReport(id);

  Future<void> deleteReport(String id) => _reports.deleteReport(id);

  /// The report as a [format] file, in memory.
  Future<({Uint8List bytes, bool truncated})> export(
    ReportQuery query,
    String format, {
    required int weekStart,
  }) => _reports.export(query, format, weekStart: weekStart);

  /// The report as a [format] file, written to [path]. True when cut short.
  Future<bool> exportTo(
    ReportQuery query,
    String format,
    String path, {
    required int weekStart,
  }) => _reports.exportTo(query, format, path, weekStart: weekStart);

  Future<List<DirectoryUser>> usersByIds(List<String> ids) =>
      _users.usersByIds(ids);
}
