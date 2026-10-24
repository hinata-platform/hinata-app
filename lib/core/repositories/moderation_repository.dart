import '../api/api_client.dart';
import '../models/moderation_models.dart';

/// Reporting from the app, the reader's own reports, and the moderation's
/// notice to the person concerned (HIN-173).
class ModerationRepository {
  ModerationRepository(this._api);

  final ApiClient _api;

  /// Reports [target] for [category]. With [alsoBlock] the author is blocked
  /// in the same step. Nobody is told who reported.
  Future<void> report(
    TargetRef target,
    ReportCategory category, {
    String? explanation,
    bool alsoBlock = false,
  }) => _api.post(
    '/api/v1/me/moderation/reports',
    body: {
      'target': target.toJson(),
      'category': category.wire,
      'explanation': ?explanation,
      if (alsoBlock) 'alsoBlock': true,
    },
  );

  /// The comments the reader reported in the last six months that are still
  /// there, at most 500: they stay folded for the reader.
  Future<Set<String>> reportedIds() async =>
      ((await _api.get('/api/v1/me/moderation/reported-ids')) as List<dynamic>)
          .cast<String>()
          .toSet();

  /// The notice about the reader's own content in case [caseId]. Answers 404
  /// once it is gone, or when it is not the reader's.
  Future<Statement> notice(String caseId) async => Statement.fromJson(
    await _api.get(
          '/api/v1/me/moderation/notices/${Uri.encodeComponent(caseId)}',
        )
        as Map<String, dynamic>,
  );

  /// Appeals the decision in case [caseId] and answers the notice as it reads
  /// now. A second appeal, or one after the deadline, answers 409.
  Future<Statement> appeal(
    String caseId,
    String text,
  ) async => Statement.fromJson(
    await _api.post(
          '/api/v1/me/moderation/notices/${Uri.encodeComponent(caseId)}/appeal',
          body: {'text': text},
        )
        as Map<String, dynamic>,
  );

  /// A page of the server, such as the house rules a decision points to.
  Uri page(String path) => _api.resolve(path);
}
