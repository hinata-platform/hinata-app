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
  FakeTimePolicyCubit(TimePolicySnapshot policy, TimeRepository time)
    : super(time) {
    if (policy != TimePolicySnapshot.none) emit(policy);
  }

  @override
  Future<void> ensureLoaded() async {}
}
