import '../api/api_client.dart';
import '../blocs/paged_cubit.dart';
import '../models/absence_models.dart';
import '../util/dates.dart';

/// Absence management 2.0 (HIN-116): the catalogue of absence types, what
/// people are entitled to, the journal their balances are the sum of, and the
/// two employment dates the arithmetic reads.
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

  Future<AbsenceType> createType(Map<String, dynamic> body) async =>
      AbsenceType.fromJson(
        await _api.post('/api/v1/time-off/types', body: body)
            as Map<String, dynamic>,
      );

  Future<AbsenceType> updateType(String id, Map<String, dynamic> body) async =>
      AbsenceType.fromJson(
        await _api.patch('/api/v1/time-off/types/${_id(id)}', body: body)
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
