import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/repositories/absence_repository.dart';
import 'package:hinata/core/repositories/availability_repository.dart';
import 'package:hinata/core/repositories/team_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';

/// Writes down every call a cubit makes and answers with what the test set up
/// for that method.
///
/// The cubits of the absence screens only pass calls on, so what is worth
/// checking is the call itself — which method, with which arguments — and that
/// the answer or the failure comes back untouched. Answers are closures so
/// each keeps its own type: a `Future<dynamic>` would not pass for the
/// `Future<AbsenceBalances>` the method promises.
mixin Recording {
  final List<Invocation> calls = [];
  final Map<Symbol, Object Function()> answers = {};

  /// Answers [method] with [value].
  void answer<T>(Symbol method, T value) =>
      answers[method] = () => Future<T>.value(value);

  /// Makes [method] fail with [failure].
  void fail<T>(Symbol method, ApiFailure failure) =>
      answers[method] = () => Future<T>.error(failure);

  /// The one call made so far.
  Invocation get only => calls.single;

  Object? record(Invocation invocation) {
    calls.add(invocation);
    final answer = answers[invocation.memberName];
    if (answer == null) {
      throw UnimplementedError('${invocation.memberName} is not faked');
    }
    return answer();
  }
}

class RecordingAbsences with Recording implements AbsenceRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class RecordingUsers with Recording implements UserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class RecordingAvailability with Recording implements AvailabilityRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class RecordingTeams with Recording implements TeamRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

/// A failure every test can expect back unchanged.
final failure = ApiFailure('error.timeOff.conflict', statusCode: 409);

/// Expects [call] to be [member] with exactly these arguments.
void expectCall(
  Invocation call,
  Symbol member, {
  List<Object?> positional = const [],
  Map<Symbol, Object?> named = const {},
}) {
  expect(call.memberName, member);
  expect(call.positionalArguments, positional);
  expect(call.namedArguments, named);
}
