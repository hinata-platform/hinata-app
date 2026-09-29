import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';

/// What one deadline for many issues sends. Only the chosen field travels: a
/// date without a rule, a rule without a date, or the clear flag alone, which
/// is how the server tells the three answers apart.
void main() {
  late _RecordingApi api;
  late IssueRepository repo;

  setUp(() {
    api = _RecordingApi();
    repo = IssueRepository(api);
  });

  test('a fixed date goes as a plain day', () async {
    final updated = await repo.bulkSetDeadline([
      'a',
      'b',
    ], dueDate: DateTime(2026, 11, 3));

    expect(api.path, '/api/v1/issues/bulk/deadline');
    expect(api.body, {
      'issueIds': ['a', 'b'],
      'dueDate': '2026-11-03',
    });
    expect(updated.map((i) => i.id), ['a', 'b']);
  });

  test('a rule goes as its JSON, sign and basis included', () async {
    await repo.bulkSetDeadline(
      ['a'],
      dueOffset: const RelativeDate(
        amount: -2,
        unit: RelativeDateUnit.weeks,
        basis: RelativeDateBasis.working,
      ),
    );

    expect(api.body, {
      'issueIds': ['a'],
      'dueOffset': {'amount': -2, 'unit': 'WEEKS', 'basis': 'WORKING'},
    });
  });

  test('clearing sends the flag and nothing else', () async {
    await repo.bulkSetDeadline(['a', 'b', 'c'], clearDueDate: true);

    expect(api.body, {
      'issueIds': ['a', 'b', 'c'],
      'clearDueDate': true,
    });
  });
}

class _RecordingApi implements ApiClient {
  String? path;
  Object? body;

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    this.path = path;
    this.body = body;
    final ids = (body! as Map<String, dynamic>)['issueIds'] as List<String>;
    return [
      for (final id in ids)
        {'id': id, 'projectId': 'p1', 'title': id, 'state': 'OPEN'},
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
