import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/repositories/time_usage_repository.dart';

void main() {
  test('asks for many projects in steps the server accepts', () async {
    final api = _BatchApi();
    final ids = [for (var i = 0; i < 230; i++) 'p$i'];

    final found = await TimeUsageRepository(api).projects([...ids, 'p0']);

    expect(api.asked.map((step) => step.length), [100, 100, 30]);
    expect(found.keys, unorderedEquals(ids));
  });

  test('reads an issue by its key', () async {
    final api = _BatchApi();
    final usage = await TimeUsageRepository(api).issue('HIN-1');
    expect(api.paths.last, '/api/v1/issues/HIN-1/time-usage');
    expect(usage.estimate?.limit, 60);
  });
}

class _BatchApi implements ApiClient {
  final List<List<String>> asked = [];
  final List<String> paths = [];

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    paths.add(path);
    if (path == '/api/v1/projects/time-usage') {
      final step = (query!['ids'] as String).split(',');
      asked.add(step);
      return [
        for (final id in step) {'projectId': id, 'usedMinutes': 1},
      ];
    }
    return {
      'issueId': 'i1',
      'projectId': 'p1',
      'estimateMinutes': 60,
      'spentMinutes': 10,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
