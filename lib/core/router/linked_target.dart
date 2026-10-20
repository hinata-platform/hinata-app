import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// The mark a navigation from a link carries as its route's `extra`, so the
/// page it lands on can tell a second visit of the same link from a rebuild
/// of the first.
///
/// go_router hands a page the same address both times: picking the same
/// search hit twice is one address twice, and without a mark of its own the
/// router does not even rebuild the page. [LinkVisit.next] makes every such
/// navigation a visit of its own.
@immutable
class LinkVisit {
  const LinkVisit._(this._number);

  static int _count = 0;

  /// A visit no earlier navigation carried.
  factory LinkVisit.next() => LinkVisit._(++_count);

  final int _number;

  /// The visit [state] was navigated with. Null for a navigation that
  /// carried none (a link opened cold, a notification, the back button),
  /// which counts as one visit for as long as the page stays.
  static LinkVisit? of(GoRouterState state) {
    final extra = state.extra;
    return extra is LinkVisit ? extra : null;
  }

  @override
  bool operator ==(Object other) =>
      other is LinkVisit && other._number == _number;

  @override
  int get hashCode => _number.hashCode;
}

/// Goes to [route] as a visit of its own (see [LinkVisit]): the page there
/// opens what the link names even when it is already on screen with it.
void goToLink(BuildContext context, String route) =>
    context.go(route, extra: LinkVisit.next());

/// What a link asks a page to open (an entry, a request, a shift, a file, a
/// sprint) until the page has opened it.
///
/// The one pattern behind every page a link can point into. The page calls
/// [take] with the route's target and visit when it is built and again in
/// `didUpdateWidget`, and [openWhen] whenever what it needs to open the
/// target may have arrived (its first read, a page of a list, a month). The
/// target then opens once, after the frame and only while the page is still
/// there. A rebuild hands in the same target and visit and is ignored; a new
/// visit of the same link opens it again.
class LinkedTarget<T extends Object> {
  LinkedTarget(this._host);

  /// The page, asked whether it is still mounted when the frame is done.
  final State _host;

  T? _pending;
  (T, LinkVisit?)? _taken;

  /// The target still to open; null once it is open, given up, or when the
  /// link named none.
  T? get pending => _pending;

  /// Takes [target] from the route with the [visit] that asked for it.
  /// Returns whether it is to be opened: false for no target, or for the
  /// same target of the same visit taken before.
  bool take(T? target, LinkVisit? visit) {
    if (target == null || (target is String && target.isEmpty)) return false;
    final link = (target, visit);
    if (link == _taken) return false;
    _taken = link;
    _pending = target;
    return true;
  }

  /// Opens the pending target with [open] once [ready] says the page can,
  /// after the current frame: the page has to be built under whatever opens,
  /// and nothing may push a route mid-build.
  void openWhen({required bool ready, required void Function(T target) open}) {
    final target = _pending;
    if (target == null || !ready) return;
    _pending = null;
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (_host.mounted) open(target);
    });
    // Called from a listener rather than a build, no frame may be coming.
    binding.ensureVisualUpdate();
  }

  /// Gives the pending target up: what the page holds says it is not there.
  void drop() => _pending = null;
}
