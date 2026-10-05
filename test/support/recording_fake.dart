/// Repository doubles for cubits that only forward.
///
/// Such a cubit stands between a screen and its repositories, so what its test
/// checks is the call that goes out (the member and its arguments) and that
/// the answer or the failure comes back unchanged. [RecordingFake] is mixed
/// into a class that `implements` the repository, so no member has to be
/// written out; a member the test did not answer fails loudly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/repositories/absence_repository.dart';
import 'package:hinata/core/repositories/account_repository.dart';
import 'package:hinata/core/repositories/auth_repository.dart';
import 'package:hinata/core/repositories/availability_repository.dart';
import 'package:hinata/core/repositories/comment_repository.dart';
import 'package:hinata/core/repositories/dashboard_repository.dart';
import 'package:hinata/core/repositories/git_repository.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/media_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/repositories/notification_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/sprint_repository.dart';
import 'package:hinata/core/repositories/team_repository.dart';
import 'package:hinata/core/repositories/time_report_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/repositories/timesheet_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/features/knowledge/data/knowledge_repository.dart';

mixin RecordingFake {
  /// Every call, in order.
  final List<Invocation> calls = [];

  /// The answer per member, built when it is called so a failing future is
  /// never left unawaited.
  final Map<Symbol, Object? Function(Invocation call)> _answers = {};

  /// Answers [member] with a future of [value]. [T] is what the member's
  /// future promises; a `Future<dynamic>` would not pass for it.
  void answer<T>(Symbol member, T value) =>
      _answers[member] = (_) => Future<T>.value(value);

  /// Makes [member] fail with [error]. The future is a `Future<Never>`, which
  /// passes for whatever future the member promises.
  void fail(Symbol member, Object error) =>
      _answers[member] = (_) => Future<Never>.error(error);

  /// Answers [member] with whatever [answer] returns for the call, for a
  /// member that is not a future or an answer that depends on the arguments.
  void answerWith(Symbol member, Object? Function(Invocation call) answer) =>
      _answers[member] = answer;

  /// The one call that was made.
  Invocation get only => calls.single;

  /// The one call made to [member].
  Invocation callTo(Symbol member) =>
      calls.singleWhere((call) => call.memberName == member);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    final answer = _answers[invocation.memberName];
    if (answer == null) {
      throw UnimplementedError('${invocation.memberName} is not answered');
    }
    return answer(invocation);
  }
}

class FakeAbsenceRepository with RecordingFake implements AbsenceRepository {}

class FakeAccountRepository with RecordingFake implements AccountRepository {}

class FakeApiClient with RecordingFake implements ApiClient {}

class FakeAuthRepository with RecordingFake implements AuthRepository {}

class FakeAvailabilityRepository
    with RecordingFake
    implements AvailabilityRepository {}

class FakeCommentRepository with RecordingFake implements CommentRepository {}

class FakeDashboardRepository
    with RecordingFake
    implements DashboardRepository {}

class FakeGitRepository with RecordingFake implements GitRepository {}

class FakeIssueRepository with RecordingFake implements IssueRepository {}

class FakeKnowledgeRepository
    with RecordingFake
    implements KnowledgeRepository {}

class FakeMediaRepository with RecordingFake implements MediaRepository {}

class FakeMetaRepository with RecordingFake implements MetaRepository {}

class FakeNotificationRepository
    with RecordingFake
    implements NotificationRepository {}

class FakeProjectRepository with RecordingFake implements ProjectRepository {}

class FakeSprintRepository with RecordingFake implements SprintRepository {}

class FakeTeamRepository with RecordingFake implements TeamRepository {}

class FakeTimeReportRepository
    with RecordingFake
    implements TimeReportRepository {}

class FakeTimeRepository with RecordingFake implements TimeRepository {}

class FakeTimesheetRepository
    with RecordingFake
    implements TimesheetRepository {}

class FakeUserRepository with RecordingFake implements UserRepository {}

/// Matches a call to [member] with [positional] arguments and, of the named
/// ones, those [named] lists. Named arguments left out are not compared: a
/// forwarder fills in the member's defaults, and those are not the cubit's.
Matcher invoked(
  Symbol member, {
  List<Object?> positional = const [],
  Map<Symbol, Object?> named = const {},
}) => isA<Invocation>()
    .having((call) => call.memberName, 'member', member)
    .having((call) => call.positionalArguments, 'positional', positional)
    .having(
      (call) => {for (final key in named.keys) key: call.namedArguments[key]},
      'named',
      named,
    );

/// A failure as the API client throws it.
final ApiFailure failure = ApiFailure('errors.test', statusCode: 400);

/// Matches [failure] coming back out of the cubit unchanged.
final Matcher throwsFailure = throwsA(same(failure));

/// Answers [member] on [fake] with [answer], runs [act], and checks that the
/// one call it made was [member] with [positional] and at least the [named]
/// arguments given, and that [act] handed back what [answer] resolved to.
Future<void> expectForwarded<T>(
  RecordingFake fake,
  Symbol member,
  Future<T> Function() answer,
  Future<Object?> Function() act, {
  List<Object?> positional = const [],
  Map<Symbol, Object?> named = const {},
}) async {
  fake.calls.clear();
  final future = answer();
  fake.answerWith(member, (_) => future);
  final result = await act();
  expect(fake.calls, [
    invoked(member, positional: positional, named: named),
  ], reason: '$member');
  expect(result, await future, reason: '$member');
}

/// Makes [member] on [fake] fail and checks that [act] fails with that very
/// [failure].
Future<void> expectFailurePassedOn(
  RecordingFake fake,
  Symbol member,
  Future<Object?> Function() act,
) async {
  fake.fail(member, failure);
  await expectLater(act(), throwsFailure);
}
