import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Native SSE transport. dio's `IOHttpClientAdapter` (dart:io) delivers the
/// response body incrementally, so we can consume `response.data.stream`
/// directly as SSE frames arrive. This is the long-standing, working path on
/// mobile/desktop — the web build uses a Fetch-based variant instead because
/// dio's XHR web adapter can't stream an open response (see the web file).
///
/// Selected by the conditional import in [ApiClient.openEventStream] whenever
/// `dart.library.io` is available.
Future<Stream<List<int>>> openEventStream({
  required Dio dio,
  required String url,
  required Map<String, String> headers,
  CancelToken? cancelToken,
}) async {
  final response = await dio.get<ResponseBody>(
    url,
    options: Options(
      responseType: ResponseType.stream,
      // Disable the receive timeout so the idle SSE connection is not aborted.
      receiveTimeout: Duration.zero,
      headers: headers,
    ),
    cancelToken: cancelToken,
  );
  return withoutCancellation(response.data!.stream);
}

/// [bytes] without the error a deliberate cancel ends it with.
///
/// Stopping a connection cancels its token, and dio answers by closing the
/// response stream with a "request cancelled" error. By then the SSE parser
/// has been told to stop listening, but an `async*` generator only notices at
/// its next event — so that error arrived at a generator nobody listened to
/// any more and surfaced as an uncaught error on every page that closed an
/// open stream (leaving an issue, for one). A cancel we asked for is not a
/// failure; every other error still passes through.
@visibleForTesting
Stream<List<int>> withoutCancellation(Stream<List<int>> bytes) =>
    bytes.handleError(
      (Object _) {},
      test: (error) => error is DioException && CancelToken.isCancel(error),
    );
