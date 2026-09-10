import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/core_models.dart';
import '../storage/app_storage.dart';
import 'feature_gate.dart';
// Native-only HTTP connection tuning (idle keep-alive socket handling); a no-op
// on the web, selected by conditional import so `dart:io` never reaches the web
// build.
import 'http_client_config.dart'
    if (dart.library.io) 'http_client_config_io.dart';
// SSE transport: dio streams fine over dart:io, but its XHR web adapter can't
// stream an open response, so the web build opens the stream over the Fetch
// API instead. Same signature on both, selected by the conditional import.
import 'sse_transport_web.dart'
    if (dart.library.io) 'sse_transport_io.dart'
    as sse_transport;

/// Exception with a user-presentable message key.
class ApiFailure implements Exception {
  ApiFailure(
    this.message, {
    this.statusCode,
    this.featureDisabled = false,
    this.details = const {},
  });

  final String message;
  final int? statusCode;

  /// Machine-readable facts about a refusal, for the few the app has to *act*
  /// on rather than print.
  ///
  /// Empty for almost every error, and meant to stay that way: the localized
  /// [message] is what a screen shows, and a second copy of it in here would be
  /// a second contract to keep in step. It exists for the frozen time entry,
  /// which names why it is frozen, who can lift it and what the way back is —
  /// so the app can offer that way instead of leaving somebody at a dead end.
  final Map<String, String> details;

  /// The route is gated behind a platform feature flag that is currently off —
  /// "not switched on", not "not found".
  ///
  /// Nothing branches on this yet: the reaction that matters happens without the
  /// caller, in [ApiClient.onFeatureDisabled], which re-reads `/meta` so the app
  /// stops offering the route at all. It is here for the screens stage 3 brings,
  /// which can say something better than a dead end.
  final bool featureDisabled;

  @override
  String toString() => message;
}

/// Dio-based client bound to the configured server URL. Transparently
/// attaches the bearer token and refreshes it once on 401.
class ApiClient {
  ApiClient(this._storage) {
    // The app builds exactly one, in `main`. Recorded here because an
    // `ImageProvider` is not a widget: it is created inside a decorator
    // builder, cached by Flutter across routes, and asked to fetch its bytes
    // long after — and whichever `BuildContext` was around at the time may not
    // be mounted, or may never have been below the provider at all. An
    // authenticated image cannot depend on a tree lookup happening to succeed.
    instance = this;
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
    // Native only: drop idle keep-alive sockets before the server closes them,
    // so a reused-but-dead socket can't throw a spurious app-wide error.
    configureNativeHttpClient(_dio);
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _storage.accessToken;
          // Server metadata is deliberately public (it drives boot routing).
          // Do not attach a stale bearer token here: some servers reject an
          // invalid token before reaching a public endpoint, which would make
          // a revoked session look like a failed server connection.
          final isAnonymousBootRequest = options.path.contains('/api/v1/meta');
          if (token != null &&
              !isAnonymousBootRequest &&
              !options.path.contains('/auth/refresh')) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          // Tell the server which language to localize error messages in.
          options.headers['Accept-Language'] = localeCode;
          handler.next(options);
        },
        onError: (error, handler) async {
          // A rejected refresh token must end the refresh attempt. Retrying the
          // refresh request through this interceptor would await the in-flight
          // `_refreshing` future from inside itself, leaving startup stuck on
          // the connecting screen after sessions are revoked server-side.
          final isRefreshRequest = error.requestOptions.path.contains(
            '/auth/refresh',
          );
          if (error.response?.statusCode == 401 &&
              !isRefreshRequest &&
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
          // A module that is switched off answers 404 on its own routes. We only
          // asked because our copy of /meta said the module was on, so that copy
          // is stale — ask for a fresh one instead of showing "not found".
          if (isFeatureDisabledResponse(
            path: error.requestOptions.path,
            status: error.response?.statusCode,
            message: () => _messageOf(_asMessageBody(error.response?.data)),
          )) {
            onFeatureDisabled?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  /// The client this app is running on, or null before `main` has built one.
  ///
  /// A last resort for the few callers that genuinely cannot reach a
  /// `BuildContext` — an [ImageProvider] fetching bytes for a cached image is
  /// the case this exists for. Everything that *can* take the client from the
  /// tree still should: this is one instance per process, so a test that builds
  /// two would see only the second.
  static ApiClient? instance;

  final AppStorage _storage;
  late final Dio _dio;

  /// In-flight refresh, shared by every request that 401s at the same time so
  /// they trigger ONE `/auth/refresh` instead of a thundering herd (which wastes
  /// connections and — if the server rotates refresh tokens — makes all but the
  /// first refresh fail and wipe the session). Cleared when the refresh settles.
  Future<bool>? _refreshing;

  /// Invoked when the session can no longer be refreshed.
  void Function()? onSessionExpired;

  /// Invoked when the server says a flag-gated module is switched off — the cue
  /// to re-read `/api/v1/meta`, because our feature flags are out of date.
  void Function()? onFeatureDisabled;

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

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _run(
    () => _dio.get<dynamic>('$baseUrl$path', queryParameters: query),
    idempotent: true,
  );

  /// Raw binary GET (e.g. the logo proxy). Returns the bytes and the response
  /// content-type, or null on any non-2xx / transport error. Retried once on a
  /// transient connection loss (a reused-but-dead keep-alive socket).
  Future<({List<int> bytes, String contentType})?> getBytes(String path) async {
    for (var attempt = 0; attempt < 2; attempt++) {
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
      } on DioException catch (error) {
        if (attempt == 0 && _isTransientConnectionLoss(error)) continue;
        // Said out loud in debug: every caller of this turns a null into a
        // silent fallback — an avatar's initials, an image's placeholder — so
        // without this a failure looks exactly like "there was nothing there",
        // and the status code that would explain it is thrown away here.
        if (kDebugMode) {
          debugPrint(
            '[api] GET $path failed: '
            '${error.response?.statusCode ?? error.type.name} '
            '${error.message ?? ''}',
          );
        }
        return null;
      } catch (error) {
        if (kDebugMode) debugPrint('[api] GET $path failed: $error');
        return null;
      }
    }
    return null;
  }

  /// Binary GET for a file the user asked for, which fails loudly.
  ///
  /// [getBytes] above answers null for everything, which is right where a
  /// missing avatar falls back to initials — and wrong here. A download the
  /// user started has to be able to say *why* it did not arrive: refused,
  /// throttled, or the connection. So this goes through the same [_run] as
  /// every other verb and throws [ApiFailure] with the server's own message.
  ///
  /// [receiveTimeout] widens the window for a document the server has to render
  /// before it can answer, the way [upload] widens it for bytes going the other
  /// way.
  Future<Uint8List> getFileBytes(
    String path, {
    Duration? receiveTimeout,
  }) async {
    final data = await _run(
      () => _dio.get<List<int>>(
        '$baseUrl$path',
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: receiveTimeout,
        ),
      ),
      idempotent: true,
    );
    return Uint8List.fromList((data as List<int>?) ?? const []);
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
  }) {
    final token = _storage.accessToken;
    return sse_transport.openEventStream(
      dio: _dio,
      url: '$baseUrl$path',
      headers: {
        'Accept': 'text/event-stream',
        // Attach the bearer explicitly: the streamed request must carry auth on
        // both transports (dio on native, Fetch on web).
        if (token != null) 'Authorization': 'Bearer $token',
        // Mirror the base client so the streamed request isn't intercepted by
        // ngrok's browser warning and is localized like every other call.
        'ngrok-skip-browser-warning': 'true',
        'Accept-Language': localeCode,
      },
      cancelToken: cancelToken,
    );
  }

  Future<dynamic> _run(
    Future<Response<dynamic>> Function() request, {
    bool idempotent = false,
  }) async {
    try {
      return (await request()).data;
    } on DioException catch (error) {
      // A transient connection loss (a keep-alive socket the pool handed us was
      // already closed by the server) is exactly the failure a manual retry
      // recovers from. Do it once, transparently, for idempotent (GET) requests
      // on a fresh socket — so a single stale connection never paints a whole
      // screen with `errors.unexpected`. Never retry a mutation (could double it)
      // and never retry a real HTTP error (it carries a response we must surface).
      if (idempotent && _isRetriableConnectionFailure(error)) {
        try {
          return (await request()).data;
        } on DioException catch (retryError) {
          throw _toFailure(retryError);
        }
      }
      throw _toFailure(error);
    }
  }

  /// A transport-level failure with no HTTP response — a reused-but-dead
  /// keep-alive socket, a connection reset, or a drop mid-flight. Safe to retry
  /// for idempotent requests; deliberately excludes any 4xx/5xx (those carry a
  /// response) and read/connect timeouts (already waited the full window — a
  /// retry would just double the wait).
  static bool _isTransientConnectionLoss(DioException error) {
    if (error.response != null) return false;
    return error.type == DioExceptionType.unknown ||
        error.type == DioExceptionType.connectionError;
  }

  /// Failures a single fresh-socket retry of an IDEMPOTENT (GET) request can
  /// recover. Beyond [_isTransientConnectionLoss] this also covers
  /// `connectionTimeout`: on mobile the first connection to the edge sometimes
  /// stalls the full connect window (a slow-to-accept proxy, or a half-open
  /// socket) and then fails — the classic "the issue took ~10s then failed, but
  /// trying again worked". Auto-retrying turns that manual retry into a
  /// transparent one. `receiveTimeout` is still excluded: there the server
  /// already has the request, so a retry would just double a genuinely slow
  /// response; any 4xx/5xx is excluded too (it carries a response to surface).
  static bool _isRetriableConnectionFailure(DioException error) {
    if (error.response != null) return false;
    return error.type == DioExceptionType.unknown ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout;
  }

  /// The error body as something a message can be read out of.
  ///
  /// A request that asked for bytes gets its *error* body as bytes too, so the
  /// server's perfectly good explanation arrives as a list of numbers and every
  /// binary download would report "errors.unexpected" whatever went wrong.
  static Object? _asMessageBody(Object? data) {
    if (data is! List<int>) return data;
    try {
      return jsonDecode(utf8.decode(data));
    } catch (_) {
      return null;
    }
  }

  /// The server's message out of an already-decoded error body, if there is one.
  static String? _messageOf(Object? data) =>
      (data is Map && data['message'] is String)
      ? data['message'] as String
      : null;

  /// The `details` object of an error body, flattened to strings.
  ///
  /// Tolerant on purpose: an older server sends no such key, and a newer one may
  /// add a field this build has never heard of. Neither is an error — a missing
  /// key reads as "this refusal has no machine-readable part", which is true.
  static Map<String, String> _detailsOf(Object? body) {
    final raw = body is Map ? body['details'] : null;
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value != null) '${entry.key}': '${entry.value}',
    };
  }

  ApiFailure _toFailure(DioException error) {
    final status = error.response?.statusCode;
    final data = _asMessageBody(error.response?.data);
    final message = _messageOf(data);
    final featureDisabled = isFeatureDisabledResponse(
      path: error.requestOptions.path,
      status: status,
      message: () => message,
    );
    if (message != null) {
      return ApiFailure(
        message,
        statusCode: status,
        featureDisabled: featureDisabled,
        details: _detailsOf(data),
      );
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError => ApiFailure(
        'errors.connection',
        statusCode: status,
      ),
      _ => ApiFailure(
        featureDisabled ? kFeatureDisabledCode : 'errors.unexpected',
        statusCode: status,
        featureDisabled: featureDisabled,
      ),
    };
  }
}
