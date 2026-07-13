import 'package:dio/dio.dart';

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
  return response.data!.stream;
}
