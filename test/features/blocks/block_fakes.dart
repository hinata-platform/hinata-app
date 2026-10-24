import 'package:hinata/features/blocks/hidden_content_cubit.dart';

import '../../support/recording_fake.dart';

/// A [HiddenContentCubit] that already holds [blocked], over [account] so a
/// test can answer and record what blocking and lifting send.
Future<HiddenContentCubit> hiddenContent(
  FakeAccountRepository account, {
  Set<String> blocked = const {},
}) async {
  account.answer<Set<String>>(#blockedIds, blocked);
  final moderation = FakeModerationRepository()
    ..answer<Set<String>>(#reportedIds, const {});
  final cubit = HiddenContentCubit(account, moderation, enabled: () => true);
  await cubit.load();
  account.calls.clear();
  return cubit;
}
