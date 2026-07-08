import 'dart:async';

import 'package:dio/dio.dart';

import 'hinata_repository.dart';
import 'sse.dart';

/// Holds the app-wide `/api/v1/me/stream` SSE connection open while the user is
/// signed in, so the server can sign this device out in real time.
///
/// When the user's session is revoked elsewhere — an admin "terminate all
/// sessions", a password reset, account deactivation, or signing this device
/// out from another one — the server pushes a `logout` frame here and [onLogout]
/// fires immediately, instead of the app only finding out on its next request
/// (which could be up to a full access-token lifetime away, or never while idle).
///
/// [start] is idempotent and reconnects with capped backoff if the stream
/// drops; [stop] tears it down. Drive both from the auth lifecycle.
class AccountEventStream {
  AccountEventStream({required HinataRepository repository, required this.onLogout})
      : _repo = repository;

  final HinataRepository _repo;

  /// Invoked when the server signals this device should sign out.
  final void Function() onLogout;

  CancelToken? _cancel;
  StreamSubscription<SseEvent>? _sub;
  Timer? _reconnect;
  int _attempts = 0;
  bool _running = false;

  /// Opens the stream (no-op if already running).
  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  /// Closes the stream and cancels any pending reconnect.
  void stop() {
    _running = false;
    _reconnect?.cancel();
    _reconnect = null;
    _sub?.cancel();
    _sub = null;
    _cancel?.cancel();
    _cancel = null;
    _attempts = 0;
  }

  Future<void> _connect() async {
    if (!_running) return;
    _cancel = CancelToken();
    try {
      final bytes = await _repo.meEventStream(cancelToken: _cancel);
      // Stopped WHILE the stream was opening → tear the just-opened connection
      // down instead of subscribing to it (else it leaks an open HTTP stream).
      if (!_running) {
        _cancel?.cancel();
        return;
      }
      _attempts = 0; // connected — reset the backoff
      _sub = parseSse(bytes).listen(
        _onEvent,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _sub?.cancel();
    _sub = null;
    if (!_running) return;
    _reconnect?.cancel();
    // Exponential backoff (3s → 30s cap) so a persistently failing stream
    // (e.g. SSE not streamable on the web platform) doesn't hammer the server.
    final secs = (3 * (1 << _attempts)).clamp(3, 30);
    _attempts = (_attempts + 1).clamp(0, 4);
    _reconnect = Timer(Duration(seconds: secs), _connect);
  }

  void _onEvent(SseEvent ev) {
    if (!_running) return;
    if (ev.event == 'logout') {
      stop();
      onLogout();
    }
  }
}
