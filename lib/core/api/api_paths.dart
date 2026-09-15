/// Whether [path] climbs out of where it points, with a `.` or `..` segment.
///
/// Ids go into request paths, and an id can come from an address anybody can
/// write: a board opened at `/board/..` would otherwise ask for
/// `/api/v1/boards/..`, which the URL resolves to another endpoint, sent with
/// this user's token (HIN-114). Encoding the id does not help, because `.` and
/// `..` stay what they are, and `%2E` is read as a dot.
bool pathClimbs(String path) {
  final end = path.indexOf(RegExp('[?#]'));
  final segments = (end < 0 ? path : path.substring(0, end)).split('/');
  return segments.any((segment) {
    final dots = segment.replaceAll(RegExp('%2e', caseSensitive: false), '.');
    return dots == '.' || dots == '..';
  });
}
