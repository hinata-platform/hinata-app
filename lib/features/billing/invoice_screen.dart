import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:printing/printing.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/billing_models.dart';
import '../../core/repositories/billing_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../../core/util/file_download.dart';
import '../../core/util/share_origin.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart' show GhostButton;
import '../../core/widgets/soft_card.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart';
import 'billing_format.dart';
import 'invoice_draft_sheet.dart' show InvoiceRecipientFields;
import 'invoice_widgets.dart';
import 'invoices_screen.dart' show invoicesRoute;

/// One invoice or credit note (HIN-96): what it says, its lines, and what can
/// be done with it — a draft is edited, refreshed, issued or thrown away; an
/// issued invoice is exported, printed or reversed with a credit note.
///
/// Issuing is the one step that cannot be taken back, so it asks first and
/// says what it does: a number from the gapless sequence, a frozen record, and
/// entries nobody can change until a credit note releases them.
class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({super.key, required this.id});

  final String id;

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

enum _Action {
  edit,
  refresh,
  issue,
  delete,
  creditNote,
  pdf,
  docx,
  xlsx,
  print,
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  late final BillingRepository _billing = context.read<BillingRepository>();
  InvoiceDetail? _invoice;
  String? _errorKey;
  bool _busy = false;

  late final PagedCubit<InvoiceLine> _lines = PagedCubit<InvoiceLine>(
    (page, size) => _billing.lines(widget.id, page: page, size: size),
    pageSize: 50,
    keyOf: (line) => line.id,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_lines.close());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final invoice = await _billing.invoice(widget.id);
      if (!mounted) return;
      setState(() {
        _invoice = invoice;
        _errorKey = null;
      });
      unawaited(_lines.load());
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _errorKey = failure.message);
    }
  }

  void _toast(String key, {bool error = false}) {
    if (!mounted) return;
    showGlassToast(
      context,
      context.t(key),
      kind: error ? GlassToastKind.error : GlassToastKind.success,
    );
  }

  /// Runs one change and takes the invoice it answers with.
  Future<void> _run(
    Future<InvoiceDetail?> Function() action, {
    String? doneKey,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final next = await action();
      if (!mounted) return;
      if (next != null) {
        setState(() => _invoice = next);
        unawaited(_lines.load());
      }
      if (doneKey != null) _toast(doneKey);
    } on ApiFailure catch (failure) {
      _toast(failure.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _menu(Rect? anchor) async {
    final invoice = _invoice;
    if (invoice == null || anchor == null) return;
    final draft = invoice.editable;
    final creditable =
        !draft &&
        invoice.summary.kind == InvoiceKind.invoice &&
        !invoice.summary.isCredited;
    final picked = await showGlassMenu<_Action>(
      context: context,
      anchorRect: anchor,
      width: 260,
      value: _Action.pdf,
      items: [
        if (draft) ...[
          _item(_Action.edit, 'billing.invoice.edit', LucideIcons.pencil),
          _item(
            _Action.refresh,
            'billing.invoice.refresh',
            LucideIcons.refreshCw,
          ),
        ],
        if (creditable)
          _item(
            _Action.creditNote,
            'billing.invoice.creditNote',
            LucideIcons.fileMinus2,
          ),
        _item(
          _Action.pdf,
          'time.reports.export.pdf',
          LucideIcons.fileText,
          divider: draft || creditable,
        ),
        _item(_Action.docx, 'time.reports.export.docx', LucideIcons.fileText),
        _item(
          _Action.xlsx,
          'time.reports.export.xlsx',
          LucideIcons.fileSpreadsheet,
        ),
        _item(_Action.print, 'time.reports.export.print', LucideIcons.printer),
        if (draft)
          GlassMenuItem(
            value: _Action.delete,
            label: context.t('billing.invoice.delete'),
            leading: const Icon(
              LucideIcons.trash2,
              size: 16,
              color: AppColors.danger,
            ),
            color: AppColors.danger,
            dividerAbove: true,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case _Action.edit:
        await _edit();
      case _Action.refresh:
        await _run(
          () => _billing.refresh(widget.id),
          doneKey: 'billing.invoice.refreshed',
        );
      case _Action.issue:
        await _issue();
      case _Action.delete:
        await _delete();
      case _Action.creditNote:
        await _creditNote();
      case _Action.pdf:
        await _export('pdf', anchor);
      case _Action.docx:
        await _export('docx', anchor);
      case _Action.xlsx:
        await _export('xlsx', anchor);
      case _Action.print:
        await _print();
    }
  }

  GlassMenuItem<_Action> _item(
    _Action value,
    String labelKey,
    IconData icon, {
    bool divider = false,
  }) => GlassMenuItem(
    value: value,
    label: context.t(labelKey),
    leading: Icon(icon, size: 16, color: AppColors.inkSoft),
    dividerAbove: divider,
  );

  Future<void> _issue() async {
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.fileCheck2,
      title: context.t('billing.invoice.issueTitle'),
      message: context.t('billing.invoice.issueMessage'),
      confirmLabel: context.t('billing.invoice.issue'),
      confirmIcon: LucideIcons.fileCheck2,
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => _billing.issue(widget.id),
      doneKey: 'billing.invoice.issued',
    );
  }

  Future<void> _delete() async {
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('billing.invoice.deleteTitle'),
      message: context.t('billing.invoice.deleteMessage'),
      confirmLabel: context.t('billing.invoice.delete'),
      destructive: true,
      confirmIcon: LucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _billing.deleteDraft(widget.id);
      if (!mounted) return;
      _toast('billing.invoice.deleted');
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(invoicesRoute);
      }
    } on ApiFailure catch (failure) {
      _toast(failure.message, error: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _creditNote() async {
    final reason = await showGlassModal<String>(
      context,
      width: 440,
      builder: (_) => const _CreditNoteForm(),
    );
    if (reason == null || !mounted) return;
    InvoiceDetail? credit;
    await _run(() async {
      credit = await _billing.creditNote(
        widget.id,
        reason: reason.isEmpty ? null : reason,
      );
      return _billing.invoice(widget.id);
    }, doneKey: 'billing.invoice.credited');
    final created = credit;
    if (created != null && mounted) {
      context.push('$invoicesRoute/${created.summary.id}');
    }
  }

  Future<void> _edit() async {
    final invoice = _invoice;
    if (invoice == null) return;
    final next = await showGlassModal<InvoiceDetail>(
      context,
      width: 500,
      builder: (_) => _EditDraftForm(billing: _billing, invoice: invoice),
    );
    if (next != null && mounted) setState(() => _invoice = next);
  }

  String _fileName(String format) {
    final number = _invoice?.summary.number;
    return '${number ?? 'invoice-draft'}.$format';
  }

  Future<void> _export(String format, Rect? anchor) async {
    final origin = shareOriginOf(context, preferred: anchor);
    try {
      final bytes = await _billing.export(widget.id, format);
      final mime = switch (format) {
        'pdf' => 'application/pdf',
        'docx' =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        _ =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      };
      final result = await downloadBytes(
        _fileName(format),
        bytes,
        mime,
        sharePositionOrigin: origin,
      );
      if (!mounted || result.outcome == DownloadOutcome.dismissed) return;
      final failed = result.outcome == DownloadOutcome.failed;
      _toast(
        failed ? 'time.reports.export.failed' : 'time.reports.export.done',
        error: failed,
      );
    } on ApiFailure catch (failure) {
      _toast(failure.message, error: true);
    }
  }

  Future<void> _print() async {
    try {
      final bytes = await _billing.export(widget.id, 'pdf');
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: _fileName('pdf'),
      );
    } on ApiFailure catch (failure) {
      _toast(failure.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoice = _invoice;
    return PageChrome(
      contentMax: Breakpoints.readingWidth,
      title: invoice == null
          ? context.t('billing.invoices.title')
          : invoiceTitle(context, invoice.summary),
      actions: [
        if (invoice != null && invoice.editable)
          PageAction(
            icon: LucideIcons.fileCheck2,
            label: context.t('billing.invoice.issue'),
            primary: true,
            busy: _busy,
            onTap: (_) => unawaited(_issue()),
          ),
        if (invoice != null)
          PageAction(
            icon: LucideIcons.ellipsis,
            label: context.t('billing.invoice.actions'),
            onTap: (anchor) => unawaited(_menu(anchor)),
          ),
      ],
      child: _body(context, invoice),
    );
  }

  Widget _body(BuildContext context, InvoiceDetail? invoice) {
    if (invoice == null) {
      return _errorKey == null
          ? const Center(child: HiveLoader(size: 30))
          : Center(
              child: HiveEmptyState(
                title: context.t('billing.invoices.title'),
                message: context.t(_errorKey!),
                action: GhostButton(
                  icon: LucideIcons.refreshCw,
                  label: context.t('common.retry'),
                  onPressed: () => unawaited(_load()),
                ),
              ),
            );
    }
    final padding = EdgeInsets.fromLTRB(
      context.pageGutter,
      context.topGutter + 12,
      context.pageGutter,
      context.bottomGutter + 24,
    );
    return BlocBuilder<PagedCubit<InvoiceLine>, PagedState<InvoiceLine>>(
      bloc: _lines,
      builder: (context, state) {
        final head = <Widget>[
          _InvoiceHead(invoice: invoice),
          const SizedBox(height: 12),
          _InvoiceTotals(invoice: invoice),
          if (invoice.editable && invoice.unratedLines > 0) ...[
            const SizedBox(height: 12),
            _Notice(
              icon: LucideIcons.triangleAlert,
              text: context.t(
                'billing.invoice.unratedHint',
                variables: {'count': '${invoice.unratedLines}'},
              ),
            ),
          ],
          if (invoice.editable) ...[
            const SizedBox(height: 12),
            _Notice(
              icon: LucideIcons.info,
              text: context.t('billing.invoice.draftHint'),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            context.t(
              'billing.invoice.linesTitle',
              variables: {'count': '${invoice.lineCount}'},
            ),
            style: TextStyle(
              fontSize: AppType.label,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
        ];
        final lines = state.items;
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (state.hasMore && notification.metrics.extentAfter < 400) {
              unawaited(_lines.loadMore());
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: padding,
              itemCount:
                  head.length +
                  lines.length +
                  (state.isLoading && lines.isEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < head.length) return head[index];
                final at = index - head.length;
                if (at >= lines.length) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: HiveLoader(size: 26)),
                  );
                }
                final line = lines[at];
                return _LineRow(
                  line: line,
                  currency: invoice.summary.currency,
                  onRemove: invoice.editable && !_busy
                      ? () => unawaited(
                          _run(
                            () => _billing.updateDraft(
                              widget.id,
                              removeLineIds: [line.id],
                            ),
                            doneKey: 'billing.invoice.lineRemoved',
                          ),
                        )
                      : null,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _InvoiceHead extends StatelessWidget {
  const _InvoiceHead({required this.invoice});

  final InvoiceDetail invoice;

  @override
  Widget build(BuildContext context) {
    final summary = invoice.summary;
    final recipient = invoice.recipient;
    final rows = <(String, String)>[
      (context.t('billing.invoice.project'), invoiceProject(summary)),
      (context.t('billing.invoice.period'), invoicePeriod(context, summary)),
      (
        context.t('billing.invoice.lineBy'),
        context.t(invoice.grouping.labelKey),
      ),
      if (invoice.creditedInvoiceNumber != null)
        (context.t('billing.invoice.reverses'), invoice.creditedInvoiceNumber!),
      if (invoice.creditNoteNumber != null)
        (context.t('billing.invoice.reversedBy'), invoice.creditNoteNumber!),
    ];
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InvoiceStatusLabel(invoice: summary),
          const SizedBox(height: 10),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _Pair(label: label, value: value),
            ),
          const SizedBox(height: 6),
          Text(
            context.t('billing.invoice.recipient'),
            style: TextStyle(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            recipient.isEmpty
                ? context.t('billing.invoice.noRecipient')
                : [
                    ?recipient.name,
                    ?recipient.address,
                    if (recipient.vatId != null && recipient.vatId!.isNotEmpty)
                      '${context.t('billing.invoice.vatId')}: ${recipient.vatId}',
                  ].where((part) => part.isNotEmpty).join('\n'),
            style: TextStyle(
              fontSize: AppType.label,
              height: 1.45,
              color: recipient.isEmpty ? AppColors.inkFaint : AppColors.ink,
            ),
          ),
          if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              invoice.notes!,
              style: TextStyle(
                fontSize: AppType.label,
                height: 1.45,
                color: AppColors.inkSoft,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pair extends StatelessWidget {
  const _Pair({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Wrap(
      spacing: 8,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppType.label,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: AppType.label,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ],
    ),
  );
}

class _InvoiceTotals extends StatelessWidget {
  const _InvoiceTotals({required this.invoice});

  final InvoiceDetail invoice;

  @override
  Widget build(BuildContext context) {
    final totals = invoice.summary.totals;
    final currency = invoice.summary.currency;
    Widget row(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: strong ? AppType.body : AppType.label,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                  color: strong ? AppColors.ink : AppColors.textSecondary,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: strong ? AppType.body : AppType.label,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          row(
            context.t('billing.invoice.hours'),
            formatHours(context, totals.minutes),
          ),
          row(
            context.t('billing.invoice.net'),
            formatMoney(context, totals.netCents, currency),
          ),
          if (invoice.taxBasisPoints > 0)
            row(
              context.t(
                'billing.invoice.taxLine',
                variables: {
                  'rate': basisPointsText(context, invoice.taxBasisPoints),
                },
              ),
              formatMoney(context, totals.taxCents, currency),
            ),
          row(
            context.t('billing.invoice.gross'),
            formatMoney(context, totals.grossCents, currency),
            strong: true,
          ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.currency, this.onRemove});

  final InvoiceLine line;
  final String currency;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final detail = line.unrated
        ? context.t(
            'billing.invoice.lineUnrated',
            variables: {'hours': formatHours(context, line.minutes)},
          )
        : context.t(
            'billing.invoice.lineDetail',
            variables: {
              'hours': formatHours(context, line.minutes),
              'rate': formatMoney(context, line.rateCents, currency),
              'entries': '${line.entries}',
            },
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            if (line.unrated) ...[
              Icon(
                LucideIcons.triangleAlert,
                size: 16,
                color: AppColors.accentInk,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.description,
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: AppType.caption,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatMoney(context, line.amountCents, currency),
              style: TextStyle(
                fontSize: AppType.label,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: AppColors.ink,
              ),
            ),
            if (onRemove != null)
              IconButton(
                tooltip: context.t('billing.invoice.removeLine'),
                onPressed: onRemove,
                icon: Icon(LucideIcons.x, size: 16, color: AppColors.inkSoft),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.hairline2),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.inkSoft),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: AppType.label,
              height: 1.45,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The reason a credit note is written, kept on it. Resolves to the reason
/// (empty for none) or null when cancelled.
class _CreditNoteForm extends StatefulWidget {
  const _CreditNoteForm();

  @override
  State<_CreditNoteForm> createState() => _CreditNoteFormState();
}

class _CreditNoteFormState extends State<_CreditNoteForm> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GlassModalHeader(
        icon: LucideIcons.fileMinus2,
        title: context.t('billing.invoice.creditTitle'),
        subtitle: context.t('billing.invoice.creditMessage'),
        subtitleMaxLines: 4,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
        child: GlassField(
          label: context.t('billing.invoice.creditReason'),
          child: TextField(
            controller: _reason,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: glassInputDecoration().copyWith(counterText: ''),
          ),
        ),
      ),
      GlassModalFooter(
        confirmLabel: context.t('billing.invoice.creditNote'),
        confirmIcon: LucideIcons.fileMinus2,
        confirmColor: AppColors.danger,
        onConfirm: () => Navigator.of(context).pop(_reason.text.trim()),
      ),
    ],
  );
}

/// The recipient, notes and tax of a draft.
class _EditDraftForm extends StatefulWidget {
  const _EditDraftForm({required this.billing, required this.invoice});

  final BillingRepository billing;
  final InvoiceDetail invoice;

  @override
  State<_EditDraftForm> createState() => _EditDraftFormState();
}

class _EditDraftFormState extends State<_EditDraftForm> {
  late final _name = TextEditingController(text: widget.invoice.recipient.name);
  late final _address = TextEditingController(
    text: widget.invoice.recipient.address,
  );
  late final _vatId = TextEditingController(
    text: widget.invoice.recipient.vatId,
  );
  late final _notes = TextEditingController(text: widget.invoice.notes);
  late final _tax = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tax.text.isEmpty) {
      _tax.text = basisPointsText(context, widget.invoice.taxBasisPoints);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _vatId.dispose();
    _notes.dispose();
    _tax.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final tax = _tax.text.trim().isEmpty ? 0 : parseBasisPoints(_tax.text);
    if (tax == null) {
      setState(() => _error = 'error.billing.invoice.tax');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final next = await widget.billing.updateDraft(
        widget.invoice.summary.id,
        recipient: InvoiceRecipient(
          name: _name.text.trim(),
          address: _address.text.trim(),
          vatId: _vatId.text.trim(),
        ),
        notes: _notes.text.trim(),
        taxBasisPoints: tax,
      );
      if (mounted) Navigator.of(context).pop(next);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GlassModalHeader(
        icon: LucideIcons.pencil,
        title: context.t('billing.invoice.edit'),
        subtitle: invoiceProject(widget.invoice.summary),
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InvoiceRecipientFields(
                name: _name,
                address: _address,
                vatId: _vatId,
                enabled: !_saving,
              ),
              const SizedBox(height: 12),
              GlassField(
                label: context.t('billing.invoice.tax'),
                child: TextField(
                  controller: _tax,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: glassInputDecoration(
                    hint: context.t('billing.invoice.taxHint'),
                  ).copyWith(suffixText: '%'),
                ),
              ),
              const SizedBox(height: 12),
              GlassField(
                label: context.t('billing.invoice.notes'),
                child: TextField(
                  controller: _notes,
                  enabled: !_saving,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 500,
                  decoration: glassInputDecoration().copyWith(counterText: ''),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    context.t(_error!),
                    style: const TextStyle(
                      fontSize: AppType.label,
                      height: 1.4,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      GlassModalFooter(
        confirmLabel: context.t('common.save'),
        busy: _saving,
        onConfirm: _saving ? null : () => unawaited(_save()),
      ),
    ],
  );
}
