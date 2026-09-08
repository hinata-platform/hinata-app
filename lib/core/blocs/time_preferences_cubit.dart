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
    if (preferences != state) emit(preferences);
  }

  /// Writes them, showing the new value at once.
  ///
  /// Optimistic because the panel is a row of steppers: a number that only
  /// moved after a round trip would feel broken, and the only thing at stake is
  /// a preference. A refusal puts the old value back.
  Future<bool> save(TimePreferences next) async {
    if (next == state) return true;
    final previous = state;
    emit(next);
    try {
      adopt(
        (await _account.updateMyProfile(timePreferences: next)).timePreferences,
      );
      return true;
    } catch (_) {
      emit(previous);
      return false;
    }
  }
}
