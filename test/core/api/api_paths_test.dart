import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_paths.dart';

/// A request path built from an id somebody wrote into an address must not
/// reach another endpoint (HIN-114).
void main() {
  test('a path with a dot segment climbs', () {
    expect(pathClimbs('/api/v1/boards/..'), isTrue);
    expect(pathClimbs('/api/v1/boards/../projects/p1'), isTrue);
    expect(pathClimbs('/api/v1/boards/./wall'), isTrue);
    expect(pathClimbs('/api/v1/boards/%2E%2E/wall'), isTrue);
    expect(pathClimbs('/api/v1/boards/%2e./wall'), isTrue);
  });

  test('an ordinary path does not', () {
    expect(pathClimbs('/api/v1/boards/6a6406a34ac0/wall'), isFalse);
    // One segment: the slashes are encoded, so the server reads one id.
    expect(pathClimbs('/api/v1/boards/..%2F..%2Fadmin/wall'), isFalse);
    expect(pathClimbs('/api/v1/issues?q=..'), isFalse);
    expect(pathClimbs('/api/v1/articles/v1.2'), isFalse);
  });
}
