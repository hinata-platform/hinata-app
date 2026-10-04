import 'package:hinata/core/api/api_client.dart';

/// A repository double for cubits that only forward: it records every call and
/// answers with what the test put under the member's name.
///
/// Mixed into a class that `implements` the repository, so no member has to be
/// written out; a call nobody answered fails the test loudly.
mixin RecordingFake {
  final List<Invocation> calls = [];

  /// The answer per member, built when it is called so a failing future is
  /// never left unawaited.
  final Map<Symbol, Object? Function()> answers = {};

  /// The one call that was made.
  Invocation get only => calls.single;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    final answer = answers[invocation.memberName];
    if (answer == null) {
      throw UnimplementedError('${invocation.memberName} is not answered');
    }
    return answer();
  }
}

/// A failure as the API client throws it.
final ApiFailure failure = ApiFailure('errors.test', statusCode: 400);
