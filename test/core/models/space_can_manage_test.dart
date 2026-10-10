import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/content_models.dart';

/// The server says per space whether the reader may delete it; a space somebody
/// only reads through one of its pages must not offer that.
void main() {
  test('a space the server marks as not theirs is not manageable', () {
    final space = Space.fromJson({
      'id': 's1',
      'name': 'Projektwissen',
      'canManage': false,
    });
    expect(space.canManage, isFalse);
  });

  test('a server from before the field keeps the old behaviour', () {
    expect(Space.fromJson({'id': 's1', 'name': 'Alt'}).canManage, isTrue);
  });
}
