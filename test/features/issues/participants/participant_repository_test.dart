import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/issue_detail.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';

/// Sharing an issue on the wire: what the detail says about the caller and
/// the people it names, and the three participant routes.
void main() {
  group('IssueDetail', () {
    Map<String, dynamic> detail([Map<String, dynamic> extra = const {}]) => {
      'issue': {'id': 'i1', 'projectId': 'p1', 'title': 'eSIM'},
      'users': [
        {'id': 'u1', 'username': 'rebar', 'displayName': 'Rebar'},
        {
          'id': 'u2',
          'username': 'helen',
          'displayName': 'Helen',
          'canSeeIssue': false,
        },
      ],
      ...extra,
    };

    test('a server without participation reads as a member who manages', () {
      final parsed = IssueDetail.fromJson(detail());

      expect(parsed.participation.role, ParticipationRole.member);
      expect(parsed.participation.canManageParticipants, isTrue);
      expect(parsed.participation.isParticipant, isFalse);
    });

    test('a participant is read as one', () {
      final parsed = IssueDetail.fromJson(
        detail({
          'participation': {
            'role': 'PARTICIPANT',
            'canManageParticipants': false,
          },
        }),
      );

      expect(parsed.participation.role, ParticipationRole.participant);
      expect(parsed.participation.canManageParticipants, isFalse);
      expect(parsed.participation.isParticipant, isTrue);
    });

    test('people without canSeeIssue default to seeing it', () {
      final parsed = IssueDetail.fromJson(detail());

      expect(parsed.cannotSeeIssue, {'u2'});
      expect(parsed.users.map((u) => u.id), ['u1', 'u2']);
    });

    test('an issue carries the ids it is shared with', () {
      final issue = Issue.fromJson({
        'id': 'i1',
        'projectId': 'p1',
        'title': 't',
        'participantIds': ['u2'],
      });

      expect(issue.participantIds, ['u2']);
      expect(
        Issue.fromJson({'id': 'i1', 'projectId': 'p1'}).participantIds,
        isEmpty,
      );
    });
  });

  group('IssueRepository', () {
    late _RecordingApi api;
    late IssueRepository repo;

    setUp(() {
      api = _RecordingApi();
      repo = IssueRepository(api);
    });

    test('lists the participants', () async {
      api.answer = [
        {
          'id': 'u2',
          'displayName': 'Helen',
          'avatarUrl': null,
          'pronouns': 'she/her',
          'addedAt': '2026-10-15T10:00:00Z',
          'addedById': 'u1',
        },
      ];

      final list = await repo.participants('i1');

      expect(api.calls, ['GET /api/v1/issues/i1/participants']);
      expect(list.single.id, 'u2');
      expect(list.single.displayName, 'Helen');
      expect(list.single.addedById, 'u1');
      expect(list.single.addedAt?.toUtc(), DateTime.utc(2026, 10, 15, 10));
    });

    test('adds and removes with PUT and DELETE', () async {
      await repo.addParticipant('i1', 'u2');
      await repo.removeParticipant('i1', 'u2');

      expect(api.calls, [
        'PUT /api/v1/issues/i1/participants/u2',
        'DELETE /api/v1/issues/i1/participants/u2',
      ]);
    });

    test('asks who of the mentioned people cannot open the issue', () async {
      api.answer = ['u3'];

      final blocked = await repo.usersWithoutAccess('i1', ['u2', 'u3']);

      expect(api.calls, ['GET /api/v1/issues/i1/participants/blocked']);
      expect(api.query, {
        'userIds': ['u2', 'u3'],
      });
      expect(blocked, {'u3'});
    });
  });
}

class _RecordingApi implements ApiClient {
  final calls = <String>[];
  Object? answer;
  Map<String, dynamic>? query;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    calls.add('GET $path');
    this.query = query;
    return answer;
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    calls.add('PUT $path');
    return null;
  }

  @override
  Future<dynamic> delete(String path, {Object? body}) async {
    calls.add('DELETE $path');
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
