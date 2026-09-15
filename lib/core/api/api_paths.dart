final _pathEnd = RegExp('[?#]');

/// A slash, or a backslash, which Dart's URI parser reads as one.
final _separator = RegExp(r'[/\\]');

final _encodedDot = RegExp('%2e', caseSensitive: false);

/// Whether [path] climbs out of where it points, with a `.` or `..` segment.
///
/// Ids go into request paths, and an id can come from an address anybody can
/// write: a board opened at `/board/..` would otherwise ask for
/// `/api/v1/boards/..`, which the URL resolves to another endpoint, sent with
/// this user's token (HIN-114). Encoding the id does not help, because `.` and
/// `..` stay what they are, `%2E` is read as a dot and `\` as a slash.
bool pathClimbs(String path) {
  final end = path.indexOf(_pathEnd);
  final segments = (end < 0 ? path : path.substring(0, end)).split(_separator);
  return segments.any((segment) {
    final dots = segment.replaceAll(_encodedDot, '.');
    return dots == '.' || dots == '..';
  });
}
