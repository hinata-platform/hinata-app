import '../../../core/blocs/paged_cubit.dart';
import '../../../core/models/moderation_case_models.dart';
import '../../../core/repositories/moderation_repository.dart';

/// One list of the moderation page (HIN-174), fifty cases a page, in the
/// server's order: urgent first and then the oldest for the open ones.
class ModerationCasesCubit extends PagedCubit<CaseSummary> {
  ModerationCasesCubit(ModerationRepository moderation, this.view)
    : super(
        (page, size) => moderation.cases(view, page, size),
        keyOf: (summary) => summary.id,
      );

  final CaseView view;
}
