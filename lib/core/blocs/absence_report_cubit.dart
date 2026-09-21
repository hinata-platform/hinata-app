import '../models/absence_report_models.dart';
import '../repositories/absence_repository.dart';
import 'paged_cubit.dart';

/// Reads one page of the absence report.
typedef AbsenceReportFetcher =
    Future<AbsenceReportPage> Function(int page, int size);

/// The rows of the absence report (HIN-119), paged like every list, plus the
/// head the first page answers with: the year, whether the rate is shown, and
/// the figures over everybody in the report.
///
/// The head lives here rather than in the widget that shows it, so it belongs
/// to the rows it sums: a new question starts without it, and a read that fails
/// does not leave the last answer's head standing.
class AbsenceReportCubit extends PagedCubit<AbsenceReportRow> {
  factory AbsenceReportCubit(AbsenceReportFetcher fetch) {
    final meta = _HeadMeta();
    return AbsenceReportCubit._(meta, (page, size) async {
      final result = await fetch(page, size);
      if (page == 0) meta.head = result.head;
      return (items: result.rows, total: result.total);
    });
  }

  AbsenceReportCubit._(this._meta, PageFetcher<AbsenceReportRow> fetch)
    : super(fetch, pageSize: 50, keyOf: (row) => row.key);

  final _HeadMeta _meta;

  /// The first page's head, or null before one arrived.
  AbsenceReportHead? get head => _meta.head;

  @override
  Future<void> load() {
    _meta.head = null;
    return super.load();
  }
}

class _HeadMeta {
  AbsenceReportHead? head;
}
