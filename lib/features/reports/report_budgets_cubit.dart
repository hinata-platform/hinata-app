import '../../core/blocs/paged_cubit.dart';
import '../../core/blocs/time_usage_cubit.dart';
import '../../core/models/time_usage_models.dart';

/// The budget report's pages (HIN-157): the ranked budgets twenty at a time,
/// and what came with them, the projects' names and, with the first page, the
/// running sprints with a budget.
///
/// The names and the sprints are set before the page that brought them is
/// emitted, so a view rebuilt for the page reads them current.
class ReportBudgetsCubit extends PagedCubit<ProjectTimeUsage> {
  factory ReportBudgetsCubit(
    TimeUsageCubit usage, {
    List<String> projectIds = const [],
  }) {
    final extras = _Extras();
    return ReportBudgetsCubit._(extras, (page, size) async {
      final report = await usage.budgetReport(
        page: page,
        size: size,
        projectIds: projectIds,
      );
      extras.names.addAll(report.budgets.names);
      if (page == 0) extras.sprints = report.sprints;
      return (items: report.budgets.items, total: report.budgets.total);
    });
  }

  ReportBudgetsCubit._(this._extras, PageFetcher<ProjectTimeUsage> fetch)
    : super(fetch, pageSize: 20, keyOf: (usage) => usage.projectId);

  final _Extras _extras;

  /// Every loaded project's name by id.
  Map<String, String> get names => _extras.names;

  /// The running sprints with a budget that have figures, from the first page.
  List<BudgetedSprint> get sprints => [
    for (final sprint in _extras.sprints)
      if (sprint.gauge != null) sprint,
  ];
}

class _Extras {
  final Map<String, String> names = {};
  List<BudgetedSprint> sprints = const [];
}
