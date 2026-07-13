import 'dart:async';

import 'package:dio/dio.dart' show CancelToken, Dio;
import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart' show ApiFailure;

/// Web SSE transport.
///
/// dio's web (`BrowserHttpClientAdapter`) uses `XMLHttpRequest` with
/// `responseType = 'arraybuffer'` and only produces its [ResponseBody] on the
/// XHR `load` event — i.e. when the request *completes*. A Server-Sent Events
/// stream never completes while it's open, so on the web build dio would sit
/// awaiting the response forever and deliver **zero** frames: live comments,
/// replies, reactions (and every other SSE feature) would silently never
/// update. This is exactly the "realtime doesn't work" symptom on the web app.
///
/// The Fetch API exposes the response body as a `ReadableStream`, which
/// `fetch_client` surfaces as an incremental [http.StreamedResponse]. We read
/// its byte stream and hand the same `Stream<List<int>>` back to the SSE parser
/// the native path uses, so callers are platform-agnostic.
///
/// Selected by the conditional import in [ApiClient.openEventStream] on the web
/// (no `dart.library.io`).
Future<Stream<List<int>>> openEventStream({
  required Dio dio, // unused on web; keeps a uniform cross-platform signature
  required String url,
  required Map<String, String> headers,
  CancelToken? cancelToken,
}) async {
  // A fresh client per stream: closing it aborts the underlying fetch, which is
  // how we tear the connection down on cancel/dispose.
  final client = FetchClient(mode: RequestMode.cors);
  final request = http.Request('GET', Uri.parse(url))
    ..headers.addAll(headers)
    ..persistentConnection = true;

  final http.StreamedResponse response;
  try {
    response = await client.send(request);
  } catch (_) {
    client.close();
    rethrow;
  }
  if (response.statusCode >= 400) {
    client.close();
    throw ApiFailure('errors.unexpected', statusCode: response.statusCode);
  }

  // Abort the fetch when the caller cancels (e.g. the view is disposed).
  cancelToken?.whenCancel.then((_) => client.close());

  // Bridge the response stream so the fetch client is always closed when the
  // stream ends — on completion, error, or the consumer cancelling — mirroring
  // dio's connection lifecycle on native.
  final out = StreamController<List<int>>();
  late final StreamSubscription<List<int>> sub;
  sub = response.stream.listen(
    out.add,
    onError: (Object e, StackTrace s) => out.addError(e, s),
    onDone: () {
      client.close();
      out.close();
    },
    cancelOnError: true,
  );
  out.onCancel = () async {
    await sub.cancel();
    client.close();
  };
  return out.stream;
}
