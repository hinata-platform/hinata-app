import 'package:hinata/core/repositories/dashboard_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/team_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';

/// Repositories that write down every call and answer from [answers].
///
/// The cubits of the project, team and report pages only stand between a
/// screen and its repositories, so what their tests check is the call that
/// went out and the answer (or failure) that came back. An answer is a
/// function returning the typed future the real method returns, such as
/// `() async => project` or `() async => throw ApiFailure('errors.x')`; a call
/// nobody answered fails the test.
mixin RepositoryRecorder {
  final List<Invocation> calls = [];
  final Map<Symbol, Function> answers = {};

  /// The one call made to [member].
  Invocation callTo(Symbol member) =>
      calls.singleWhere((call) => call.memberName == member);

  dynamic record(Invocation invocation) {
    calls.add(invocation);
    final answer = answers[invocation.memberName];
    if (answer == null) {
      throw UnimplementedError('${invocation.memberName} is not answered');
    }
    return Function.apply(answer, const []);
  }
}

class RecordingProjects with RepositoryRecorder implements ProjectRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class RecordingUsers with RepositoryRecorder implements UserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class RecordingTeams with RepositoryRecorder implements TeamRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class RecordingTime with RepositoryRecorder implements TimeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class RecordingDashboard
    with RepositoryRecorder
    implements DashboardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class RecordingMeta with RepositoryRecorder implements MetaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}
