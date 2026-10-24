import 'dart:typed_data';

import '../api/api_client.dart';
import '../blocs/paged_cubit.dart';
import '../models/moderation_case_models.dart';
import '../models/moderation_models.dart';

/// Reporting from the app, the reader's own reports, and the moderation's
/// notice to the person concerned (HIN-173); for moderators, the cases and
/// every step on them (HIN-174).
class ModerationRepository {
  ModerationRepository(this._api, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final ApiClient _api;
  final DateTime Function() _now;

  /// How long one read of the house rules serves the decisions that follow.
  static const rulesHeldFor = Duration(minutes: 10);

  /// The last rules read, for the server and language they were read in.
  ({String server, String locale, DateTime at, ModerationRules rules})? _rules;

  /// Reports [target] for [category]. With [alsoBlock] the author is blocked
  /// in the same step; [location] is where something without a menu of its
  /// own is ([TargetRef.elsewhere]). Nobody is told who reported.
  Future<void> report(
    TargetRef target,
    ReportCategory category, {
    String? explanation,
    bool alsoBlock = false,
    String? location,
  }) => _api.post(
    '/api/v1/me/moderation/reports',
    body: {
      'target': target.toJson(),
      'category': category.wire,
      'explanation': ?explanation,
      'location': ?location,
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

  // --- moderators (HIN-174) -------------------------------------------------

  static const _base = '/api/v1/moderation';

  /// The numbers on the moderation page, without what the reader wrote.
  Future<ModerationSummary> summary() async => ModerationSummary.fromJson(
    await _api.get('$_base/summary') as Map<String, dynamic>,
  );

  /// One page of [view]: the open ones urgent first and then the oldest, the
  /// appealed ones oldest first, the done ones newest first.
  Future<PageResult<CaseSummary>> cases(
    CaseView view,
    int page,
    int size,
  ) async => _page(
    await _api.get(
          '$_base/cases',
          query: {'view': view.wire, 'page': page, 'size': size},
        )
        as Map<String, dynamic>,
    CaseSummary.fromJson,
  );

  /// Case [id] opened. 404 for whoever wrote its content.
  Future<CaseDetail> detail(String id) async =>
      CaseDetail.fromJson(await _api.get(_case(id)) as Map<String, dynamic>);

  /// Further reports of case [id], in the order they came.
  Future<PageResult<CaseReport>> reports(String id, int page, int size) async =>
      _page(
        await _api.get(
              '${_case(id)}/reports',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>,
        CaseReport.fromJson,
      );

  /// Takes case [id] at [rev]; with [takeOver] also from somebody whose claim
  /// is older than two hours. 409 when it moved meanwhile.
  Future<CaseSummary> claim(String id, int rev, {bool takeOver = false}) =>
      _summary('${_case(id)}/claim', {'rev': rev, 'takeOver': takeOver});

  /// Gives case [id] back.
  Future<CaseSummary> release(String id, int rev) =>
      _summary('${_case(id)}/release', {'rev': rev, 'takeOver': false});

  /// Uncovers who filed report [reportId], with a [reason] that goes into the
  /// history. Refused for a case about the safety of children.
  Future<CaseReport> revealReporter(
    String id,
    String reportId,
    String reason,
  ) async => CaseReport.fromJson(
    await _api.post(
          '${_case(id)}/reports/${Uri.encodeComponent(reportId)}/reveal',
          body: {'reason': reason},
        )
        as Map<String, dynamic>,
  );

  /// Asks to open withheld content, or, as the second person, opens it.
  Future<CaseDetail> revealEvidence(String id, String reason) async =>
      CaseDetail.fromJson(
        await _api.post(
              '${_case(id)}/evidence/reveal',
              body: {'reason': reason},
            )
            as Map<String, dynamic>,
      );

  /// File [index] of the case's evidence, held in memory only: the server
  /// sends it uncached, and every look is in its audit log.
  Future<Uint8List> evidenceFile(String id, int index) =>
      _api.getFileBytes('${_case(id)}/evidence/$index');

  /// Decides case [id] as [draft] says.
  Future<CaseSummary> decide(String id, DecisionDraft draft) =>
      _summary('${_case(id)}/decision', draft.toJson());

  /// The statement [draft] would send, worded as the person will read it.
  Future<Statement> statementPreview(String id, DecisionDraft draft) async =>
      Statement.fromJson(
        await _api.post('${_case(id)}/statement-preview', body: draft.toJson())
            as Map<String, dynamic>,
      );

  /// Confirms a suspension of a person with a role, as the second person.
  Future<CaseSummary> confirm(String id, int rev) =>
      _summary('${_case(id)}/decision/confirm', {'rev': rev});

  /// Turns down a decision waiting for a second person, with a reason.
  Future<CaseSummary> reject(String id, int rev, String note) =>
      _summary('${_case(id)}/decision/reject', {'rev': rev, 'note': note});

  /// Undoes the removal of a decided case, with a reason.
  Future<CaseSummary> restore(String id, int rev, String note) =>
      _summary('${_case(id)}/restore', {'rev': rev, 'note': note});

  /// Lifts the suspension a case decided, with a reason.
  Future<CaseSummary> liftSuspension(String id, int rev, String note) =>
      _summary('${_case(id)}/suspension/lift', {'rev': rev, 'note': note});

  /// Enters an appeal that came by a reply to the mail on [receivedAt].
  Future<CaseSummary> recordAppeal(
    String id,
    String text,
    DateTime receivedAt,
  ) => _summary('${_case(id)}/appeal', {
    'text': text,
    'receivedAt': receivedAt.toUtc().toIso8601String(),
  });

  /// Decides the appeal on case [id], with a reason.
  Future<CaseSummary> decideAppeal(
    String id,
    int rev,
    AppealResult result,
    String note,
  ) => _summary('${_case(id)}/appeal-decision', {
    'rev': rev,
    'result': result.wire,
    'note': note,
  });

  /// Holds a decided case beyond its time: until [until], or without an end.
  Future<CaseSummary> legalHold(
    String id, {
    DateTime? until,
    bool indefinite = false,
    required String reason,
  }) => _summary('${_case(id)}/legal-hold', {
    'until': ?until?.toUtc().toIso8601String(),
    'indefinite': indefinite,
    'reason': reason,
  });

  /// The house rules a decision can rest on, in the reader's language.
  ///
  /// They are the same for every decision on an instance and change rarely,
  /// so one read serves for [rulesHeldFor]: a moderator deciding case after
  /// case asks once.
  Future<ModerationRules> rules() async {
    final server = _api.baseUrl;
    final locale = _api.localeCode;
    final held = _rules;
    if (held != null &&
        held.server == server &&
        held.locale == locale &&
        _now().difference(held.at) < rulesHeldFor) {
      return held.rules;
    }
    final rules = ModerationRules.fromJson(
      await _api.get('$_base/rules') as Map<String, dynamic>,
    );
    _rules = (server: server, locale: locale, at: _now(), rules: rules);
    return rules;
  }

  /// The accounts moderation suspended, newest first.
  Future<PageResult<SuspendedAccount>> suspensions(int page, int size) async =>
      _page(
        await _api.get(
              '$_base/suspensions',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>,
        SuspendedAccount.fromJson,
      );

  /// Opens a case on moderation's own initiative and answers its id.
  Future<String> openOwn(
    TargetRef target,
    ReportCategory category,
    String facts,
  ) async =>
      ((await _api.post(
                '$_base/cases',
                body: {
                  'target': target.toJson(),
                  'category': category.wire,
                  'facts': facts,
                },
              )
              as Map<String, dynamic>)['id']
          as String?) ??
      '';

  static String _case(String id) => '$_base/cases/${Uri.encodeComponent(id)}';

  Future<CaseSummary> _summary(String path, Map<String, dynamic> body) async =>
      CaseSummary.fromJson(
        await _api.post(path, body: body) as Map<String, dynamic>,
      );

  static PageResult<T> _page<T>(
    Map<String, dynamic> data,
    T Function(Map<String, dynamic>) read,
  ) => (
    items: [
      for (final item in (data['content'] as List<dynamic>?) ?? const [])
        read(item as Map<String, dynamic>),
    ],
    total: (data['totalElements'] as num?)?.toInt() ?? 0,
  );
}
