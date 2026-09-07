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
    this.onTimerChanged,
    void Function()? onReconnect,
  }) : _repo = repository {
    _sse = SseConnection(
      open: (cancelToken) => _repo.meEventStream(cancelToken: cancelToken),
      onEvent: _onEvent,
      // Sign-out needs nothing on reconnect — it is purely event-driven and the
      // watchdog already guarantees a dead stream is re-established. The timer
      // does: it is *state*, and a frame that arrived while the stream was down
      // arrived nowhere. Whoever owns that state re-reads it here.
      onReconnect: onReconnect,
    );
  }

  final AccountRepository _repo;

  /// Invoked when the server signals this device should sign out.
  final void Function() onLogout;

  /// Invoked when the running timer started, stopped or changed elsewhere.
  ///
  /// Carries no payload on purpose. The frame says that something happened;
  /// what is now true is a question for `GET /me/timer`, and a client that
  /// trusted the frame would be wrong every time one went missing — which the
  /// stream, being best-effort and scoped to a single server instance, allows.
  final void Function()? onTimerChanged;

  late final SseConnection _sse;

  /// Opens the stream (no-op if already running).
  void start() => _sse.start();

  /// Closes the stream and cancels any pending reconnect.
  void stop() => _sse.stop();

  void _onEvent(SseEvent ev) {
    if (ev.event == 'logout') {
      _sse.stop();
      onLogout();
      return;
    }
    if (ev.event == 'timer') {
      onTimerChanged?.call();
    }
  }
}
