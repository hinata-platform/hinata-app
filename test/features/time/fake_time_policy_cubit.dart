import 'package:hinata/core/blocs/time_policy_cubit.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';

/// A policy cubit that already knows the answer.
///
/// The real one reads it from the server; here the test states it, so a case
/// about a frozen day or a required field is one line rather than a fake round
/// trip. Shared because three screens now read the policy, and three copies of
/// the same four lines is how they start to disagree.
class FakeTimePolicyCubit extends TimePolicyCubit {
  FakeTimePolicyCubit(
    TimePolicySnapshot policy,
    TimeRepository time, {
    this.onLoad,
  }) : super(time) {
    if (policy != TimePolicySnapshot.none) emit(policy);
  }

  /// What the *first* read finds, for a screen that opens cold.
  ///
  /// The default is the useful lie — a policy handed in at construction, so a
  /// case about a frozen day is one line. It hides one thing, and it hid it for
  /// a whole stage: whether the screen asks at all. A screen that never calls
  /// [ensureLoaded] draws the rules correctly in every test here and nothing at
  /// all when it is opened from a link.
  final TimePolicySnapshot? onLoad;

  /// How many times a screen has asked for the rules.
  int loads = 0;

  /// What a re-read finds, when a test is about the rules having changed
  /// under a session that had already read them.
  TimePolicySnapshot? onRefresh;

  int refreshes = 0;

  @override
  Future<void> ensureLoaded() async {
    loads++;
    final fresh = onLoad;
    if (fresh != null) emit(fresh);
  }

  @override
  Future<void> refresh() async {
    refreshes++;
    final fresh = onRefresh;
    if (fresh != null) emit(fresh);
  }
}
