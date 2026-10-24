import '../../../core/blocs/paged_cubit.dart';
import '../../../core/models/moderation_case_models.dart';
import '../../../core/repositories/moderation_repository.dart';

/// The accounts moderation suspended, newest first (HIN-174).
class SuspensionsCubit extends PagedCubit<SuspendedAccount> {
  SuspensionsCubit(ModerationRepository moderation)
    : super(moderation.suspensions, keyOf: (account) => account.person.id);
}
