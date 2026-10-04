import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';

/// A repository fake that writes down every call and answers from a table.
///
/// The time module's cubits only hand calls on, so what their tests check is
/// the hand-over: which method, with which arguments, and that the answer or
/// the refusal comes back unchanged. Mixed into a class that `implements` the
/// repository and forwards [noSuchMethod] to [record], one fake covers every
/// method without restating its signature.
mixin RecordingRepository {
  /// Every call, in order.
  final List<Invocation> calls = [];

  /// What each method answers, by name. Typed futures, because the forwarder
  /// checks the answer against the method's return type.
  final Map<Symbol, Object> answers = {};

  /// Thrown by every call when set.
  ApiFailure? failure;

  Object? record(Invocation invocation) {
    calls.add(invocation);
    final refusal = failure;
    if (refusal != null) throw refusal;
    return answers[invocation.memberName];
  }
}

/// Matches a call to [member] with [positional] arguments and, of the named
/// ones, those [named] lists. Named arguments left out are not compared: a
/// forwarder fills in the method's defaults, and those are not the cubit's.
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

/// A refusal as the API client raises it.
final refusal = ApiFailure('errors.forbidden');

/// Matches [refusal] coming back out of the cubit.
final throwsRefusal = throwsA(same(refusal));
