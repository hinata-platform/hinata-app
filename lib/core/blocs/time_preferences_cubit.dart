import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/account_models.dart';
import '../repositories/account_repository.dart';

/// How this account likes its timer to count, as one live value.
///
/// The lengths and the sound live on the account, which means the server owns
/// them and two devices agree — but three places in the app need them at once:
/// the focus screen when it starts a run, the settings panel that edits them,
/// and the listener that decides whether an interval ending makes a sound. A
/// value read separately by each would be three reads and three ways to be
/// stale, and the panel changing a number would not reach the other two until
/// the next launch.
///
/// It starts on the defaults rather than on nothing: they are a working rhythm,
/// so a screen that opens before the account has been read has a real answer
/// rather than a spinner over four numbers.
class TimePreferencesCubit extends Cubit<TimePreferences> {
  TimePreferencesCubit(this._account) : super(const TimePreferences());

  final AccountRepository _account;

  /// Re-reads them from the account. A failure keeps what is held: nothing here
  /// is worth an error message, and the defaults are usable.
  Future<void> load() async {
    try {
      adopt((await _account.meAccount()).timePreferences);
    } catch (_) {
      // What we have stands.
    }
  }

  /// Takes preferences that arrived with an account read somebody else made.
  void adopt(TimePreferences preferences) {
    _confirmed = preferences;
    if (preferences != state) emit(preferences);
  }

  /// How long a burst of taps is collected before anything is written.
  ///
  /// Long enough that pressing `+` five times is one request, short enough that
  /// somebody who taps once and closes the panel has already saved.
  static const Duration _settle = Duration(milliseconds: 450);

  Timer? _debounce;
  Completer<bool>? _awaiting;

  /// The last value the server acknowledged. What a refusal rolls back to —
  /// rolling back to the previous *optimistic* value would restore a number the
  /// server never accepted either.
  TimePreferences _confirmed = const TimePreferences();

  /// Writes them, showing the new value at once.
  ///
  /// Optimistic because the panel is a row of steppers: a number that only
  /// moved after a round trip would feel broken, and the only thing at stake is
  /// a preference.
  ///
  /// The write itself is collected. Five taps of `+` used to be five `PATCH`
  /// requests, each carrying the whole document, with no ordering guarantee
  /// between them — so the fourth could land after the fifth and leave the
  /// server holding a value the client is not showing, uncorrected until the
  /// next launch. One request per burst makes that impossible rather than
  /// unlikely.
  Future<bool> save(TimePreferences next) {
    if (next == state) return Future.value(true);
    emit(next);
    _debounce?.cancel();
    final awaiting = _awaiting ??= Completer<bool>();
    _debounce = Timer(_settle, () {
      _awaiting = null;
      unawaited(_write().then(awaiting.complete));
    });
    return awaiting.future;
  }

  Future<bool> _write() async {
    final asked = state;
    try {
      final saved = await _account.updateMyProfile(timePreferences: asked);
      _confirmed = saved.timePreferences;
      // Only if nothing newer has been asked for in the meantime — a burst that
      // started again during the round trip must not be undone by its answer.
      if (asked == state) adopt(_confirmed);
      return true;
    } catch (_) {
      if (asked == state) emit(_confirmed);
      return false;
    }
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
