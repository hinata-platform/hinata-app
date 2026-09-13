import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/time_privacy_models.dart';
import '../repositories/time_repository.dart';

/// The privacy notice of the time-tracking module and whether the reader has
/// confirmed it, held once for the whole app.
///
/// Null until the first read. The visibility inside is computed by the server
/// from the policies in force, so a screen that shows it calls [refresh] when it
/// opens rather than trusting a copy from earlier in the session.
///
/// It also answers the one question only the app can: whether the first-use
/// notice has already been offered in this session. Offered once and dismissed
/// without confirming, it waits for the next session instead of opening on every
/// view the person switches to.
class TimePrivacyCubit extends Cubit<TimePrivacy?> {
  TimePrivacyCubit(this._time) : super(null);

  final TimeRepository _time;

  Future<bool>? _inFlight;
  bool _offered = false;

  /// Reads the notice once. Repeated calls while a read is in flight join it.
  ///
  /// Answers whether a notice is held afterwards, so a screen that has nothing to
  /// show without one can offer another try instead of spinning.
  Future<bool> ensureLoaded() {
    if (state != null) return Future.value(true);
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  /// Reads it again, for a screen that shows the computed visibility. Answers
  /// whether a notice is held afterwards: the fresh one, or the last one read.
  Future<bool> refresh() =>
      _inFlight ??= _load().whenComplete(() => _inFlight = null);

  Future<bool> _load() async {
    try {
      final privacy = await _time.privacy();
      if (!isClosed) emit(privacy);
      return true;
    } catch (_) {
      // With the module off the route does not exist, and a notice that cannot
      // be loaded is not a reason to block anybody from working. The next screen
      // that opens asks again.
      return state != null;
    }
  }

  /// Records "Understood". Answers whether the server accepted it.
  Future<bool> acknowledge() async {
    try {
      final privacy = await _time.acknowledgePrivacy();
      if (!isClosed) emit(privacy);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether the first-use notice should open now, and marks it as offered.
  ///
  /// True at most once per session, and only for somebody who has never
  /// confirmed it.
  bool takeFirstUseOffer() {
    final privacy = state;
    if (privacy == null || privacy.acknowledged || _offered) return false;
    _offered = true;
    return true;
  }

  /// Forgets the session that just ended. The next sign-in may be another person
  /// on another server with another notice.
  void reset() {
    _offered = false;
    _inFlight = null;
    if (state != null) emit(null);
  }
}
