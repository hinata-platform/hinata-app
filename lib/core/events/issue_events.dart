import 'dart:async';

/// App-wide broadcast for issue changes (create / update / delete).
///
/// Screens that render issues — the issues list, the board, the dashboard —
/// can never be reached by a page-local reload when the change originates from
/// *global* chrome such as the nav-rail "new issue" button: that chrome holds
/// no handle to the currently-visible page's cubit. This lightweight broadcast
/// decouples the two: the origin of a change calls [notifyChanged], and every
/// mounted screen subscribed to [changes] re-fetches through its existing
/// reload seam.
///
/// A single app-wide instance ([instance]) is intentional — the stream is a
/// broadcast controller, so it is safe to have many concurrent listeners and it
/// never needs disposing for the app's lifetime. Subscribers must still cancel
/// their own [StreamSubscription] in `dispose`.
class IssueEvents {
  IssueEvents._();

  /// The shared app-wide instance.
  static final IssueEvents instance = IssueEvents._();

  final StreamController<void> _controller = StreamController<void>.broadcast();

  /// Fires whenever an issue is created, updated or deleted anywhere in the app.
  Stream<void> get changes => _controller.stream;

  /// Signal that the set of issues changed so subscribed screens re-fetch.
  void notifyChanged() => _controller.add(null);
}
