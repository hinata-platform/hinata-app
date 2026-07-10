import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Tunes the native `HttpClient` so the client drops idle keep-alive sockets
/// *before* the server closes them.
///
/// The failure this prevents: an issue-open fires ~12–15 GETs and every
/// pin/react/edit leaves more keep-alive sockets idling in the shared pool.
/// Embedded Tomcat on its defaults closes a pooled socket out from under the
/// client (idle keep-alive timeout, or after N requests on one connection). The
/// next request the pool hands out reuses that already-closed socket and
/// `dart:io` throws `HttpException: Connection closed before full header was
/// received`. Dio wraps that as [DioExceptionType.unknown] (no HTTP response),
/// which surfaces as a generic `errors.unexpected` on whatever screen happened
/// to draw the dead socket — an app-wide error from one stale connection.
///
/// A short client-side `idleTimeout` (well under any reasonable server keep-alive
/// window) makes the *client* the one that retires idle connections, collapsing
/// the reuse-race window. It does not affect in-flight requests, so long-lived
/// SSE streams (an open, still-consuming response) are untouched. The
/// `ApiClient`'s one-shot idempotent-GET retry covers anything that still slips
/// through (e.g. a server with an even shorter keep-alive).
void configureNativeHttpClient(Dio dio) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.idleTimeout = const Duration(seconds: 5);
      return client;
    },
  );
}
