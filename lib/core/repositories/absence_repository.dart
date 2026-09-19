import '../api/api_client.dart';
import '../blocs/paged_cubit.dart';
import '../models/absence_models.dart';
import '../models/absence_request_models.dart';
import '../util/dates.dart';

/// Absence management 2.0: the catalogue of absence types, what people are
/// entitled to, the journal their balances are the sum of, the two employment
/// dates the arithmetic reads (HIN-116), and asking for time off (HIN-117).
///
/// Behind the server's `absence_management` flag — its own switch, nested under
/// `advanced_time_tracking` — so with either off every route here answers 404
/// `error.feature.disabled` and [FeatureGate] sends the app to re-read `/meta`.
///
/// Days are thousandths of a working day on the wire, exactly as the server
/// stores them; nothing here converts one into a decimal.
class AbsenceRepository {
  AbsenceRepository(this._api);

  final ApiClient _api;

  static String _id(String id) => Uri.encodeComponent(id);

  // --- who is asking ---------------------------------------------------------

  /// Whether the reader keeps absences for everybody, so a screen knows
  /// whether to offer a way into the keeper's pages.
  ///
  /// Asked of the server rather than derived from the admin role: an operator
  /// names the circle that sees sick days as sick days, and a named keeper who
  /// is not an administrator would otherwise never find the page.
  Future<bool> isKeeper() async {
    final data =
        await _api.get('/api/v1/time-off/access') as Map<String, dynamic>;
    return data['keeper'] as bool? ?? false;
  }

  // --- the catalogue -------------------------------------------------------

  /// The types on offer. [includeInactive] is honoured for a keeper and
  /// ignored for everybody else, which the server decides rather than this.
  Future<List<AbsenceType>> types({bool includeInactive = false}) async {
    final data =
        await _api.get(
              '/api/v1/time-off/types',
              query: {if (includeInactive) 'includeInactive': true},
            )
            as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(AbsenceType.fromJson)
        .toList(growable: false);
  }

  Future<AbsenceType> createType(AbsenceTypeDraft draft) async =>
      AbsenceType.fromJson(
        await _api.post('/api/v1/time-off/types', body: draft.toJson())
            as Map<String, dynamic>,
      );

  Future<AbsenceType> updateType(String id, AbsenceTypeDraft draft) async =>
      AbsenceType.fromJson(
        await _api.patch(
              '/api/v1/time-off/types/${_id(id)}',
              body: draft.toJson(),
            )
            as Map<String, dynamic>,
      );

  Future<void> deleteType(String id) =>
      _api.delete('/api/v1/time-off/types/${_id(id)}');

  // --- balances --------------------------------------------------------------

  /// One person's standing for a leave year. Without [userId] it is the
  /// reader's own, which is the only one most people may ask for.
  Future<AbsenceBalances> balances({String? userId, int? year}) async =>
      AbsenceBalances.fromJson(
        await _api.get(
              '/api/v1/time-off/balances',
              query: {
                if (userId != null && userId.isNotEmpty) 'userId': userId,
                'year': ?year,
              },
            )
            as Map<String, dynamic>,
      );

  /// One page of the journal behind a balance, oldest first.
  Future<PageResult<AbsenceLedgerEntry>> ledger({
    required String userId,
    required String typeId,
    required int year,
    int page = 0,
    int size = 50,
  }) async {
    final data =
        await _api.get(
              '/api/v1/time-off/balances/${_id(userId)}/${_id(typeId)}/$year/ledger',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: [
        for (final item in (data['content'] as List<dynamic>?) ?? const [])
          AbsenceLedgerEntry.fromJson(item as Map<String, dynamic>),
      ],
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  /// One page of the directory beside where each person stands for [typeId] in
  /// [year] — the list a keeper grants from. A keeper's to ask.
  Future<PageResult<AbsenceStanding>> overview({
    required String typeId,
    required int year,
    String query = '',
    int page = 0,
    int size = 25,
  }) async {
    final data =
        await _api.get(
              '/api/v1/time-off/entitlements/overview',
              query: {
                'typeId': typeId,
                'year': year,
                'q': query,
                'page': page,
                'size': size,
              },
            )
            as Map<String, dynamic>;
    return (
      items: [
        for (final item in (data['content'] as List<dynamic>?) ?? const [])
          AbsenceStanding.fromJson(item as Map<String, dynamic>),
      ],
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  // --- granting ----------------------------------------------------------------

  Future<AbsenceEntitlement> grant({
    required String userId,
    required String typeId,
    required int year,
    int? allowanceMilliDays,
    String? note,
  }) async => AbsenceEntitlement.fromJson(
    await _api.post(
          '/api/v1/time-off/entitlements',
          body: {
            'userId': userId,
            'typeId': typeId,
            'year': year,
            'allowanceMilliDays': ?allowanceMilliDays,
            'note': ?note,
          },
        )
        as Map<String, dynamic>,
  );

  /// What a bulk grant would do. Always asked before granting, never a side
  /// effect of it: a keeper about to give forty people a year should see the
  /// part-year cases first.
  Future<List<AbsenceGrantPreview>> previewGrant({
    required String typeId,
    required int year,
    required List<String> userIds,
    int? allowanceMilliDays,
  }) async {
    final data =
        await _api.post(
              '/api/v1/time-off/entitlements/preview',
              body: {
                'typeId': typeId,
                'year': year,
                'userIds': userIds,
                'allowanceMilliDays': ?allowanceMilliDays,
              },
            )
            as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(AbsenceGrantPreview.fromJson)
        .toList(growable: false);
  }

  Future<List<AbsenceEntitlement>> grantMany({
    required String typeId,
    required int year,
    required List<String> userIds,
    int? allowanceMilliDays,
  }) async {
    final data =
        await _api.post(
              '/api/v1/time-off/entitlements/bulk',
              body: {
                'typeId': typeId,
                'year': year,
                'userIds': userIds,
                'allowanceMilliDays': ?allowanceMilliDays,
              },
            )
            as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(AbsenceEntitlement.fromJson)
        .toList(growable: false);
  }

  /// A keeper's correction. The reason is required by the server and by the
  /// form: a balance that moved for no stated cause is the one somebody will
  /// be asked about in a year.
  Future<AbsenceLedgerEntry> adjust({
    required String userId,
    required String typeId,
    required int year,
    required int milliDays,
    required String reason,
    DateTime? effectiveOn,
  }) async => AbsenceLedgerEntry.fromJson(
    await _api.post(
          '/api/v1/time-off/ledger',
          body: {
            'userId': userId,
            'typeId': typeId,
            'year': year,
            'milliDays': milliDays,
            'reason': reason,
            if (effectiveOn != null) 'effectiveOn': formatDateOnly(effectiveOn),
          },
        )
        as Map<String, dynamic>,
  );

  // --- requests -------------------------------------------------------------------

  /// The reader's own requests, newest first. There is no parameter for
  /// somebody else's: whose absences a person may look at is decided in the
  /// calendar, and a list of requests is not a second way in.
  Future<PageResult<AbsenceRequest>> myRequests({
    AbsenceRequestStatus? status,
    int? year,
    int page = 0,
    int size = 25,
  }) => _requests('/api/v1/time-off/requests', {
    if (status != null) 'status': status.wire,
    'year': ?year,
    'page': page,
    'size': size,
  });

  /// What the reader has to decide. Empty for somebody who decides nothing,
  /// which is an honest answer rather than a hidden feature.
  Future<PageResult<AbsenceRequest>> inbox({
    AbsenceRequestStatus? status,
    int page = 0,
    int size = 25,
  }) => _requests('/api/v1/time-off/requests/inbox', {
    if (status != null) 'status': status.wire,
    'page': page,
    'size': size,
  });

  Future<PageResult<AbsenceRequest>> _requests(
    String path,
    Map<String, dynamic> query,
  ) async {
    final data = await _api.get(path, query: query) as Map<String, dynamic>;
    return (
      items: [
        for (final item in (data['content'] as List<dynamic>?) ?? const [])
          AbsenceRequest.fromJson(item as Map<String, dynamic>),
      ],
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  /// One request, for anybody it concerns. Everybody else gets a 404 rather
  /// than a 403, so probing ids says nothing.
  Future<AbsenceRequest> request(String id) async => AbsenceRequest.fromJson(
    await _api.get('/api/v1/time-off/requests/${_id(id)}')
        as Map<String, dynamic>,
  );

  /// What a draft would cost. The same arithmetic the submission freezes, so
  /// the number in the form is the number on the request — asked of the server
  /// rather than computed here, because a second implementation of a working
  /// week is a second answer waiting to disagree.
  Future<AbsencePreview> preview(AbsenceRequestDraft draft) async =>
      AbsencePreview.fromJson(
        await _api.post(
              '/api/v1/time-off/requests/preview',
              body: draft.toJson(),
            )
            as Map<String, dynamic>,
      );

  Future<AbsenceRequest> submit(AbsenceRequestDraft draft) async =>
      AbsenceRequest.fromJson(
        await _api.post('/api/v1/time-off/requests', body: draft.toJson())
            as Map<String, dynamic>,
      );

  /// Changes a request that is still waiting. The server works the days out
  /// again and asks again who decides; once somebody has decided, it is 409.
  Future<AbsenceRequest> edit(String id, AbsenceRequestDraft draft) async =>
      AbsenceRequest.fromJson(
        await _api.patch(
              '/api/v1/time-off/requests/${_id(id)}',
              body: draft.toJson(),
            )
            as Map<String, dynamic>,
      );

  Future<AbsenceRequest> approve(String id, {String? note}) =>
      _decide(id, 'approve', note);

  /// Rejects, and the reason is required — by the server, and by the form that
  /// sends it (§ 7 Abs. 1 BUrlG).
  Future<AbsenceRequest> reject(String id, {required String note}) =>
      _decide(id, 'reject', note);

  Future<AbsenceRequest> withdraw(String id) => _decide(id, 'withdraw', null);

  Future<AbsenceRequest> cancel(String id, {String? note}) =>
      _decide(id, 'cancel', note);

  Future<AbsenceRequest> _decide(String id, String step, String? note) async =>
      AbsenceRequest.fromJson(
        await _api.post(
              '/api/v1/time-off/requests/${_id(id)}/$step',
              body: {'note': ?note},
            )
            as Map<String, dynamic>,
      );

  /// Who else is away across a span — names and spans, never the kind of
  /// absence. For whoever decides; a person who decides nothing reads nothing.
  Future<List<AbsenceClash>> conflicts({
    required DateTime from,
    required DateTime to,
  }) async {
    final data =
        await _api.get(
              '/api/v1/time-off/requests/conflicts',
              query: {'from': formatDateOnly(from), 'to': formatDateOnly(to)},
            )
            as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(AbsenceClash.fromJson)
        .toList(growable: false);
  }

  /// Reports sickness. One step, effective at once, no approver and nothing
  /// required but the date — § 5 EFZG knows a notification, not a permission.
  ///
  /// [typeId] names a sick type where an operator offers more than one;
  /// left out, the server takes the built-in.
  Future<SickReport> reportSick({
    required DateTime from,
    DateTime? to,
    bool halfDay = false,
    String? typeId,
  }) async => SickReport.fromJson(
    await _api.post(
          '/api/v1/time-off/sick',
          body: {
            'from': formatDateOnly(from),
            if (to != null) 'to': formatDateOnly(to),
            if (halfDay) 'halfDay': true,
            if (typeId != null && typeId.isNotEmpty) 'typeId': typeId,
          },
        )
        as Map<String, dynamic>,
  );

  // --- employment dates ----------------------------------------------------------

  Future<EmploymentDates> employment(String userId) async =>
      EmploymentDates.fromJson(
        await _api.get('/api/v1/time-off/employment/${_id(userId)}')
            as Map<String, dynamic>,
      );

  Future<EmploymentDates> saveEmployment({
    required String userId,
    DateTime? hiredOn,
    DateTime? leftOn,
    String? note,
  }) async => EmploymentDates.fromJson(
    await _api.put(
          '/api/v1/time-off/employment/${_id(userId)}',
          body: {
            if (hiredOn != null) 'hiredOn': formatDateOnly(hiredOn),
            if (leftOn != null) 'leftOn': formatDateOnly(leftOn),
            'note': ?note,
          },
        )
        as Map<String, dynamic>,
  );
}
