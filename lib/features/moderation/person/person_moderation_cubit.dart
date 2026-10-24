import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/moderation_case_models.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/repositories/moderation_repository.dart';

/// Moderation from a person's profile (HIN-174): a case of moderation's own
/// to suspend them, and lifting a suspension. The state is why the last step
/// was refused, in the server's words; null while nothing was.
class PersonModerationCubit extends Cubit<String?> {
  PersonModerationCubit(this._moderation) : super(null);

  final ModerationRepository _moderation;

  /// Opens a case on [personId] for [category] with what was found, and reads
  /// it for its decision; null when refused.
  Future<CaseDetail?> openCase(
    String personId,
    ReportCategory category,
    String facts,
  ) async {
    try {
      final id = await _moderation.openOwn(
        TargetRef(ContentKind.person, personId),
        category,
        facts,
      );
      return await _moderation.detail(id);
    } on ApiFailure catch (failure) {
      emit(failure.message);
      return null;
    }
  }

  /// Lifts the suspension case [caseId] decided, with a reason, at the
  /// revision it stands at now.
  Future<bool> lift(String caseId, String note) async {
    try {
      final detail = await _moderation.detail(caseId);
      await _moderation.liftSuspension(caseId, detail.summary.rev, note);
      return true;
    } on ApiFailure catch (failure) {
      emit(failure.message);
      return false;
    }
  }

  /// The refusal was said.
  void seen() => emit(null);
}
