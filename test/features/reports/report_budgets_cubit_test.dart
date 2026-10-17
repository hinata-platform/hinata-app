import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/time_usage_cubit.dart';
import 'package:hinata/core/models/time_usage_models.dart';
import 'package:hinata/core/repositories/time_usage_repository.dart';
import 'package:hinata/features/reports/report_budgets_cubit.dart';

/// The budget report's pages: names gathered across pages, the sprints from
/// the first page only, and only those that have figures.
void main() {
  test(
    'gathers names across pages and keeps the first page\'s sprints',
    () async {
      final usage = TimeUsageCubit(_Repository(), enabled: () => true);
      addTearDown(usage.close);
      final pages = ReportBudgetsCubit(usage, projectIds: const ['p1', 'p2']);
      addTearDown(pages.close);

      await pages.load();
      await pages.loadMore();

      expect(pages.state.items, hasLength(25));
      expect(pages.names['p0'], 'Project 0');
      expect(pages.names['p24'], 'Project 24');
      expect(pages.sprints.map((sprint) => sprint.id), ['s1']);
    },
  );
}

class _Repository extends TimeUsageRepository {
  _Repository() : super(_NoApi());

  @override
  Future<BudgetReportPage> budgetReport({
    int page = 0,
    int size = 20,
    List<String> projectIds = const [],
  }) async {
    expect(projectIds, ['p1', 'p2']);
    final ids = [
      for (var i = page * size; i < 25 && i < (page + 1) * size; i++) 'p$i',
    ];
    return BudgetReportPage(
      budgets: TopBudgets(
        items: [
          for (final id in ids)
            ProjectTimeUsage(projectId: id, budgetMinutes: 60, usedMinutes: 6),
        ],
        names: {for (final id in ids) id: 'Project ${id.substring(1)}'},
        total: 25,
      ),
      sprints: page == 0
          ? [
              BudgetedSprint(
                id: 's1',
                name: 'Sprint 1',
                board: 'Board',
                gauge: BudgetGauge.of(10, 60),
              ),
              // Without a budget it has nothing to draw.
              const BudgetedSprint(id: 's2', name: 'Sprint 2', board: 'Board'),
            ]
          : const [BudgetedSprint(id: 's3', name: 'Later', board: 'Board')],
    );
  }
}

class _NoApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
