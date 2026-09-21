import '../models/team_absence_models.dart';
import 'paged_cubit.dart';

/// Reads one page of the team absence calendar.
typedef TeamAbsencePageFetcher =
    Future<TeamAbsencePage> Function(int page, int size);

/// The rows of the team absence calendar, paged like every list, plus what a
/// page says about the whole group: whether the server cut it (HIN-118).
///
/// The cut lives here rather than in the widget that shows it, so it belongs
/// to the rows it describes: a new group starts without it, and a read that
/// fails does not leave the old group's note standing.
class TeamAbsenceRowsCubit extends PagedCubit<TeamAbsenceRow> {
  factory TeamAbsenceRowsCubit(TeamAbsencePageFetcher fetch) {
    final meta = _Meta();
    return TeamAbsenceRowsCubit._(meta, (page, size) async {
      final result = await fetch(page, size);
      meta.truncated = meta.truncated || result.truncated;
      return (items: result.rows, total: result.total);
    });
  }

  TeamAbsenceRowsCubit._(this._meta, PageFetcher<TeamAbsenceRow> fetch)
    : super(fetch, pageSize: rowsPerPage, keyOf: (row) => row.userId);

  /// The server's largest page: fewest round trips for a group of up to a
  /// thousand people.
  static const rowsPerPage = 100;

  final _Meta _meta;

  /// Whether the group was larger than one calendar reads, or held more
  /// absences than one read collects.
  bool get truncated => _meta.truncated;

  @override
  Future<void> load() {
    _meta.truncated = false;
    return super.load();
  }

  /// Every page, for a view that has to see the whole group at once — the
  /// phone agenda groups by week, and a week missing the people on a later
  /// page would look complete while it is not. Bounded by the server's cap of
  /// a thousand people: ten pages at most.
  Future<void> loadAll() async {
    await load();
    while (!isClosed && state.hasMore && state.errorKey == null) {
      final before = state.items.length;
      await loadMore();
      if (state.items.length == before) break;
    }
  }
}

class _Meta {
  bool truncated = false;
}
