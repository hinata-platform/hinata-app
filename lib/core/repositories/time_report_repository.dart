import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../models/time_report_models.dart';
import '../util/reader_time_zone.dart';

/// Time reports (HIN-93): summary, detailed and workload reports, their files,
/// the CSV import, and saved, shared and scheduled reports.
///
/// Behind `advanced_time_tracking` like the rest of the module; with it off
/// every route answers 404 `error.feature.disabled`. Every answer is computed
/// by the server in the reader's own scope, whoever asks and however the
/// question arrived — typed, saved, or opened from somebody else's link.
class TimeReportRepository {
  TimeReportRepository(this._api);

  final ApiClient _api;

  static String _id(String id) => Uri.encodeComponent(id);

  /// The parameters of a report for today, with the device's zone for the
  /// start and end times a file writes. [weekStart] is the policy's first day.
  Future<Map<String, dynamic>> _params(
    ReportQuery query, {
    int weekStart = DateTime.monday,
  }) async {
    final zone = await ReaderTimeZone.resolve();
    return {
      ...query.toQuery(DateTime.now(), weekStart: weekStart),
      'tz': ?zone,
    };
  }

  Future<ReportSummary> summary(
    ReportQuery query, {
    int page = 0,
    int size = 50,
    int weekStart = DateTime.monday,
  }) async => ReportSummary.fromJson(
    await _api.get(
          '/api/v1/time/reports/summary',
          query: {
            ...await _params(query, weekStart: weekStart),
            'groupBy': query.groupBy.wire,
            'page': page,
            'size': size,
          },
        )
        as Map<String, dynamic>,
  );

  Future<({List<ReportEntry> items, int total})> detailed(
    ReportQuery query, {
    int page = 0,
    int size = 50,
    int weekStart = DateTime.monday,
  }) async {
    final data =
        await _api.get(
              '/api/v1/time/reports/detailed',
              query: {
                ...await _params(query, weekStart: weekStart),
                'page': page,
                'size': size,
              },
            )
            as Map<String, dynamic>;
    return (
      items: [
        for (final raw in (data['content'] as List<dynamic>?) ?? const [])
          ReportEntry.fromJson(raw as Map<String, dynamic>),
      ],
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  /// Only while an operator switched workload reports on (404 otherwise), and
  /// only for an administrator or a lead who sees members' entries (403).
  Future<WorkloadPage> workload(
    ReportQuery query, {
    String? projectId,
    String? teamId,
    int page = 0,
    int size = 50,
    int weekStart = DateTime.monday,
  }) async => WorkloadPage.fromJson(
    await _api.get(
          '/api/v1/time/reports/workload',
          query: {
            ...await _params(query, weekStart: weekStart),
            'projectId': ?projectId,
            'teamId': ?teamId,
            'page': page,
            'size': size,
          },
        )
        as Map<String, dynamic>,
  );

  // --- files -----------------------------------------------------------------

  /// The report as a file in memory: `csv`, `xlsx` or `pdf`. [truncated] says
  /// the server stopped at the format's ceiling.
  Future<({Uint8List bytes, bool truncated})> export(
    ReportQuery query,
    String format, {
    int weekStart = DateTime.monday,
  }) async {
    final file = await _api.getFile(
      await _exportPath(query, format, weekStart),
      receiveTimeout: const Duration(minutes: 3),
    );
    return (bytes: file.bytes, truncated: _truncated(file.header));
  }

  /// The same file written straight to [path], so a large one never sits in
  /// memory. Answers whether the server stopped at the format's ceiling.
  Future<bool> exportTo(
    ReportQuery query,
    String format,
    String path, {
    int weekStart = DateTime.monday,
  }) async => _truncated(
    await _api.downloadTo(
      await _exportPath(query, format, weekStart),
      path,
      receiveTimeout: const Duration(minutes: 5),
    ),
  );

  Future<String> _exportPath(
    ReportQuery query,
    String format,
    int weekStart,
  ) async {
    final params = {
      ...await _params(query, weekStart: weekStart),
      if (format != 'csv') 'groupBy': query.groupBy.wire,
    };
    final pairs = <String>[
      for (final entry in params.entries)
        if (entry.value is List)
          for (final value in entry.value as List)
            '${Uri.encodeQueryComponent(entry.key)}='
                '${Uri.encodeQueryComponent('$value')}'
        else
          '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent('${entry.value}')}',
    ];
    return '/api/v1/time/reports/export.$format?${pairs.join('&')}';
  }

  static bool _truncated(String? Function(String name) header) =>
      header('x-export-truncated') == 'true';

  // --- import ------------------------------------------------------------------

  /// Checks every row of a CSV file and writes nothing. [mapping] overrides
  /// the columns the server read from the header; [userId] imports for
  /// somebody else, which only an administrator may.
  Future<ImportPreview> previewImport({
    required String fileName,
    Uint8List? bytes,
    String? path,
    Map<ImportColumn, int> mapping = const {},
    String? userId,
  }) async {
    final file = bytes != null
        ? MultipartFile.fromBytes(bytes, filename: fileName)
        : await MultipartFile.fromFile(path!, filename: fileName);
    return ImportPreview.fromJson(
      await _api.upload(
            '/api/v1/time/import/csv',
            file,
            fields: {
              for (final entry in mapping.entries)
                'column.${entry.key.wire}': entry.value,
              'userId': ?userId,
            },
          )
          as Map<String, dynamic>,
    );
  }

  Future<({List<ImportRowError> items, int total})> importErrors(
    String importId, {
    int page = 0,
    int size = 20,
  }) async {
    final data =
        await _api.get(
              '/api/v1/time/import/${_id(importId)}/errors',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: [
        for (final raw in (data['content'] as List<dynamic>?) ?? const [])
          ImportRowError.fromJson(raw as Map<String, dynamic>),
      ],
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  /// Writes the rows that passed, all of them or none. Answers how many.
  Future<int> commitImport(String importId) async {
    final data =
        await _api.post('/api/v1/time/import/${_id(importId)}/commit')
            as Map<String, dynamic>;
    return (data['inserted'] as num?)?.toInt() ?? 0;
  }

  Future<void> discardImport(String importId) =>
      _api.delete('/api/v1/time/import/${_id(importId)}');

  // --- saved reports -----------------------------------------------------------

  Future<({List<SavedReport> items, int total})> savedReports({
    int page = 0,
    int size = 50,
  }) async {
    final data =
        await _api.get(
              '/api/v1/time/reports/saved',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: [
        for (final raw in (data['content'] as List<dynamic>?) ?? const [])
          SavedReport.fromJson(raw as Map<String, dynamic>),
      ],
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  Future<SavedReport> saveReport(String name, ReportQuery query) async =>
      SavedReport.fromJson(
        await _api.post(
              '/api/v1/time/reports/saved',
              body: {'name': name, 'config': query.toConfig()},
            )
            as Map<String, dynamic>,
      );

  Future<SavedReport> updateReport(
    String id, {
    String? name,
    ReportQuery? query,
  }) async => SavedReport.fromJson(
    await _api.patch(
          '/api/v1/time/reports/saved/${_id(id)}',
          body: {'name': ?name, 'config': ?query?.toConfig()},
        )
        as Map<String, dynamic>,
  );

  Future<void> deleteReport(String id) =>
      _api.delete('/api/v1/time/reports/saved/${_id(id)}');

  /// A new link; the token is shown once and replaces any earlier one.
  Future<String> shareReport(String id) async {
    final data =
        await _api.post('/api/v1/time/reports/saved/${_id(id)}/share')
            as Map<String, dynamic>;
    return data['token'] as String? ?? '';
  }

  Future<void> unshareReport(String id) =>
      _api.delete('/api/v1/time/reports/saved/${_id(id)}/share');

  Future<SavedReport> scheduleReport(
    String id,
    ReportSchedule schedule,
  ) async => SavedReport.fromJson(
    await _api.put(
          '/api/v1/time/reports/saved/${_id(id)}/schedule',
          body: schedule.toJson(),
        )
        as Map<String, dynamic>,
  );

  Future<SavedReport> unscheduleReport(String id) async => SavedReport.fromJson(
    await _api.delete('/api/v1/time/reports/saved/${_id(id)}/schedule')
        as Map<String, dynamic>,
  );

  /// A saved report by id, for its owner or somebody its schedule mails — the
  /// link in a report mail lands here.
  Future<SavedReport> openSaved(String id) async => SavedReport.fromJson(
    await _api.get('/api/v1/time/reports/saved/${_id(id)}')
        as Map<String, dynamic>,
  );

  /// The report somebody's link points to, opened in the reader's own scope.
  Future<SavedReport> openShared(String token) async => SavedReport.fromJson(
    await _api.get('/api/v1/time/reports/saved/shared/${_id(token)}')
        as Map<String, dynamic>,
  );
}
