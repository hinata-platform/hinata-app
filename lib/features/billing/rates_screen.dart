import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/billing_models.dart';
import '../../core/repositories/billing_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../../core/widgets/glass_filter_bar.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart' show GhostButton;
import '../../core/widgets/person_picker.dart';
import '../../core/widgets/project_picker.dart';
import '../../core/widgets/soft_card.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart';
import 'billing_access_cubit.dart';
import 'billing_format.dart';
import 'rate_timeline_sheet.dart';

/// The page behind `/time/rates` (HIN-96): every rate the reader may see, with
/// the instance defaults at the top for an administrator.
///
/// An administrator sees revenue and cost rates on every target; a project
/// lead sees the revenue rates of the projects they lead and nothing about
/// what anybody costs. A row opens its target's timeline, where a rate is
/// changed from a date on.
class RatesScreen extends StatelessWidget {
  const RatesScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        BillingAccessCubit(context.read<BillingRepository>())..load(),
    child: const _RatesView(),
  );
}

class _RatesView extends StatefulWidget {
  const _RatesView();

  @override
  State<_RatesView> createState() => _RatesViewState();
}

class _RatesViewState extends State<_RatesView> {
  late final BillingRepository _billing = context.read<BillingRepository>();
  RateKind? _kind;
  RateScope? _scope;
  RateStatus? _status = RateStatus.active;

  late final PagedCubit<BillingRate> _rates = PagedCubit<BillingRate>(
    (page, size) => _billing.rates(
      kind: _kind,
      scope: _scope,
      status: _status,
      page: page,
      size: size,
    ),
    pageSize: 25,
    keyOf: (rate) => rate.id,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_rates.load());
  }

  @override
  void dispose() {
    unawaited(_rates.close());
    super.dispose();
  }

  void _reload() => unawaited(_rates.load());

  Future<void> _open(RateTarget target, BillingAccess access) async {
    final changed = await showRateTimelineSheet(
      context,
      billing: _billing,
      target: target,
      currency: access.currency,
    );
    if (changed == true) _reload();
  }

  Future<void> _pickKind(Rect? anchor, BillingAccess access) async {
    const all = '';
    final picked = await showGlassOptions<String>(
      context,
      title: context.t('billing.rates.kind'),
      anchorRect: anchor,
      options: [
        (value: all, child: Text(context.t('billing.rates.allKinds'))),
        for (final kind in RateKind.values)
          if (kind == RateKind.billable || access.costs)
            (value: kind.wire, child: Text(context.t(_kindKey(kind)))),
      ],
    );
    if (picked == null) return;
    setState(() => _kind = picked == all ? null : RateKind.parse(picked));
    _reload();
  }

  Future<void> _pickScope(Rect? anchor, BillingAccess access) async {
    const all = '';
    final picked = await showGlassOptions<String>(
      context,
      title: context.t('billing.rates.scope'),
      anchorRect: anchor,
      options: [
        (value: all, child: Text(context.t('billing.rates.allScopes'))),
        for (final scope in _scopesFor(access))
          (value: scope.wire, child: Text(context.t(scope.labelKey))),
      ],
    );
    if (picked == null) return;
    setState(() => _scope = picked == all ? null : RateScope.parse(picked));
    _reload();
  }

  Future<void> _pickStatus(Rect? anchor) async {
    const all = '';
    final picked = await showGlassOptions<String>(
      context,
      title: context.t('billing.rates.status'),
      anchorRect: anchor,
      options: [
        (value: all, child: Text(context.t('billing.rates.allStatuses'))),
        for (final status in RateStatus.values)
          (value: status.wire, child: Text(context.t(status.labelKey))),
      ],
    );
    if (picked == null) return;
    setState(() => _status = picked == all ? null : RateStatus.parse(picked));
    _reload();
  }

  static List<RateScope> _scopesFor(BillingAccess access) => access.admin
      ? RateScope.values
      : const [RateScope.project, RateScope.projectMember, RateScope.issue];

  static String _kindKey(RateKind kind) =>
      kind == RateKind.cost ? 'billing.kind.cost' : 'billing.kind.billable';

  /// "New rate": what for, then which one, then its timeline.
  Future<void> _newRate(Rect? anchor, BillingAccess access) async {
    final scope = await showGlassOptions<RateScope>(
      context,
      title: context.t('billing.rates.newFor'),
      anchorRect: anchor,
      options: [
        for (final scope in _scopesFor(access))
          if (scope != RateScope.issue)
            (value: scope, child: Text(context.t(scope.labelKey))),
      ],
    );
    if (scope == null || !mounted) return;
    var kind = RateKind.billable;
    if (access.costs &&
        scope != RateScope.project &&
        scope != RateScope.issue) {
      final picked = await showGlassOptions<RateKind>(
        context,
        title: context.t('billing.rates.kind'),
        anchorRect: anchor,
        options: [
          for (final option in RateKind.values)
            (value: option, child: Text(context.t(_kindKey(option)))),
        ],
      );
      if (picked == null || !mounted) return;
      kind = picked;
    }
    final target = await _pickTarget(scope, kind, anchor ?? Rect.zero);
    if (target == null || !mounted) return;
    await _open(target, access);
  }

  Future<RateTarget?> _pickTarget(
    RateScope scope,
    RateKind kind,
    Rect anchor,
  ) async {
    switch (scope) {
      case RateScope.instanceDefault:
        return RateTarget(
          kind: kind,
          scope: scope,
          label: context.t(scope.labelKey),
        );
      case RateScope.project:
        final projects = await showProjectPicker(
          context,
          anchorRect: anchor,
          selected: const {},
          titleKey: 'billing.rates.pickProject',
          multi: false,
        );
        if (projects == null || projects.isEmpty) return null;
        return RateTarget(
          kind: kind,
          scope: scope,
          scopeId: projects.first.id,
          label: projects.first.name,
        );
      case RateScope.projectMember:
        final projects = await showProjectPicker(
          context,
          anchorRect: anchor,
          selected: const {},
          titleKey: 'billing.rates.pickProject',
          multi: false,
        );
        if (projects == null || projects.isEmpty || !mounted) return null;
        final person = await showPersonPicker(context, anchorRect: anchor);
        if (person == null) return null;
        return RateTarget(
          kind: kind,
          scope: scope,
          scopeId: projects.first.id,
          secondaryId: person.id,
          label: '${person.displayName} · ${projects.first.name}',
        );
      case RateScope.user:
        final person = await showPersonPicker(context, anchorRect: anchor);
        if (person == null) return null;
        return RateTarget(
          kind: kind,
          scope: scope,
          scopeId: person.id,
          label: person.displayName,
        );
      case RateScope.team:
        final teams = await context.read<TeamRepository>().teams();
        if (!mounted) return null;
        final team = await showGlassOptions<String>(
          context,
          title: context.t('billing.rates.pickTeam'),
          anchorRect: anchor,
          options: [
            for (final team in teams) (value: team.id, child: Text(team.name)),
          ],
        );
        if (team == null) return null;
        return RateTarget(
          kind: kind,
          scope: scope,
          scopeId: team,
          label: teams.firstWhere((candidate) => candidate.id == team).name,
        );
      case RateScope.issue:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<BillingAccessCubit>().state;
    return PageChrome(
      contentMax: Breakpoints.readingWidth,
      title: context.t('billing.rates.title'),
      actions: [
        if (access != null && access.invoices)
          PageAction(
            icon: LucideIcons.plus,
            label: context.t('billing.rates.new'),
            primary: true,
            onTap: (anchor) => unawaited(_newRate(anchor, access)),
          ),
      ],
      child: access == null
          ? const Center(child: HiveLoader(size: 30))
          : !access.invoices
          ? Center(
              child: HiveEmptyState(
                title: context.t('billing.rates.title'),
                message: context.t('error.billing.forbidden'),
              ),
            )
          : _list(context, access),
    );
  }

  Widget _pills(BillingAccess access) {
    final pills = [
      GlassFilterPill(
        icon: LucideIcons.coins,
        label: _kind == null
            ? context.t('billing.rates.allKinds')
            : context.t(_kindKey(_kind!)),
        active: _kind != null,
        onTap: (anchor) => unawaited(_pickKind(anchor, access)),
      ),
      GlassFilterPill(
        icon: LucideIcons.target,
        label: _scope == null
            ? context.t('billing.rates.allScopes')
            : context.t(_scope!.labelKey),
        active: _scope != null,
        onTap: (anchor) => unawaited(_pickScope(anchor, access)),
      ),
      GlassFilterPill(
        icon: LucideIcons.calendarRange,
        label: _status == null
            ? context.t('billing.rates.allStatuses')
            : context.t(_status!.labelKey),
        active: _status != null,
        onTap: (anchor) => unawaited(_pickStatus(anchor)),
      ),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: pills);
  }

  Widget _defaults(BillingAccess access) => SoftCard(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('billing.rates.defaults'),
          style: TextStyle(
            fontSize: AppType.label,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          context.t('billing.rates.defaultsHint'),
          style: TextStyle(
            fontSize: AppType.caption,
            height: 1.4,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in RateKind.values)
              GhostButton(
                icon: kind == RateKind.cost
                    ? LucideIcons.walletCards
                    : LucideIcons.coins,
                label: context.t(
                  kind == RateKind.cost
                      ? 'billing.rates.defaultCost'
                      : 'billing.rates.defaultRevenue',
                ),
                onPressed: () => unawaited(
                  _open(
                    RateTarget(
                      kind: kind,
                      scope: RateScope.instanceDefault,
                      label: context.t(RateScope.instanceDefault.labelKey),
                    ),
                    access,
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _list(BuildContext context, BillingAccess access) {
    final padding = EdgeInsets.fromLTRB(
      context.pageGutter,
      context.topGutter + 12,
      context.pageGutter,
      context.bottomGutter + 24,
    );
    return BlocBuilder<PagedCubit<BillingRate>, PagedState<BillingRate>>(
      bloc: _rates,
      builder: (context, state) {
        final head = <Widget>[
          if (access.admin) ...[_defaults(access), const SizedBox(height: 14)],
          _pills(access),
          const SizedBox(height: 12),
        ];
        Widget body;
        if (state.isLoading && state.items.isEmpty) {
          body = const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: HiveLoader(size: 28)),
          );
        } else if (state.errorKey != null && state.items.isEmpty) {
          body = HiveEmptyState(
            title: context.t('billing.rates.title'),
            message: context.t(state.errorKey!),
            action: GhostButton(
              icon: LucideIcons.refreshCw,
              label: context.t('common.retry'),
              onPressed: _reload,
            ),
          );
        } else if (state.items.isEmpty) {
          body = HiveEmptyState(
            title: context.t('billing.rates.emptyTitle'),
            message: context.t('billing.rates.emptyMessage'),
          );
        } else {
          body = const SizedBox.shrink();
        }
        final rows = state.items;
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (state.hasMore && notification.metrics.extentAfter < 400) {
              unawaited(_rates.loadMore());
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: _rates.load,
            child: ListView.builder(
              padding: padding,
              itemCount: head.length + 1 + rows.length,
              itemBuilder: (context, index) {
                if (index < head.length) return head[index];
                if (index == head.length) return body;
                final rate = rows[index - head.length - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RateCard(
                    rate: rate,
                    onTap: () => unawaited(_open(rate.target, access)),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// One rate in the list: its target, its amount, its span.
class RateCard extends StatelessWidget {
  const RateCard({super.key, required this.rate, required this.onTap});

  final BillingRate rate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final target = switch (rate.scope) {
      RateScope.instanceDefault => context.t(rate.scope.labelKey),
      RateScope.projectMember =>
        '${rate.memberLabel ?? context.t('time.deletedUser')} · '
            '${rate.targetDetail ?? rate.targetLabel ?? ''}',
      RateScope.issue => [?rate.targetDetail, ?rate.targetLabel].join(' '),
      _ => rate.targetLabel ?? rate.targetDetail ?? '—',
    };
    return Semantics(
      button: true,
      child: SoftCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  RateStatusMark(status: rate.status),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          target,
                          style: TextStyle(
                            fontSize: AppType.body,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          '${context.t(rate.scope.labelKey)} · '
                          '${context.t(rate.kind == RateKind.cost ? 'billing.kind.cost' : 'billing.kind.billable')} · '
                          '${context.t(rate.status.labelKey)}',
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
                      fontSize: AppType.label,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: AppColors.inkFaint,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
