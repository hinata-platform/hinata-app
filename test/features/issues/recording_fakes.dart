/// Fakes for the issue cubits' tests: each records every call it receives and
/// answers from a table the test fills, keyed by member name.
///
/// The cubits under test only forward, so what matters is the call that comes
/// out the other side — the member, its arguments — and that the answer (or
/// the failure) travels back unchanged. A member the test did not answer fails
/// loudly instead of returning null.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/comment_repository.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/media_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/sprint_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/features/knowledge/data/knowledge_repository.dart';

mixin Recording {
  final List<Invocation> calls = [];

  /// What each member answers; the function sees the call it answers.
  final Map<Symbol, Object? Function(Invocation call)> answers = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    final answer = answers[invocation.memberName];
    if (answer == null) {
      throw UnimplementedError('${invocation.memberName} is not faked');
    }
    return answer(invocation);
  }
}

class FakeIssueRepository with Recording implements IssueRepository {}

class FakeCommentRepository with Recording implements CommentRepository {}

class FakeProjectRepository with Recording implements ProjectRepository {}

class FakeUserRepository with Recording implements UserRepository {}

class FakeMediaRepository with Recording implements MediaRepository {}

class FakeSprintRepository with Recording implements SprintRepository {}

class FakeMetaRepository with Recording implements MetaRepository {}

class FakeKnowledgeRepository with Recording implements KnowledgeRepository {}

class FakeApiClient with Recording implements ApiClient {}

/// Answers [member] on [fake] with [answer], runs [act], and checks that the
/// one call it made was [member] with [positional] and at least the [named]
/// arguments given, and that [act] handed back what [answer] resolved to.
Future<void> expectForwarded<T>(
  Recording fake,
  Symbol member,
  Future<T> Function() answer,
  Future<Object?> Function() act, {
  List<Object?> positional = const [],
  Map<Symbol, Object?> named = const {},
}) async {
  fake.calls.clear();
  final future = answer();
  fake.answers[member] = (_) => future;
  final result = await act();
  expect(fake.calls, hasLength(1), reason: '$member');
  final call = fake.calls.single;
  expect(call.memberName, member);
  expect(call.positionalArguments, positional, reason: '$member');
  for (final entry in named.entries) {
    expect(
      call.namedArguments[entry.key],
      entry.value,
      reason: '$member ${entry.key}',
    );
  }
  expect(result, await future, reason: '$member');
}

/// Answers [member] on [fake] with a refusal and checks that [act] fails with
/// that very [ApiFailure].
Future<void> expectFailurePassedOn<T>(
  Recording fake,
  Symbol member,
  Future<Object?> Function() act,
) async {
  final failure = ApiFailure('errors.refused', statusCode: 403);
  fake.answers[member] = (_) => Future<T>.error(failure);
  await expectLater(act(), throwsA(same(failure)));
}

/// A minimal issue, for answers that need one.
Issue testIssue([String id = 'i1']) => Issue.fromJson({
  'id': id,
  'projectId': 'p1',
  'readableId': 'HIN-1',
  'title': 'Title',
  'state': 'OPEN',
});

/// A minimal work entry, for answers that need one.
const WorkItem testWorkItem = WorkItem(
  id: 'w1',
  durationMinutes: 30,
  activityType: 'Development',
);
