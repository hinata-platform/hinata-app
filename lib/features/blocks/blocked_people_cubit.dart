import '../../core/blocs/paged_cubit.dart';
import '../../core/models/account_models.dart';
import '../../core/repositories/account_repository.dart';

/// The people the reader blocks, newest first, 25 to a page (HIN-168).
///
/// Lifting a block goes through `HiddenContentCubit`, which the rest of the
/// app folds by; this list only drops the row once that landed.
class BlockedPeopleCubit extends PagedCubit<BlockedPerson> {
  BlockedPeopleCubit(AccountRepository account)
    : super(
        (page, size) => account.blocksPage(page: page, size: size),
        pageSize: 25,
        keyOf: (person) => person.id,
      );
}
