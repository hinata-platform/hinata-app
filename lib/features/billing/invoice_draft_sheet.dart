import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/billing_models.dart';
import '../../core/repositories/billing_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../../core/widgets/field_button.dart';
import '../../core/widgets/project_picker.dart';
import '../sprint/modals/glass_modal.dart';
import 'billing_format.dart';

/// Drafts an invoice (HIN-96): one project, a service period, how lines are
/// grouped, and who it goes to. The lines themselves are the server's — the
/// billable entries nobody billed yet, valued on their own days — and the
/// draft page shows them before anything is issued.
///
/// The recipient and tax can wait: the draft page edits them too. Only the
/// project and the period decide what goes in. Resolves to the new draft.
Future<InvoiceDetail?> showInvoiceDraftSheet(
  BuildContext context, {
  required BillingRepository billing,
  String? projectId,
  String? projectName,
}) {
  final projects = context.read<ProjectRepository>();
  return showGlassModal<InvoiceDetail>(
    context,
    width: 520,
    builder: (_) => RepositoryProvider<ProjectRepository>.value(
      value: projects,
      child: _InvoiceDraftForm(
        billing: billing,
        projectId: projectId,
        projectName: projectName,
      ),
    ),
  );
}

class _InvoiceDraftForm extends StatefulWidget {
  const _InvoiceDraftForm({
    required this.billing,
    this.projectId,
    this.projectName,
  });

  final BillingRepository billing;
  final String? projectId;
  final String? projectName;

  @override
  State<_InvoiceDraftForm> createState() => _InvoiceDraftFormState();
}

class _InvoiceDraftFormState extends State<_InvoiceDraftForm> {
  final _projectKey = GlobalKey();
  final _periodKey = GlobalKey();
  final _groupingKey = GlobalKey();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _vatId = TextEditingController();
  final _tax = TextEditingController();

  late String? _projectId = widget.projectId;
  late String? _projectName = widget.projectName;
  late DateTimeRange _period = _lastMonth();
  InvoiceGrouping _grouping = InvoiceGrouping.issue;
  bool _saving = false;
  String? _error;

  /// Last month: what is invoiced far more often than anything else.
  static DateTimeRange _lastMonth() {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month - 1);
    return DateTimeRange(start: first, end: DateTime(now.year, now.month, 0));
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _vatId.dispose();
    _tax.dispose();
    super.dispose();
  }

  Future<void> _pickProject() async {
    final picked = await showProjectPicker(
      context,
      anchorRect: anchorRectOf(_projectKey) ?? Rect.zero,
      selected: {?_projectId},
      titleKey: 'billing.invoice.pickProject',
      multi: false,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      _projectId = picked.first.id;
      _projectName = picked.first.name;
    });
  }

  Future<void> _pickPeriod() async {
    final picked = await showGlassDateRangePicker(
      context,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      initialRange: _period,
      title: context.t('billing.invoice.period'),
    );
    if (picked != null && mounted) setState(() => _period = picked);
  }

  Future<void> _pickGrouping() async {
    final picked = await showGlassOptions<InvoiceGrouping>(
      context,
      title: context.t('billing.invoice.lineBy'),
      anchorRect: anchorRectOf(_groupingKey),
      options: [
        for (final grouping in InvoiceGrouping.values)
          (value: grouping, child: Text(context.t(grouping.labelKey))),
      ],
    );
    if (picked != null && mounted) setState(() => _grouping = picked);
  }

  Future<void> _create() async {
    final projectId = _projectId;
    if (projectId == null) {
      setState(() => _error = 'error.billing.invoice.project');
      return;
    }
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
      final draft = await widget.billing.createDraft(
        InvoiceDraftRequest(
          projectId: projectId,
          from: _period.start,
          to: _period.end,
          grouping: _grouping,
          recipient: InvoiceRecipient(
            name: _name.text.trim(),
            address: _address.text.trim(),
            vatId: _vatId.text.trim(),
          ),
          taxBasisPoints: tax,
        ),
      );
      if (mounted) Navigator.of(context).pop(draft);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.receiptText,
          title: context.t('billing.invoice.newTitle'),
          subtitle: context.t('billing.invoice.newSubtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeyedSubtree(
                  key: _projectKey,
                  child: FieldButton(
                    icon: LucideIcons.folderKanban,
                    label: context.t('billing.invoice.project'),
                    value:
                        _projectName ??
                        context.t('billing.invoice.pickProject'),
                    empty: _projectId == null,
                    onTap: _saving ? () {} : () => unawaited(_pickProject()),
                  ),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _periodKey,
                  child: FieldButton(
                    icon: LucideIcons.calendarRange,
                    label: context.t('billing.invoice.period'),
                    value:
                        '${day.format(_period.start)} – ${day.format(_period.end)}',
                    onTap: _saving ? () {} : () => unawaited(_pickPeriod()),
                  ),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _groupingKey,
                  child: FieldButton(
                    icon: LucideIcons.layers,
                    label: context.t('billing.invoice.lineBy'),
                    value: context.t(_grouping.labelKey),
                    onTap: _saving ? () {} : () => unawaited(_pickGrouping()),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  context.t('billing.invoice.recipient'),
                  style: TextStyle(
                    fontSize: AppType.label,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 10),
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
          confirmLabel: context.t('billing.invoice.createDraft'),
          confirmIcon: LucideIcons.filePlus2,
          busy: _saving,
          onConfirm: _saving ? null : () => unawaited(_create()),
        ),
      ],
    );
  }
}

/// Name, address and VAT id of a recipient: free text, at most 500 each.
class InvoiceRecipientFields extends StatelessWidget {
  const InvoiceRecipientFields({
    super.key,
    required this.name,
    required this.address,
    required this.vatId,
    this.enabled = true,
  });

  final TextEditingController name;
  final TextEditingController address;
  final TextEditingController vatId;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlassField(
        label: context.t('billing.invoice.recipientName'),
        child: TextField(
          controller: name,
          enabled: enabled,
          maxLength: 500,
          decoration: glassInputDecoration().copyWith(counterText: ''),
        ),
      ),
      const SizedBox(height: 12),
      GlassField(
        label: context.t('billing.invoice.recipientAddress'),
        child: TextField(
          controller: address,
          enabled: enabled,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: glassInputDecoration().copyWith(counterText: ''),
        ),
      ),
      const SizedBox(height: 12),
      GlassField(
        label: context.t('billing.invoice.vatId'),
        child: TextField(
          controller: vatId,
          enabled: enabled,
          maxLength: 500,
          decoration: glassInputDecoration().copyWith(counterText: ''),
        ),
      ),
    ],
  );
}
