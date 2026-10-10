import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/billing_models.dart';
import '../../core/repositories/billing_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../../core/widgets/field_button.dart';
import '../../core/widgets/hive_loader.dart';
import '../sprint/modals/glass_modal.dart';
import 'billing_format.dart';

/// One target's rates over time, and a new one from a date on (HIN-96).
///
/// The way a rate changes here is the way it changes in the books: a new rate
/// from a day on, which closes the running one the day before. Nothing is
/// overwritten, so last month's entries keep the rate they were worked at. A
/// planned change is a rate from a future day; a correction backwards is a
/// rate from an earlier one — the same form either way.
///
/// [canEdit] is false where the reader may see the rates but not set them.
/// Resolves to true when something changed.
Future<bool?> showRateTimelineSheet(
  BuildContext context, {
  required BillingRepository billing,
  required RateTarget target,
  required String currency,
  bool canEdit = true,
}) => showGlassModal<bool>(
  context,
  width: 500,
  builder: (_) => _RateTimeline(
    billing: billing,
    target: target,
    currency: currency,
    canEdit: canEdit,
  ),
);

class _RateTimeline extends StatefulWidget {
  const _RateTimeline({
    required this.billing,
    required this.target,
    required this.currency,
    required this.canEdit,
  });

  final BillingRepository billing;
  final RateTarget target;
  final String currency;
  final bool canEdit;

  @override
  State<_RateTimeline> createState() => _RateTimelineState();
}

class _RateTimelineState extends State<_RateTimeline> {
  final _amount = TextEditingController();
  final _dateKey = GlobalKey();
  List<BillingRate>? _rates;
  DateTime _from = DateUtils.dateOnly(DateTime.now());
  bool _saving = false;
  bool _changed = false;
  String? _error;
  final Set<String> _removing = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rates = await widget.billing.timeline(widget.target);
      if (!mounted) return;
      setState(() => _rates = rates);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _rates = const [];
        _error = failure.message;
      });
    }
  }

  Future<void> _pickDate() async {
    final anchor = anchorRectOf(_dateKey);
    final picked = await showGlassDatePopover(
      context,
      anchorRect: anchor ?? Rect.zero,
      initialDate: _from,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
      title: context.t('billing.rate.from'),
    );
    if (picked != null && mounted) setState(() => _from = picked);
  }

  Future<void> _save() async {
    final cents = parseCents(_amount.text);
    if (cents == null) {
      setState(() => _error = 'billing.rate.amountInvalid');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.billing.createRate(
        widget.target,
        amountCents: cents,
        from: _from,
      );
      if (!mounted) return;
      _amount.clear();
      _changed = true;
      setState(() => _saving = false);
      showGlassToast(context, context.t('billing.rate.saved'));
      await _load();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _remove(BillingRate rate) async {
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('billing.rate.removeTitle'),
      message: context.t('billing.rate.removeMessage'),
      confirmLabel: context.t('billing.rate.remove'),
      destructive: true,
      confirmIcon: LucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removing.add(rate.id));
    try {
      await widget.billing.deleteRate(rate.id);
      _changed = true;
      await _load();
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _removing.remove(rate.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassModalHeader(
            icon: target.kind == RateKind.cost
                ? LucideIcons.walletCards
                : LucideIcons.coins,
            title: target.label ?? context.t(target.scope.labelKey),
            subtitle: context.t(
              target.kind == RateKind.cost
                  ? 'billing.rate.costOf'
                  : 'billing.rate.revenueOf',
              variables: {'target': context.t(target.scope.labelKey)},
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _timeline(context),
                  if (widget.canEdit) ...[
                    const SizedBox(height: 18),
                    Text(
                      context.t('billing.rate.changeFrom'),
                      style: TextStyle(
                        fontSize: AppType.label,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.t('billing.rate.changeHint'),
                      style: TextStyle(
                        fontSize: AppType.caption,
                        height: 1.4,
                        color: AppColors.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassField(
                      label: context.t('billing.rate.amount'),
                      child: TextField(
                        controller: _amount,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                            glassInputDecoration(
                              hint: context.t('billing.rate.amountHint'),
                            ).copyWith(
                              suffixText:
                                  '${currencySymbol(context, widget.currency)} / h',
                            ),
                        onSubmitted: (_) => unawaited(_save()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    KeyedSubtree(
                      key: _dateKey,
                      child: FieldButton(
                        icon: LucideIcons.calendarClock,
                        label: context.t('billing.rate.from'),
                        value: DateFormat.yMMMd(
                          Localizations.localeOf(context).toLanguageTag(),
                        ).format(_from),
                        onTap: _saving ? () {} : () => unawaited(_pickDate()),
                      ),
                    ),
                  ],
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
          if (widget.canEdit)
            GlassModalFooter(
              confirmLabel: context.t('billing.rate.set'),
              confirmIcon: LucideIcons.check,
              busy: _saving,
              onConfirm: _saving ? null : () => unawaited(_save()),
            ),
        ],
      ),
    );
  }

  Widget _timeline(BuildContext context) {
    final rates = _rates;
    if (rates == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: HiveLoader(size: 26)),
      );
    }
    if (rates.isEmpty) {
      return Text(
        context.t('billing.rate.none'),
        style: TextStyle(fontSize: AppType.label, color: AppColors.inkSoft),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final rate in rates)
          RateSpanRow(
            rate: rate,
            busy: _removing.contains(rate.id),
            onRemove: widget.canEdit ? () => unawaited(_remove(rate)) : null,
          ),
      ],
    );
  }
}

/// One rate of a timeline: amount per hour, its span, where it stands.
class RateSpanRow extends StatelessWidget {
  const RateSpanRow({
    super.key,
    required this.rate,
    this.busy = false,
    this.onRemove,
  });

  final BillingRate rate;
  final bool busy;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final day = DateFormat.yMMMd(locale);
    final span = rate.validTo == null
        ? context.t(
            'billing.rate.since',
            variables: {'from': day.format(rate.validFrom)},
          )
        : context.t(
            'billing.rate.span',
            variables: {
              'from': day.format(rate.validFrom),
              'to': day.format(rate.validTo!),
            },
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          RateStatusMark(status: rate.status),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t(
                    'billing.rate.perHour',
                    variables: {
                      'amount': formatMoney(
                        context,
                        rate.amountCents,
                        rate.currency,
                      ),
                    },
                  ),
                  style: TextStyle(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: rate.status == RateStatus.ended
                        ? AppColors.inkSoft
                        : AppColors.ink,
                  ),
                ),
                Text(
                  '$span · ${context.t(rate.status.labelKey)}',
                  style: TextStyle(
                    fontSize: AppType.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: context.t('billing.rate.remove'),
              onPressed: busy ? null : onRemove,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      LucideIcons.trash2,
                      size: 18,
                      color: AppColors.inkSoft,
                    ),
            ),
        ],
      ),
    );
  }
}

/// Where a rate stands as a glyph — always beside its word, never alone.
class RateStatusMark extends StatelessWidget {
  const RateStatusMark({super.key, required this.status});

  final RateStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      RateStatus.active => (LucideIcons.circleCheck, AppColors.successInk),
      RateStatus.planned => (LucideIcons.calendarClock, AppColors.accentInk),
      RateStatus.ended => (LucideIcons.circleDashed, AppColors.inkFaint),
    };
    return ExcludeSemantics(child: Icon(icon, size: 18, color: color));
  }
}
