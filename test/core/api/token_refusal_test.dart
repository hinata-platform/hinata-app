import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';

/// The one question behind "why was I signed out just now".
///
/// A session used to end on *any* failed request: the client cleared its tokens
/// whenever a refresh did not come back, and the auth bloc cleared them whenever
/// `/me` threw. `ApiFailure` is thrown for every failure this client sees —
/// a 429 from the auth budget (ten a minute, shared by every client on one
/// address), a 503 from a server coming back up, a read that timed out, a
/// keep-alive socket the pool had already lost. So a blip signed somebody out
/// in the middle of their work, at no particular moment, which is exactly what
/// it looked like from the outside.
void main() {
  test('only the statuses that refuse a token end a session', () {
    for (final status in const [400, 401, 403]) {
      expect(refusesTheToken(status), isTrue, reason: '$status');
    }
  });

  test('a server that never answered the question keeps the session', () {
    for (final status in const [
      null, // no response at all: a timeout, a reset, a socket that never opened
      408,
      409,
      429, // the auth budget, which every client on one address shares
      500,
      502,
      503,
      504,
    ]) {
      expect(refusesTheToken(status), isFalse, reason: '$status');
    }
  });
}
