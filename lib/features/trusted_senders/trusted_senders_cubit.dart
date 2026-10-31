import '../../core/blocs/paged_cubit.dart';
import '../../core/models/account_models.dart';
import '../../core/repositories/account_repository.dart';

/// The mail senders whose external images the reader always loads, newest
/// first, 25 to a page (HIN-181).
class TrustedSendersCubit extends PagedCubit<TrustedSender> {
  TrustedSendersCubit(AccountRepository account)
    : _account = account,
      super(
        (page, size) => account.trustedSendersPage(page: page, size: size),
        pageSize: 25,
        keyOf: (sender) => sender.domain,
      );

  final AccountRepository _account;

  /// Stops trusting [domain]; the row goes once the server agreed.
  Future<void> distrust(String domain) async {
    await _account.distrustSender(domain);
    removeItem(domain);
  }
}
