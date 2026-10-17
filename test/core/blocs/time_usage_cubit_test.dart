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
}

class _Repository extends TimeUsageRepository {
  _Repository() : super(_NoApi());

  final List<Set<String>> asked = [];
  final Set<String> hidden = {};
  bool fail = false;

  @override
  Future<Map<String, ProjectTimeUsage>> projects(
    Iterable<String> projectIds,
  ) async {
    asked.add(projectIds.toSet());
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
