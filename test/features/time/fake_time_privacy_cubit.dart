import 'package:hinata/core/blocs/time_privacy_cubit.dart';
import 'package:hinata/core/models/time_privacy_models.dart';

/// A [TimePrivacyCubit] that answers from memory.
///
/// Without a [privacy] it holds nothing, and a cubit holding nothing never
/// offers the first-use notice — so a screen test that does not care about the
/// notice sees no sheet pop over what it is testing. A test that does care hands
/// one in, and [onLoad] lets it arrive the way a cold read would.
class FakeTimePrivacyCubit extends TimePrivacyCubit {
  FakeTimePrivacyCubit(super.time, {TimePrivacy? privacy, this.onLoad}) {
    if (privacy != null) emit(privacy);
  }

  /// Emitted on the first [ensureLoaded], as a cold read would.
  final TimePrivacy? onLoad;

  int acknowledgements = 0;

  @override
  Future<bool> ensureLoaded() async {
    final fresh = onLoad;
    if (fresh != null && state == null) emit(fresh);
    return state != null;
  }

  @override
  Future<bool> refresh() async => state != null;

  @override
  Future<bool> acknowledge() async {
    acknowledgements++;
    final current = state;
    if (current != null) {
      emit(
        TimePrivacy(
          notice: current.notice,
          customNotice: current.customNotice,
          acknowledgedAt: DateTime.utc(2026, 9, 10),
          visibility: current.visibility,
        ),
      );
    }
    return true;
  }
}
