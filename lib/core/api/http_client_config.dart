import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

/// The web side of [configureHttpClient]; the native one lives in
/// `http_client_config_io.dart` and is picked by a conditional import wherever
/// `dart.library.io` exists.
///
/// The browser owns the connection pool here, so there is nothing to tune but
/// the adapter's own log. Every call this app makes is a CORS preflight anyway
/// — the bearer token alone makes it one — and the server answers them, so
/// dio's per-request warning that a preflight will happen only buries the
/// debug console under a stack trace per request.
void configureHttpClient(Dio dio) {
  dio.httpClientAdapter = BrowserHttpClientAdapter(enableCORSWarning: false);
}
