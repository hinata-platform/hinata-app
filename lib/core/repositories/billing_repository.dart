import 'dart:typed_data';

import '../api/api_client.dart';
import '../blocs/paged_cubit.dart';
import '../models/billing_models.dart';
import '../util/dates.dart';

/// `/api/v1/billing` (HIN-96): what the reader may do, rates, the money
/// reports and invoices.
///
/// Every route answers 404 `error.feature.disabled` while billing is off, and
/// 403 for a member who leads nothing — callers ask only when the `billing`
/// flag is on.
class BillingRepository {
  BillingRepository(this._api);

  final ApiClient _api;

  Future<BillingAccess> access() async => BillingAccess.fromJson(
    await _api.get('/api/v1/billing/access') as Map<String, dynamic>,
  );

  // --- rates -----------------------------------------------------------------

  Future<PageResult<BillingRate>> rates({
    RateKind? kind,
    RateScope? scope,
    String? scopeId,
    String? projectId,
    RateStatus? status,
    int page = 0,
    int size = 25,
  }) async {
    final data =
        await _api.get(
              '/api/v1/billing/rates',
              query: {
                'kind': ?kind?.wire,
                'scope': ?scope?.wire,
                'scopeId': ?scopeId,
                'projectId': ?projectId,
                'status': ?status?.wire,
                'page': page,
                'size': size,
              },
            )
            as Map<String, dynamic>;
    return (
      items: [
        for (final row in data['content'] as List? ?? const [])
          BillingRate.fromJson(row as Map<String, dynamic>),
      ],
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  /// Every rate of one target, newest start first.
  Future<List<BillingRate>> timeline(RateTarget target) async {
    final data = await _api.get(
      '/api/v1/billing/rates/timeline',
      query: {
        'kind': target.kind.wire,
        'scope': target.scope.wire,
        'scopeId': ?target.scopeId,
        'secondaryId': ?target.secondaryId,
      },
    );
    return [
      for (final row in data as List? ?? const [])
        BillingRate.fromJson(row as Map<String, dynamic>),
    ];
  }

  /// A rate from [from] on. An open-ended one closes the running one the day
  /// before — "change from date".
  Future<BillingRate> createRate(
    RateTarget target, {
    required int amountCents,
    required DateTime from,
    DateTime? to,
  }) async => BillingRate.fromJson(
    await _api.post(
          '/api/v1/billing/rates',
          body: {
            'kind': target.kind.wire,
            'scope': target.scope.wire,
            'scopeId': ?target.scopeId,
            'secondaryId': ?target.secondaryId,
            'amountCents': amountCents,
            'validFrom': formatDateOnly(from),
            if (to != null) 'validTo': formatDateOnly(to),
          },
        )
        as Map<String, dynamic>,
  );

  Future<BillingRate> updateRate(
    String id, {
    int? amountCents,
    DateTime? from,
    DateTime? to,
    bool openEnded = false,
  }) async => BillingRate.fromJson(
    await _api.patch(
          '/api/v1/billing/rates/$id',
          body: {
            'amountCents': ?amountCents,
            if (from != null) 'validFrom': formatDateOnly(from),
            if (to != null) 'validTo': formatDateOnly(to),
            if (openEnded) 'openEnded': true,
          },
        )
        as Map<String, dynamic>,
  );

  Future<void> deleteRate(String id) =>
      _api.delete('/api/v1/billing/rates/$id');

  // --- reports ---------------------------------------------------------------

  Future<({BillingReportHead head, PageResult<BillingRow> rows})> report(
    BillingReportKind kind, {
    required DateTime from,
    required DateTime to,
    required BillingGroupBy groupBy,
    List<String> projectIds = const [],
    int page = 0,
    int size = 25,
  }) async {
    final data =
        await _api.get(
              '/api/v1/billing/reports/${kind.wire}',
              query: {
                'from': formatDateOnly(from),
                'to': formatDateOnly(to),
                'groupBy': groupBy.wire,
                if (projectIds.isNotEmpty) 'projectIds': projectIds,
                'page': page,
                'size': size,
              },
            )
            as Map<String, dynamic>;
    final groups = data['groups'] as Map<String, dynamic>? ?? const {};
    return (
      head: BillingReportHead(
        kind: kind,
        groupBy: BillingGroupBy.parse(data['groupBy'] as String?),
        currency: data['currency'] as String? ?? 'EUR',
        totals: BillingRow.fromJson(
          data['totals'] as Map<String, dynamic>? ?? const {},
        ),
        costs: data['costs'] as bool? ?? false,
      ),
      rows: (
        items: [
          for (final row in groups['content'] as List? ?? const [])
            BillingRow.fromJson(row as Map<String, dynamic>),
        ],
        total: (groups['totalElements'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  // --- invoices --------------------------------------------------------------

  Future<PageResult<InvoiceSummary>> invoices({
    InvoiceStatus? status,
    String? projectId,
    int page = 0,
    int size = 20,
  }) async {
    final data =
        await _api.get(
              '/api/v1/billing/invoices',
              query: {
                'status': ?status?.wire,
                'projectId': ?projectId,
                'page': page,
                'size': size,
              },
            )
            as Map<String, dynamic>;
    return (
      items: [
        for (final row in data['content'] as List? ?? const [])
          InvoiceSummary.fromJson(row as Map<String, dynamic>),
      ],
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  Future<InvoiceDetail> invoice(String id) async => InvoiceDetail.fromJson(
    await _api.get('/api/v1/billing/invoices/$id') as Map<String, dynamic>,
  );

  Future<PageResult<InvoiceLine>> lines(
    String id, {
    int page = 0,
    int size = 50,
  }) async {
    final data =
        await _api.get(
              '/api/v1/billing/invoices/$id/lines',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: [
        for (final row in data['content'] as List? ?? const [])
          InvoiceLine.fromJson(row as Map<String, dynamic>),
      ],
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  Future<InvoiceDetail> createDraft(InvoiceDraftRequest request) async =>
      InvoiceDetail.fromJson(
        await _api.post('/api/v1/billing/invoices', body: request.toJson())
            as Map<String, dynamic>,
      );

  Future<InvoiceDetail> updateDraft(
    String id, {
    InvoiceRecipient? recipient,
    String? notes,
    int? taxBasisPoints,
    List<String> removeLineIds = const [],
  }) async => InvoiceDetail.fromJson(
    await _api.patch(
          '/api/v1/billing/invoices/$id',
          body: {
            if (recipient != null) 'recipient': recipient.toJson(),
            'notes': ?notes,
            'taxBasisPoints': ?taxBasisPoints,
            if (removeLineIds.isNotEmpty) 'removeLineIds': removeLineIds,
          },
        )
        as Map<String, dynamic>,
  );

  Future<InvoiceDetail> refresh(String id) async => InvoiceDetail.fromJson(
    await _api.post('/api/v1/billing/invoices/$id/refresh')
        as Map<String, dynamic>,
  );

  Future<void> deleteDraft(String id) =>
      _api.delete('/api/v1/billing/invoices/$id');

  Future<InvoiceDetail> issue(String id) async => InvoiceDetail.fromJson(
    await _api.post('/api/v1/billing/invoices/$id/issue')
        as Map<String, dynamic>,
  );

  Future<InvoiceDetail> creditNote(String id, {String? reason}) async =>
      InvoiceDetail.fromJson(
        await _api.post(
              '/api/v1/billing/invoices/$id/credit-note',
              body: {'reason': ?reason},
            )
            as Map<String, dynamic>,
      );

  /// The record as `pdf`, `docx` or `xlsx`, in its own language.
  Future<Uint8List> export(String id, String format) => _api.getFileBytes(
    '/api/v1/billing/invoices/$id/export.$format',
    receiveTimeout: const Duration(minutes: 2),
  );

  /// The same file written to [path], for the platforms that save to disk.
  Future<void> exportTo(String id, String format, String path) async {
    await _api.downloadTo(
      '/api/v1/billing/invoices/$id/export.$format',
      path,
      receiveTimeout: const Duration(minutes: 2),
    );
  }
}
