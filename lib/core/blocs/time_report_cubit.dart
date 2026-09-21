import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/time_report_models.dart';
import 'paged_cubit.dart';

/// The question the report page asks (HIN-93): window, filters, grouping,
/// chart. Every list on the page reads it and reloads when it changes.
class ReportQueryCubit extends Cubit<ReportQuery> {
  ReportQueryCubit([super.initial = const ReportQuery()]);

  void set(ReportQuery query) {
    if (query != state) emit(query);
  }

  void change(ReportQuery Function(ReportQuery current) update) =>
      set(update(state));
}

/// Reads the summary: totals and one page of groups.
typedef ReportSummaryFetcher =
    Future<ReportSummary> Function(int page, int size);

/// The groups of a summary, paged like every list, plus what the first page
/// says about the whole report: its totals and whether the reader sees other
/// people's rows.
///
/// The totals live here rather than in the widget that shows them, so they
/// belong to the groups they sum: a new question starts without them, and a
/// read that fails does not leave the last answer's totals standing.
class ReportGroupsCubit extends PagedCubit<ReportGroup> {
  factory ReportGroupsCubit(ReportSummaryFetcher fetch) {
    final meta = _SummaryMeta();
    return ReportGroupsCubit._(meta, (page, size) async {
      final summary = await fetch(page, size);
      if (page == 0) meta.summary = summary;
      return (items: summary.groups, total: summary.groupCount);
    });
  }

  ReportGroupsCubit._(this._meta, PageFetcher<ReportGroup> fetch)
    : super(fetch, pageSize: groupsPerPage);

  static const groupsPerPage = 50;

  final _SummaryMeta _meta;

  /// The first page's answer, or null before one arrived.
  ReportSummary? get summary => _meta.summary;

  @override
  Future<void> load() {
    _meta.summary = null;
    return super.load();
  }
}

class _SummaryMeta {
  ReportSummary? summary;
}

/// Reads one page of the workload report.
typedef WorkloadFetcher = Future<WorkloadPage> Function(int page, int size);

/// The people of the workload report, by name, plus what the page says about
/// the group: whether it was cut, and whether booked time counts only the
/// reader's own projects.
class WorkloadRowsCubit extends PagedCubit<WorkloadRow> {
  factory WorkloadRowsCubit(WorkloadFetcher fetch) {
    final meta = _WorkloadMeta();
    return WorkloadRowsCubit._(meta, (page, size) async {
      final result = await fetch(page, size);
      meta
        ..truncated = meta.truncated || result.truncated
        ..bookedInLedProjects = result.bookedInLedProjects;
      return (items: result.rows, total: result.total);
    });
  }

  WorkloadRowsCubit._(this._meta, PageFetcher<WorkloadRow> fetch)
    : super(fetch, pageSize: 50, keyOf: (row) => row.userId);

  final _WorkloadMeta _meta;

  bool get truncated => _meta.truncated;

  bool get bookedInLedProjects => _meta.bookedInLedProjects;

  @override
  Future<void> load() {
    _meta.truncated = false;
    return super.load();
  }
}

class _WorkloadMeta {
  bool truncated = false;
  bool bookedInLedProjects = false;
}
