import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/time_usage_cubit.dart';
import 'package:hinata/core/models/time_usage_models.dart';
import 'package:hinata/core/repositories/time_usage_repository.dart';

void main() {
  test('asks once for every project watched in the same turn', () async {
    final repository = _Repository();
    final cubit = TimeUsageCubit(repository, enabled: () => true);
    addTearDown(cubit.close);

    await Future.wait([
      cubit.watch(['a']),
      cubit.watch(['b']),
      cubit.watch(['a', 'c']),
    ]);

    expect(repository.asked, [
      {'a', 'b', 'c'},
    ]);
    expect(cubit.state.of('b')?.usedMinutes, 1);
  });

  test(
    'does not ask again while the figures are fresh, but does after a refresh',
    () async {
      final repository = _Repository();
      final cubit = TimeUsageCubit(repository, enabled: () => true);
      addTearDown(cubit.close);

      await cubit.watch(['a']);
      await cubit.watch(['a']);
      await cubit.refresh('a');

      expect(repository.asked, [
        {'a'},
        {'a'},
      ]);
    },
  );

  test('asks nothing with the extended module off', () async {
    final repository = _Repository();
    final cubit = TimeUsageCubit(repository, enabled: () => false);
    addTearDown(cubit.close);

    await cubit.watch(['a']);

    expect(repository.asked, isEmpty);
  });

  test('a failed read leaves no figures and no error', () async {
    final repository = _Repository()..fail = true;
    final cubit = TimeUsageCubit(repository, enabled: () => true);
    addTearDown(cubit.close);

    await cubit.watch(['a']);

    expect(cubit.state.projects, isEmpty);
  });

  test('a project that comes back without figures is forgotten', () async {
    final repository = _Repository();
    final cubit = TimeUsageCubit(repository, enabled: () => true);
    addTearDown(cubit.close);
    await cubit.watch(['a']);
    repository.hidden.add('a');

    await cubit.refresh('a');

    expect(cubit.state.of('a'), isNull);
  });

  test('a refresh during a read reads once more when it lands', () async {
    final repository = _Repository()..slow = Completer<void>();
    final cubit = TimeUsageCubit(repository, enabled: () => true);
    addTearDown(cubit.close);

    final first = cubit.watch(['a']);
    await Future<void>.delayed(Duration.zero);
    // Saved while the first read was under way: that read may be stale.
    unawaited(cubit.refresh('a'));
    repository.slow!.complete();
    repository.slow = null;
    await first;
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(repository.asked, [
      {'a'},
      {'a'},
    ]);
  });

  test('a forecast that came with the report is not asked again', () async {
    final repository = _Repository();
    final cubit = TimeUsageCubit(repository, enabled: () => true);
    addTearDown(cubit.close);

    await cubit.budgetReport();

    expect(cubit.heldForecast('a')?.dailyMinutes, 30);
    expect(await cubit.forecast('a'), isNotNull);
    expect(repository.forecasts, isEmpty);
    expect(await cubit.forecast('b'), isNotNull);
    expect(repository.forecasts, ['b']);
  });

  test('every other read is nothing with the module off', () async {
    final repository = _Repository();
    final cubit = TimeUsageCubit(repository, enabled: () => false);
    addTearDown(cubit.close);

    expect(await cubit.forecast('a'), isNull);
    expect(await cubit.issue('HIN-1'), isNull);
    expect(await cubit.sprint('s1'), isNull);
    expect(repository.forecasts, isEmpty);
  });
}

class _Repository extends TimeUsageRepository {
  _Repository() : super(_NoApi());

  final List<Set<String>> asked = [];
  final Set<String> hidden = {};
  bool fail = false;
  Completer<void>? slow;
  final List<String> forecasts = [];

  @override
  Future<BudgetForecast> forecast(String projectId) async {
    forecasts.add(projectId);
    return const BudgetForecast(dailyMinutes: 10);
  }

  @override
  Future<BudgetReportPage> budgetReport({
    int page = 0,
    int size = 20,
    List<String> projectIds = const [],
  }) async => const BudgetReportPage(
    budgets: TopBudgets(forecasts: {'a': BudgetForecast(dailyMinutes: 30)}),
  );

  @override
  Future<Map<String, ProjectTimeUsage>> projects(
    Iterable<String> projectIds,
  ) async {
    asked.add(projectIds.toSet());
    await slow?.future;
    if (fail) throw StateError('offline');
    return {
      for (final id in projectIds)
        if (!hidden.contains(id))
          id: ProjectTimeUsage(
            projectId: id,
            budgetMinutes: 60,
            usedMinutes: 1,
          ),
    };
  }
}

class _NoApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
