import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/blocs/paged_cubit.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/billing_models.dart';
import '../../../core/repositories/billing_repository.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/glass_filter_bar.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart' show GhostButton;
import '../../billing/billing_format.dart';
import '../../billing/invoices_screen.dart' show invoicesRoute, ratesRoute;
import '../../sprint/modals/glass_modal.dart';
import 'report_format.dart' show textFactor;
import 'report_list_parts.dart';

/// The tab "billing" of the report page (HIN-96): revenue, profitability and
/// utilization over a window, grouped.
///
/// What a reader gets is the server's decision: an administrator everything,
/// costs included; a project lead revenue and utilization of the projects they
/// lead. Profitability needs costs and is offered only where the reader may
/// see them. People are never ranked: grouped by person, rows come in order of
/// name (R10), and there is no margin or utilization per person (R7).
class BillingReportTab extends StatefulWidget {
  const BillingReportTab({
    super.key,
    required this.access,
    required this.padding,
  });

  final BillingAccess access;

  /// The page's gutter, the bottom inset included — inside the scroll padding.
  final EdgeInsets padding;

  @override
  State<BillingReportTab> createState() => _BillingReportTabState();
}

class _BillingReportTabState extends State<BillingReportTab> {
  late final BillingRepository _billing = context.read<BillingRepository>();
  BillingReportKind _kind = BillingReportKind.billing;
  BillingGroupBy _groupBy = BillingGroupBy.project;
  late DateTimeRange _window = _month(DateTime.now());
  BillingReportHead? _head;

  late final PagedCubit<BillingRow> _rows = PagedCubit<BillingRow>((
    page,
    size,
  ) async {
    final answer = await _billing.report(
      _kind,
      from: _window.start,
      to: _window.end,
      groupBy: _groupBy,
      page: page,
      size: size,
    );
    if (mounted) setState(() => _head = answer.head);
    return answer.rows;
  }, pageSize: 25);

  static DateTimeRange _month(DateTime day) => DateTimeRange(
    start: DateTime(day.year, day.month),
    end: DateTime(day.year, day.month + 1, 0),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_rows.load());
  }

  @override
  void dispose() {
    unawaited(_rows.close());
    super.dispose();
  }

  void _reload() {
    setState(() => _head = null);
    unawaited(_rows.load());
  }

  /// A whole month moves by a month; any other window by its own length.
  void _move(int by) {
    final whole =
        _window.start.day == 1 &&
        _window.end == DateTime(_window.start.year, _window.start.month + 1, 0);
    setState(() {
      if (whole) {
        _window = _month(
          DateTime(_window.start.year, _window.start.month + by),
        );
      } else {
        final days = _window.end.difference(_window.start).inDays + 1;
        _window = DateTimeRange(
          start: _window.start.add(Duration(days: days * by)),
          end: _window.end.add(Duration(days: days * by)),
        );
      }
    });
    _reload();
  }

  Future<void> _pickWindow() async {
    final picked = await showGlassDateRangePicker(
      context,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      initialRange: _window,
      title: context.t('time.reports.pickRange'),
    );
    if (picked == null || !mounted) return;
    // At most a year, like every report.
    final end = picked.end.difference(picked.start).inDays > 365
        ? picked.start.add(const Duration(days: 365))
        : picked.end;
    setState(() => _window = DateTimeRange(start: picked.start, end: end));
    _reload();
  }

  Future<void> _pickKind(Rect? anchor) async {
    final picked = await showGlassOptions<BillingReportKind>(
      context,
      title: context.t('billing.report.kindTitle'),
      anchorRect: anchor,
      options: [
        for (final kind in BillingReportKind.values)
          if (kind != BillingReportKind.profitability || widget.access.costs)
            (value: kind, child: Text(context.t(kind.labelKey))),
      ],
    );
    if (picked == null || picked == _kind) return;
    setState(() {
      _kind = picked;
      final allowed = BillingGroupBy.forKind(
        picked,
        people: widget.access.admin,
      );
      if (!allowed.contains(_groupBy)) _groupBy = BillingGroupBy.project;
    });
    _reload();
  }

  Future<void> _pickGroup(Rect? anchor) async {
    final picked = await showGlassOptions<BillingGroupBy>(
      context,
      title: context.t('time.reports.groupBy'),
      anchorRect: anchor,
      options: [
        for (final group in BillingGroupBy.forKind(
          _kind,
          people: widget.access.admin,
        ))
          (
            value: group,
            child: Text(context.t('billing.report.group.${group.name}')),
          ),
      ],
    );
    if (picked == null || picked == _groupBy) return;
    setState(() => _groupBy = picked);
    _reload();
  }

  List<Widget> _pills(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final whole =
        _window.start.day == 1 &&
        _window.end == DateTime(_window.start.year, _window.start.month + 1, 0);
    final label = whole
        ? DateFormat.yMMMM(locale).format(_window.start)
        : '${DateFormat.yMMMd(locale).format(_window.start)} – '
              '${DateFormat.yMMMd(locale).format(_window.end)}';
    return [
      GlassFilterPill(
        icon: LucideIcons.coins,
        label: context.t(_kind.labelKey),
        active: true,
        onTap: (anchor) => unawaited(_pickKind(anchor)),
      ),
      GlassStepperPill(
        label: Semantics(
          button: true,
          label: context.t('time.reports.pickRange'),
          child: GestureDetector(
            onTap: () => unawaited(_pickWindow()),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ),
        onBack: () => _move(-1),
        onForward: () => _move(1),
        backTooltip: context.t('billing.report.previous'),
        forwardTooltip: context.t('billing.report.next'),
      ),
      GlassFilterPill(
        icon: LucideIcons.layers,
        label: context.t('billing.report.group.${_groupBy.name}'),
        active: _groupBy != BillingGroupBy.project,
        onTap: (anchor) => unawaited(_pickGroup(anchor)),
      ),
    ];
  }

  Widget _controls(BuildContext context) {
    final pills = _pills(context);
    if (context.isCompact) {
      return SizedBox(
        height: kGlassControlHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
          itemCount: pills.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, index) => pills[index],
        ),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: pills);
  }

  Widget _links(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      GhostButton(
        icon: LucideIcons.receiptText,
        label: context.t('billing.invoices.title'),
        onPressed: () => context.push(invoicesRoute),
      ),
      GhostButton(
        icon: LucideIcons.badgePercent,
        label: context.t('billing.rates.title'),
        onPressed: () => context.push(ratesRoute),
      ),
    ],
  );

  String _groupLabel(BuildContext context, BillingRow row) {
    if (row.key == null) {
      return context.t('billing.report.none.${_groupBy.name}');
    }
    final locale = Localizations.localeOf(context).toLanguageTag();
    if (_groupBy.time) {
      final day = row.day;
      if (day == null) return row.key!;
      return switch (_groupBy) {
        BillingGroupBy.month => DateFormat.yMMMM(locale).format(day),
        BillingGroupBy.week => context.t(
          'time.reports.weekOf',
          variables: {'day': DateFormat.MMMd(locale).format(day)},
        ),
        _ => DateFormat.MMMEd(locale).format(day),
      };
    }
    return row.label ?? row.detail ?? row.key!;
  }

  @override
  Widget build(BuildContext context) {
    final padding = widget.padding;
    final horizontal = padding.copyWith(top: 0, bottom: 0);
    final compact = context.isCompact;
    return BlocBuilder<PagedCubit<BillingRow>, PagedState<BillingRow>>(
      bloc: _rows,
      builder: (context, state) {
        final head = _head;
        return RefreshIndicator(
          onRefresh: _rows.load,
          child: ReportPagedScroll(
            onEnd: _rows.loadMore,
            slivers: [
              SliverPadding(padding: EdgeInsets.only(top: padding.top)),
              SliverPadding(
                padding: compact
                    ? const EdgeInsets.only(bottom: 12)
                    : horizontal.copyWith(bottom: 12),
                sliver: SliverToBoxAdapter(child: _controls(context)),
              ),
              if (widget.access.invoices)
                SliverPadding(
                  padding: horizontal.copyWith(bottom: 12),
                  sliver: SliverToBoxAdapter(child: _links(context)),
                ),
              if (state.errorKey != null && state.items.isEmpty)
                SliverToBoxAdapter(
                  child: HiveEmptyState(
                    title: context.t(state.errorKey!),
                    action: OutlinedButton(
                      onPressed: _reload,
                      child: Text(context.t('time.reports.retry')),
                    ),
                  ),
                )
              else if (head == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: HiveLoader()),
                )
              else ...[
                SliverPadding(
                  padding: horizontal.copyWith(bottom: 12),
                  sliver: SliverToBoxAdapter(child: BillingTotals(head: head)),
                ),
                if (state.items.isEmpty)
                  SliverToBoxAdapter(
                    child: HiveEmptyState(
                      title: context.t('billing.report.emptyTitle'),
                      message: context.t('billing.report.emptyMessage'),
                    ),
                  )
                else
                  SliverPadding(
                    padding: horizontal,
                    sliver: SliverList.builder(
                      itemCount: state.items.length,
                      itemBuilder: (context, index) {
                        final row = state.items[index];
                        return ReportCardEdge(
                          top: index == 0,
                          last: index == state.items.length - 1,
                          child: BillingRowView(
                            label: _groupLabel(context, row),
                            detail:
                                _groupBy.time || _groupBy == BillingGroupBy.user
                                ? null
                                : row.detail,
                            row: row,
                            head: head,
                          ),
                        );
                      },
                    ),
                  ),
                if (state.isLoadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: HiveLoader(size: 28)),
                    ),
                  ),
              ],
              SliverPadding(padding: EdgeInsets.only(bottom: padding.bottom)),
            ],
          ),
        );
      },
    );
  }
}

/// The figures one report kind shows, as (label, value) pairs.
List<(String, String)> billingFigures(
  BuildContext context,
  BillingReportHead head,
  BillingRow row,
) {
  String money(int? cents) =>
      cents == null ? '–' : formatMoney(context, cents, head.currency);
  return switch (head.kind) {
    BillingReportKind.billing => [
      (
        context.t('billing.report.billableHours'),
        formatHours(context, row.billableMinutes),
      ),
      (context.t('billing.report.revenue'), money(row.revenueCents)),
    ],
    BillingReportKind.profitability => [
      (context.t('billing.report.revenue'), money(row.revenueCents)),
      (context.t('billing.report.cost'), money(row.costCents)),
      (
        context.t('billing.report.margin'),
        row.marginPermille == null
            ? money(row.marginCents)
            : '${money(row.marginCents)} · '
                  '${formatPermille(context, row.marginPermille)}',
      ),
    ],
    BillingReportKind.utilization => [
      (context.t('billing.report.hours'), formatHours(context, row.minutes)),
      (
        context.t('billing.report.billableShare'),
        formatPermille(context, row.billablePermille),
      ),
      if (row.capacityMinutes != null)
        (
          context.t('billing.report.ofCapacity'),
          formatPermille(context, row.capacityPermille),
        ),
    ],
  };
}

/// The report's totals, with the hint when billable time went unpriced.
class BillingTotals extends StatelessWidget {
  const BillingTotals({super.key, required this.head});

  final BillingReportHead head;

  @override
  Widget build(BuildContext context) {
    final totals = head.totals;
    final unrated =
        (totals.unratedBillableMinutes ?? 0) + (totals.unratedMinutes ?? 0);
    return ReportCardEdge(
      top: true,
      last: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 28,
              runSpacing: 12,
              children: [
                for (final (label, value) in billingFigures(
                  context,
                  head,
                  totals,
                ))
                  MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: AppType.caption,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: AppType.title,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (unrated > 0) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.triangleAlert,
                    size: 15,
                    color: AppColors.accentInk,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.t(
                        'billing.report.unrated',
                        variables: {'hours': formatHours(context, unrated)},
                      ),
                      style: TextStyle(
                        fontSize: AppType.caption,
                        height: 1.4,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One group: its name, then its figures — side by side on a wide window,
/// under the name on a phone.
class BillingRowView extends StatelessWidget {
  const BillingRowView({
    super.key,
    required this.label,
    required this.row,
    required this.head,
    this.detail,
  });

  final String label;
  final String? detail;
  final BillingRow row;
  final BillingReportHead head;

  @override
  Widget build(BuildContext context) {
    final figures = billingFigures(context, head, row);
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppType.label,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        if (detail != null && detail != label)
          Text(
            detail!,
            style: TextStyle(
              fontSize: AppType.caption,
              color: AppColors.textSecondary,
            ),
          ),
      ],
    );
    Widget figure((String, String) pair, {required bool end}) => MergeSemantics(
      child: Column(
        crossAxisAlignment: end
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pair.$1,
            style: TextStyle(
              fontSize: AppType.caption,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            pair.$2,
            style: TextStyle(
              fontSize: AppType.label,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 520 * textFactor(context)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                name,
                const SizedBox(height: 6),
                Wrap(
                  spacing: 20,
                  runSpacing: 6,
                  children: [
                    for (final pair in figures) figure(pair, end: false),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: name),
              for (final pair in figures)
                SizedBox(width: 130, child: figure(pair, end: true)),
            ],
          );
        },
      ),
    );
  }
}
