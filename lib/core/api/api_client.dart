import 'package:dio/dio.dart';

import '../models/core_models.dart';
import '../storage/app_storage.dart';

/// Exception with a user-presentable message key.
class ApiFailure implements Exception {
  ApiFailure(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Dio-based client bound to the configured server URL. Transparently
/// attaches the bearer token and refreshes it once on 401.
class ApiClient {
  ApiClient(this._storage) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Accept': 'application/json',
          // Bypass the ngrok free-tier browser interstitial: without this header
          // ngrok answers API calls with an HTML warning page instead of JSON.
          // Harmless against any other host, so it is sent unconditionally.
          'ngrok-skip-browser-warning': 'true',
        },
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _storage.accessToken;
          if (token != null && !options.path.contains('/auth/refresh')) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          // Tell the server which language to localize error messages in.
          options.headers['Accept-Language'] = localeCode;
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 &&
              _storage.refreshToken != null &&
              error.requestOptions.extra['retried'] != true) {
            final refreshed = await _tryRefresh();
            if (refreshed) {
              final options = error.requestOptions;
              options.extra['retried'] = true;
              options.headers['Authorization'] =
                  'Bearer ${_storage.accessToken}';
              try {
                final response = await _dio.fetch<dynamic>(options);
                return handler.resolve(response);
              } on DioException catch (retryError) {
                return handler.next(retryError);
              }
            }
            onSessionExpired?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  final AppStorage _storage;
  late final Dio _dio;

  /// In-flight refresh, shared by every request that 401s at the same time so
  /// they trigger ONE `/auth/refresh` instead of a thundering herd (which wastes
  /// connections and — if the server rotates refresh tokens — makes all but the
  /// first refresh fail and wipe the session). Cleared when the refresh settles.
  Future<bool>? _refreshing;

  /// Invoked when the session can no longer be refreshed.
  void Function()? onSessionExpired;

  /// Language code sent as `Accept-Language` so the server localizes error
  /// messages. Kept in sync with the app's [LocaleCubit] (see HinataApp).
  String localeCode = 'en';

  String get baseUrl => _storage.serverUrl ?? '';

  Uri resolve(String path) => Uri.parse('$baseUrl$path');

  /// One-off reachability probe of a *candidate* server [url] — not the bound
  /// one. Times a `GET <url>/api/v1/meta` over a throwaway Dio that carries **no
  /// bearer** (the current server's token must never reach another host) with a
  /// short timeout. Returns the [ServerProbe], or null on a malformed URL or any
  /// transport / non-2xx error. Used by the "add server" connection test.
  Future<ServerProbe?> probe(String url) async {
    var base = url.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    final uri = Uri.tryParse(base);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return null;
    }
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
        headers: {
          'Accept': 'application/json',
          'ngrok-skip-browser-warning': 'true',
          'Accept-Language': localeCode,
        },
      ),
    );
    final stopwatch = Stopwatch()..start();
    try {
      final response = await dio.get<dynamic>('$base/api/v1/meta');
      stopwatch.stop();
      final data = response.data;
      if (data is! Map<String, dynamic>) return null;
      final meta = ServerMeta.fromJson(data);
      return ServerProbe(
        ms: stopwatch.elapsedMilliseconds,
        version: meta.serverVersion,
        tls: uri.isScheme('https'),
        setupCompleted: meta.setupCompleted,
        org: meta.organizationName,
      );
    } catch (_) {
      return null;
    } finally {
      dio.close();
    }
  }

  /// Single-flight refresh: concurrent 401s all await the same in-flight call.
  Future<bool> _tryRefresh() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    // Snapshot the refresh token now: a parallel request may have already
    // rotated it by the time this runs, but the single-flight guard means only
    // one _doRefresh is ever in flight, so this is the current one.
    final refresh = _storage.refreshToken;
    if (refresh == null) return false;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/api/v1/auth/refresh',
        data: {'refreshToken': refresh},
      );
      final data = response.data!;
      await _storage.setTokens(
        access: data['accessToken'] as String,
        refresh: data['refreshToken'] as String,
      );
      return true;
    } catch (_) {
      await _storage.clearTokens();
      return false;
    }
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _run(() => _dio.get<dynamic>('$baseUrl$path', queryParameters: query));

  /// Raw binary GET (e.g. the logo proxy). Returns the bytes and the response
  /// content-type, or null on any non-2xx / transport error.
  Future<({List<int> bytes, String contentType})?> getBytes(String path) async {
    try {
      final response = await _dio.get<List<int>>(
        '$baseUrl$path',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      return (
        bytes: bytes,
        contentType: (response.headers.value('content-type') ?? '')
            .toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> post(String path, {Object? body}) =>
      _run(() => _dio.post<dynamic>('$baseUrl$path', data: body));

  Future<dynamic> patch(String path, {Object? body}) =>
      _run(() => _dio.patch<dynamic>('$baseUrl$path', data: body));

  Future<dynamic> put(String path, {Object? body}) =>
      _run(() => _dio.put<dynamic>('$baseUrl$path', data: body));

  Future<dynamic> delete(String path, {Object? body}) =>
      _run(() => _dio.delete<dynamic>('$baseUrl$path', data: body));

  Future<dynamic> upload(
    String path,
    MultipartFile file, {
    void Function(int sent, int total)? onSendProgress,
    CancelToken? cancelToken,
    Map<String, dynamic>? fields,
  }) => _run(
    () => _dio.post<dynamic>(
      '$baseUrl$path',
      data: FormData.fromMap({'file': file, ...?fields}),
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
      // Uploads (attachments, voice) can take far longer than the default
      // 20s receive timeout, especially on mobile. Native Dio enforces that
      // timeout and would abort a slow upload *after* the server already
      // stored the file (web/XHR ignores it, hence "only mobile"). Give upload
      // requests a generous window matching the max upload size.
      options: Options(
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 5),
      ),
    ),
  );

  /// Opens a long-lived Server-Sent Events stream and returns the raw byte
  /// stream (callers parse SSE frames). The bearer token is attached as usual;
  /// the receive timeout is disabled so the idle connection is not aborted.
  Future<Stream<List<int>>> openEventStream(
    String path, {
    CancelToken? cancelToken,
  }) async {
    final token = _storage.accessToken;
    final response = await _dio.get<ResponseBody>(
      '$baseUrl$path',
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: Duration.zero,
        headers: {
          'Accept': 'text/event-stream',
          // Attach the bearer explicitly: the streamed request must carry auth
          // even on the web adapter, which handles stream responses specially.
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ),
      cancelToken: cancelToken,
    );
    return response.data!.stream;
  }

  Future<dynamic> _run(Future<Response<dynamic>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (error) {
      throw _toFailure(error);
    }
  }

  ApiFailure _toFailure(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    if (data is Map && data['message'] is String) {
      return ApiFailure(data['message'] as String, statusCode: status);
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError => ApiFailure(
        'errors.connection',
        statusCode: status,
      ),
      _ => ApiFailure('errors.unexpected', statusCode: status),
    };
  }
}
