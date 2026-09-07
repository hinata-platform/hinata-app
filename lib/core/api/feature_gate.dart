/// Recognising "this route is switched off", as opposed to "this route does not
/// exist".
///
/// Optional server modules are gated by a platform feature flag. While the flag
/// is off the module's routes do not exist *for the client*: the server answers
/// 404 rather than 403, because "denied" would be the wrong word for something
/// that is not on this server at all.
///
/// The app has to tell that 404 apart from an ordinary one, because the two
/// deserve opposite reactions. An ordinary 404 is a dead link. This one means
/// our copy of `/api/v1/meta` is stale — the flag was flipped while we were
/// running — and the fix is to re-read it, not to show "not found".
library;

/// The wire code the server answers with when a flag-gated route is off.
///
/// The server localizes its error messages, so a live server sends a sentence
/// here, not this code — which is why [isFeatureDisabledResponse] decides on the
/// *route* first. The code is still matched, for a server whose message bundle
/// lacks the key and falls back to emitting it.
const String kFeatureDisabledCode = 'error.feature.disabled';

/// Route prefixes that exist only while `advanced_time_tracking` is on.
///
/// These mirror `AdvancedTimeTrackingGate.GATED_PATTERNS` in hinata-server, and
/// they have to be written the same way the server writes them: as the prefix
/// itself, with no trailing slash. The server gates both `/api/v1/time` and
/// everything under it, because the bare path is what a client calls for a
/// collection — `GET /api/v1/time?from=…` is the entry list. A list here that
/// only recognised `/api/v1/time/` would miss exactly that request, and the
/// stale-flag recovery would never fire on the one screen most likely to hit it.
///
/// Adding a sixth prefix means editing this list and that one. `gated prefixes`
/// in a search finds both.
const List<String> kFlagGatedRoutePrefixes = [
  '/api/v1/time',
  '/api/v1/me/timer',
  '/api/v1/availability',
  '/api/v1/billing',
  '/api/v1/me/calendar-subscriptions',
];

/// Whether [path] is served by a module that can be switched off.
///
/// Matched on segment boundaries, not as a substring: `/api/v1/timesheet` is the
/// base timesheet that exists on every server and must never be read as part of
/// the module, and a filter value that happened to contain `/api/v1/billing`
/// must not turn an unrelated 404 into "the module is off".
bool isFlagGatedRoute(String path) {
  final route = _routeOf(path);
  return kFlagGatedRoutePrefixes.any(
    (prefix) => route == prefix || route.startsWith('$prefix/'),
  );
}

/// The path portion of [path] — dio hands us whatever the caller passed, which
/// may carry a query string or a fragment.
String _routeOf(String path) {
  final cut = path.indexOf(RegExp(r'[?#]'));
  return cut == -1 ? path : path.substring(0, cut);
}

/// Whether this response means "the module is switched off".
///
/// [message] is a callback because reading it can mean decoding a byte body,
/// and for everything that is not a 404 the answer is already no.
bool isFeatureDisabledResponse({
  required String path,
  required int? status,
  String? Function()? message,
}) {
  if (status != 404) return false;
  return isFlagGatedRoute(path) || message?.call() == kFeatureDisabledCode;
}
