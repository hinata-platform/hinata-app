import 'package:dio/dio.dart';

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
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Accept': 'application/json',
        // Bypass the ngrok free-tier browser interstitial: without this header
        // ngrok answers API calls with an HTML warning page instead of JSON.
        // Harmless against any other host, so it is sent unconditionally.
        'ngrok-skip-browser-warning': 'true',
      },
    ));
    _dio.interceptors.add(InterceptorsWrapper(
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
            options.headers['Authorization'] = 'Bearer ${_storage.accessToken}';
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
    ));
  }

  final AppStorage _storage;
  late final Dio _dio;

  /// Invoked when the session can no longer be refreshed.
  void Function()? onSessionExpired;

  /// Language code sent as `Accept-Language` so the server localizes error
  /// messages. Kept in sync with the app's [LocaleCubit] (see HivoraApp).
  String localeCode = 'en';

  String get baseUrl => _storage.serverUrl ?? '';

  Uri resolve(String path) => Uri.parse('$baseUrl$path');

  Future<bool> _tryRefresh() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/api/v1/auth/refresh',
        data: {'refreshToken': _storage.refreshToken},
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
        contentType:
            (response.headers.value('content-type') ?? '').toLowerCase(),
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

  Future<dynamic> delete(String path) =>
      _run(() => _dio.delete<dynamic>('$baseUrl$path'));

  Future<dynamic> upload(String path, MultipartFile file) => _run(() =>
      _dio.post<dynamic>('$baseUrl$path', data: FormData.fromMap({'file': file})));

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
      DioExceptionType.connectionError =>
        ApiFailure('errors.connection', statusCode: status),
      _ => ApiFailure('errors.unexpected', statusCode: status),
    };
  }
}
