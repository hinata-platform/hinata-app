/// The in-app route a `hinata://time/…` link opens, or null.
///
/// Routes only. A query such as `?action=stop` is dropped: a link from a
/// notification, a widget or another app may open a screen, never act on the
/// timer, so a crafted link cannot stop somebody's work.
String? timeDeepLinkRoute(Uri uri) {
  if (uri.scheme != 'hinata' || uri.host != 'time') return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return '/time';
  if (segments.length == 1 && segments.first == 'focus') return '/time/focus';
  return '/time';
}
