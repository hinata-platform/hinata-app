/// Recognising "this route is switched off", as opposed to "this route does not
/// exist".
///
/// Optional server modules are gated by a platform feature flag. While the flag
/// is off the module's routes do not exist *for the client*: the server answers
/// 404 with the code `error.feature.disabled` rather than 403, so a client that
/// was never meant to know the module exists cannot probe for it.
///
/// The app has to tell that 404 apart from an ordinary one, because the two
/// deserve opposite reactions. An ordinary 404 is a dead link. This one means
/// our copy of `/api/v1/meta` is stale — the flag was flipped while we were
/// running — and the fix is to re-read it, not to show "not found".
library;

/// The wire code the server answers with when a flag-gated route is off.
///
/// The server localizes its error messages, so a live server sends a sentence
/// here, not this code — which is why [isFeatureDisabledResponse] matches on the
/// *route* first. The code is still matched because a server whose message
/// bundle lacks the key falls back to emitting the key itself, and because the
/// app's own bundle carries a translation for it.
const String kFeatureDisabledCode = 'error.feature.disabled';

/// Route prefixes that exist only while `advanced_time_tracking` is on.
///
/// Mirrors the single server-side prefix interceptor (HIN-83). Kept as a list of
/// prefixes rather than a regex because that is exactly how the server matches
/// them, and the two lists have to be readable side by side.
const List<String> kFlagGatedRoutePrefixes = [
  '/api/v1/time/',
  '/api/v1/me/timer',
  '/api/v1/availability/',
  '/api/v1/billing/',
  '/api/v1/me/calendar-subscriptions',
];

/// Whether [path] is served by a module that can be switched off.
bool isFlagGatedRoute(String path) =>
    kFlagGatedRoutePrefixes.any(path.contains);

/// Whether this response means "the module is switched off".
///
/// A 404 from a flag-gated route is the reliable signal; the localized message
/// cannot be matched. The code is accepted on its own as well, for a server that
/// hands back the raw key.
bool isFeatureDisabledResponse({
  required String path,
  required int? status,
  String? message,
}) {
  if (status != 404) return false;
  return isFlagGatedRoute(path) || message == kFeatureDisabledCode;
}
