import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/blocs/paged_cubit.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/billing_models.dart';
import '../../../core/repositories/billing_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart' show GhostButton;
import '../../../core/widgets/person_picker.dart';
import '../../billing/billing_format.dart';
import '../../billing/invoice_draft_sheet.dart';
import '../../billing/invoices_screen.dart' show invoicesRoute;
import '../../billing/rate_timeline_sheet.dart';
import '../../sprint/modals/glass_modal.dart' show anchorRectOf;
import 'settings_common.dart';

/// Project settings → Abrechnung (HIN-96): what an hour on this project is
/// billed at, per member where it differs, and the way to its invoices.
///
/// The lead's: revenue rates of their own project. What anybody costs is not
/// here — that is an administrator's, under the rates page (R7). Every change
/// goes through the rate's timeline, so a new rate starts on a day and last
/// month keeps the rate it was worked at.
class ProjectBillingSection extends StatefulWidget {
  const ProjectBillingSection({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  final String projectId;
  final String projectName;

  @override
  State<ProjectBillingSection> createState() => _ProjectBillingSectionState();
}

class _ProjectBillingSectionState extends State<ProjectBillingSection> {
  late final BillingRepository _billing = context.read<BillingRepository>();
  final _addKey = GlobalKey();
  BillingAccess? _access;
  BillingRate? _projectRate;
  bool _projectRateKnown = false;

  late final PagedCubit<BillingRate> _members = PagedCubit<BillingRate>(
    (page, size) => _billing.rates(
      kind: RateKind.billable,
      scope: RateScope.projectMember,
      projectId: widget.projectId,
      status: RateStatus.active,
      page: page,
      size: size,
    ),
    pageSize: 20,
    keyOf: (rate) => rate.id,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_members.close());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final access = await _billing.access();
      if (!mounted) return;
      setState(() => _access = access);
      if (!access.leads(widget.projectId)) return;
      final project = await _billing.rates(
        kind: RateKind.billable,
        scope: RateScope.project,
        scopeId: widget.projectId,
        status: RateStatus.active,
        size: 1,
      );
      if (!mounted) return;
      setState(() {
        _projectRate = project.items.firstOrNull;
        _projectRateKnown = true;
      });
      unawaited(_members.load());
    } catch (_) {
      if (mounted) setState(() => _access = BillingAccess.none);
    }
  }

  Future<void> _open(RateTarget target) async {
    final changed = await showRateTimelineSheet(
      context,
      billing: _billing,
      target: target,
      currency: _access?.currency ?? 'EUR',
    );
    if (changed == true) unawaited(_load());
  }

  Future<void> _addMember() async {
    final person = await showPersonPicker(
      context,
      anchorRect: anchorRectOf(_addKey) ?? Rect.zero,
    );
    if (person == null || !mounted) return;
    await _open(
      RateTarget(
        kind: RateKind.billable,
        scope: RateScope.projectMember,
        scopeId: widget.projectId,
        secondaryId: person.id,
        label: person.displayName,
      ),
    );
  }

  Future<void> _draftInvoice() async {
    final draft = await showInvoiceDraftSheet(
      context,
      billing: _billing,
      projectId: widget.projectId,
      projectName: widget.projectName,
    );
    if (draft != null && mounted) {
      unawaited(context.push('$invoicesRoute/${draft.summary.id}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    return SettingsSection(
      title: context.t('projectSettings.billing.title'),
      note: context.t('projectSettings.billing.note'),
      child:
          access == null ||
              (access.leads(widget.projectId) && !_projectRateKnown)
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: HiveLoader(size: 28)),
            )
          : !access.leads(widget.projectId)
          ? Text(
              context.t('projectSettings.billing.notLead'),
              style: TextStyle(
                fontSize: AppType.label,
                color: AppColors.inkSoft,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FieldLabel(
                  text: context.t('projectSettings.billing.projectRate'),
                ),
                _RateLine(
                  value: _projectRate == null
                      ? context.t('projectSettings.billing.noRate')
                      : context.t(
                          'billing.rate.perHour',
                          variables: {
                            'amount': formatMoney(
                              context,
                              _projectRate!.amountCents,
                              _projectRate!.currency,
                            ),
                          },
                        ),
                  muted: _projectRate == null,
                  actionLabel: context.t(
                    _projectRate == null
                        ? 'projectSettings.billing.setRate'
                        : 'projectSettings.billing.changeRate',
                  ),
                  onAction: () => unawaited(
                    _open(
                      RateTarget(
                        kind: RateKind.billable,
                        scope: RateScope.project,
                        scopeId: widget.projectId,
                        label: widget.projectName,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FieldLabel(
                  text: context.t('projectSettings.billing.memberRates'),
                ),
                BlocBuilder<PagedCubit<BillingRate>, PagedState<BillingRate>>(
                  bloc: _members,
                  builder: (context, state) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.items.isEmpty && !state.isLoading)
                        Text(
                          context.t('projectSettings.billing.noMemberRates'),
                          style: TextStyle(
                            fontSize: AppType.label,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      for (final rate in state.items)
                        _RateLine(
                          label:
                              rate.memberLabel ?? context.t('time.deletedUser'),
                          value: context.t(
                            'billing.rate.perHour',
                            variables: {
                              'amount': formatMoney(
                                context,
                                rate.amountCents,
                                rate.currency,
                              ),
                            },
                          ),
                          actionLabel: context.t(
                            'projectSettings.billing.changeRate',
                          ),
                          onAction: () => unawaited(_open(rate.target)),
                        ),
                      if (state.hasMore)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            onPressed: () => unawaited(_members.loadMore()),
                            child: Text(context.t('common.loadMore')),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    KeyedSubtree(
                      key: _addKey,
                      child: GhostButton(
                        icon: LucideIcons.userPlus,
                        label: context.t('projectSettings.billing.addMember'),
                        onPressed: () => unawaited(_addMember()),
                      ),
                    ),
                    GhostButton(
                      icon: LucideIcons.filePlus2,
                      label: context.t('billing.invoice.new'),
                      onPressed: () => unawaited(_draftInvoice()),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// A rate with its label and the one action that changes it.
class _RateLine extends StatelessWidget {
  const _RateLine({
    required this.value,
    required this.actionLabel,
    required this.onAction,
    this.label,
    this.muted = false,
  });

  final String? label;
  final String value;
  final bool muted;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null)
                  Text(
                    label!,
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: label == null ? AppType.body : AppType.label,
                    fontWeight: label == null
                        ? FontWeight.w700
                        : FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: muted ? AppColors.inkFaint : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    ),
  );
}
