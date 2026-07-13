import '../repositories/account_repository.dart';
import 'sse.dart';
import 'sse_connection.dart';

/// Holds the app-wide `/api/v1/me/stream` SSE connection open while the user is
/// signed in, so the server can sign this device out in real time.
///
/// When the user's session is revoked elsewhere — an admin "terminate all
/// sessions", a password reset, account deactivation, or signing this device
/// out from another one — the server pushes a `logout` frame here and [onLogout]
/// fires immediately, instead of the app only finding out on its next request
/// (which could be up to a full access-token lifetime away, or never while idle).
///
/// [start] is idempotent and, via [SseConnection], reconnects with capped
/// backoff and an idle watchdog (so a half-open stream can't silently swallow a
/// revocation); [stop] tears it down. Drive both from the auth lifecycle.
class AccountEventStream {
  AccountEventStream({
    required AccountRepository repository,
    required this.onLogout,
  }) : _repo = repository {
    _sse = SseConnection(
      open: (cancelToken) => _repo.meEventStream(cancelToken: cancelToken),
      onEvent: _onEvent,
      // Nothing to reconcile on reconnect: sign-out is purely event-driven, and
      // the watchdog already guarantees a dead stream is re-established.
    );
  }

  final AccountRepository _repo;

  /// Invoked when the server signals this device should sign out.
  final void Function() onLogout;

  late final SseConnection _sse;

  /// Opens the stream (no-op if already running).
  void start() => _sse.start();

  /// Closes the stream and cancels any pending reconnect.
  void stop() => _sse.stop();

  void _onEvent(SseEvent ev) {
    if (ev.event == 'logout') {
      _sse.stop();
      onLogout();
    }
  }
}
