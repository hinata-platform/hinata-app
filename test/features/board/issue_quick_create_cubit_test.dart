import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/features/board/issue_quick_create_cubit.dart';

class _Issues implements IssueRepository {
  final bodies = <Map<String, dynamic>>[];
  Object? refusal;

  @override
  Future<Issue> createIssue(Map<String, dynamic> body) async {
    bodies.add(body);
    final refusal = this.refusal;
    if (refusal != null) throw refusal;
    return Issue(
      id: 'i1',
      projectId: body['projectId'] as String,
      readableId: 'HIN-1',
      title: body['title'] as String,
      state: 'Open',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _Users implements UserRepository {
  final asked = <List<Object>>[];
  Object? refusal;

  @override
  Future<({List<DirectoryUser> items, int total})> searchUsers(
    String query, {
    int page = 0,
    int size = 25,
  }) async {
    asked.add([query, page, size]);
    final refusal = this.refusal;
    if (refusal != null) throw refusal;
    return (
      items: const [
        DirectoryUser(id: 'u1', username: 'ada', displayName: 'Ada'),
      ],
      total: 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

void main() {
  late _Issues issues;
  late _Users users;
  late IssueQuickCreateCubit composer;

  setUp(() {
    issues = _Issues();
    users = _Users();
    composer = IssueQuickCreateCubit(issues: issues, users: users);
  });

  tearDown(() => composer.close());

  test('creates the issue from the body it is given', () async {
    final created = await composer.create({'projectId': 'A', 'title': 'T'});

    expect(created.id, 'i1');
    expect(issues.bodies, [
      {'projectId': 'A', 'title': 'T'},
    ]);
  });

  test('searches the directory page by page', () async {
    final first = await composer.searchUsers('ad', size: 25);
    await composer.searchUsers('ad', page: 1, size: 25);

    expect(first.total, 1);
    expect([for (final u in first.items) u.id], ['u1']);
    expect(users.asked, [
      ['ad', 0, 25],
      ['ad', 1, 25],
    ]);
  });

  test('passes a refusal on as it came', () async {
    final refusal = ApiFailure('error.accessDenied');
    issues.refusal = refusal;
    users.refusal = refusal;

    await expectLater(composer.create(const {}), throwsA(refusal));
    await expectLater(composer.searchUsers(''), throwsA(refusal));
  });
}
