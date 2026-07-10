import 'package:dio/dio.dart';

/// Applies native (`dart:io`) HTTP connection tuning to [dio]. This is the
/// web-safe stub — a no-op, because on the web the browser owns the connection
/// pool and neither `dart:io` nor `IOHttpClientAdapter` exist. The real
/// implementation lives in `http_client_config_io.dart` and is selected by a
/// conditional import on platforms that have `dart.library.io`.
void configureNativeHttpClient(Dio dio) {}
