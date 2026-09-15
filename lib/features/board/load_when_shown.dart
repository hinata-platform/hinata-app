import 'dart:async';

import 'package:flutter/widgets.dart';

/// Reads a list only while its route is the current one.
///
/// A board opens on top of the list it came from, also when it is reloaded at
/// its own address (HIN-114). A list that read everything the moment it was
/// built would compete with the board's own first requests for a page nobody
/// sees. So the list starts out of date and reads once its route is current,
/// and [markStale] asks again: at once while the list is shown, otherwise once
/// it is.
mixin LoadWhenShown<T extends StatefulWidget> on State<T> {
  bool _stale = true;

  /// Reads the list.
  Future<void> loadShown();

  /// The list is out of date: read it now if it is shown, otherwise once it is.
  void markStale() {
    _stale = true;
    _loadIfShown();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadIfShown();
  }

  void _loadIfShown() {
    if (!mounted) return;
    // Asked before anything else: it subscribes to the route, which is what
    // calls this again once the page above the list is gone.
    final shown = ModalRoute.isCurrentOf(context) ?? true;
    if (!shown || !_stale) return;
    _stale = false;
    unawaited(loadShown());
  }
}
