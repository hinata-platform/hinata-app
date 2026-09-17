import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/absence_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_filter_bar.dart' show GlassStepperPill;
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/read_on_trigger.dart';
import 'absence_entitlement_sheets.dart' show LedgerRow;
import 'absence_labels.dart';

/// Settings → Working hours and absences → your absence balances (HIN-116).
///
/// What you are entitled to this year, what is behind you, what is still ahead,
/// and the journal every one of those numbers is the sum of.
///
/// **Only you and the people who keep absences see this.** Not your lead: that
/// a colleague is away is a planning fact and belongs to the calendar; how many
/// vacation days they have left is not a question project planning has to
/// answer (R2, R10). The server enforces it; this screen only ever asks for the
/// reader's own.
///
/// **Absent when the module is off**, and silently: the routes do not exist for
/// this client then, and a card that spun forever would be the only thing on the
/// page that ignored the switch.
class AbsenceBalancesPanel extends StatefulWidget {
  const AbsenceBalancesPanel({super.key});

  @override
  State<AbsenceBalancesPanel> createState() => _AbsenceBalancesPanelState();
}

class _AbsenceBalancesPanelState extends State<AbsenceBalancesPanel> {
  int _year = DateTime.now().year;
  AbsenceBalances? _balances;
  List<AbsenceType> _types = const [];
  bool _loading = true;
  bool _keeper = false;
  String? _errorKey;

  /// The type whose journal is open below the cards. Null until the balances
  /// arrive, then the first one with something in it.
  String? _openTypeId;

  PagedCubit<AbsenceLedgerEntry>? _entries;

  @override
  void initState() {
    super.initState();
    // Only when there is something to ask for. While the module is off its
    // routes do not exist for this client, and asking anyway answers 404 on
    // every visit to the settings page — the one response that sends the app
    // off to re-read `/api/v1/meta`.
    if (_moduleOn) unawaited(_load());
  }

  bool get _moduleOn =>
      context.read<AppConfigBloc>().state.meta?.absenceManagement ?? false;

  @override
  void dispose() {
    unawaited(_entries?.close());
    super.dispose();
  }

  /// The first read: the year, plus the two answers that do not depend on it.
  Future<void> _load() async {
    final repository = context.read<AbsenceRepository>();
    // Side by side: the catalogue names the rows, the balances fill them, and
    // whether this reader keeps absences decides one link at the bottom.
    final types = repository.types();
    final keeper = repository.isKeeper();
    await _loadBalances();
    if (!mounted) return;
    try {
      final catalogue = await types;
      final keeps = await keeper;
      if (!mounted) return;
      setState(() {
        _types = catalogue;
        _keeper = keeps;
      });
    } on ApiFailure {
      // The balances already said whatever went wrong; a second sentence about
      // the same outage helps nobody.
    }
  }

  /// One year's balances. Neither the catalogue nor "do I keep absences" depends
  /// on the year, so stepping it is one request rather than three.
  Future<void> _loadBalances() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final standing = await context.read<AbsenceRepository>().balances(
        year: _year,
      );
      if (!mounted) return;
      setState(() {
        _balances = standing;
        _loading = false;
      });
      _openJournalFor(_firstInteresting());
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = failure.message;
      });
    }
  }

  /// The type the journal opens on.
  ///
  /// The first one somebody was actually granted; failing that, the first one
  /// that *could* be granted. An unlimited type — sickness, and whatever else an
  /// operator marks that way — has no balance at all, so its journal is empty by
  /// construction, and opening on it shows an empty state that will never fill.
  String? _firstInteresting() {
    final rows = _balances?.balances ?? const <AbsenceBalance>[];
    for (final row in rows) {
      if (row.granted) return row.typeId;
    }
    for (final row in rows) {
      if (!row.unlimited) return row.typeId;
    }
    return rows.firstOrNull?.typeId;
  }

  void _openJournalFor(String? typeId) {
    if (typeId == null) return;
    unawaited(_entries?.close());
    final cubit = PagedCubit<AbsenceLedgerEntry>(
      (page, size) => context.read<AbsenceRepository>().ledger(
        userId: _balances?.userId ?? '',
        typeId: typeId,
        year: _year,
        page: page,
        size: size,
      ),
      pageSize: 50,
      keyOf: (entry) => entry.id,
    );
    setState(() {
      _openTypeId = typeId;
      _entries = cubit;
    });
    unawaited(cubit.load());
  }

  void _moveYear(int by) {
    setState(() => _year += by);
    unawaited(_loadBalances());
  }

  AbsenceType? _typeOf(String typeId) =>
      _types.where((type) => type.id == typeId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final on = context.select<AppConfigBloc, bool>(
      (bloc) => bloc.state.meta?.absenceManagement ?? false,
    );
    if (!on) return const SizedBox.shrink();
    return BlocListener<AppConfigBloc, AppConfigState>(
      // An administrator can switch the module on while somebody has this page
      // open. The panel appears with the flag; the first read follows it here,
      // rather than from inside build().
      listenWhen: (before, after) =>
          (before.meta?.absenceManagement ?? false) !=
          (after.meta?.absenceManagement ?? false),
      listener: (context, state) {
        if ((state.meta?.absenceManagement ?? false) && _balances == null) {
          unawaited(_load());
        }
      },
      child: _panel(context),
    );
  }

  Widget _panel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        if (_loading && _balances == null)
          const Padding(
            padding: EdgeInsets.all(22),
            child: Center(child: HiveLoader(size: 30)),
          )
        else if (_errorKey != null && _balances == null)
          HiveEmptyState(
            title: context.t(_errorKey!),
            card: false,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
            action: OutlinedButton(
              onPressed: () => unawaited(_load()),
              child: Text(context.t('common.retry')),
            ),
          )
        else ...[
          ..._cards(context),
          ..._journal(context),
          if (_keeper) _manageLink(context),
        ],
        Divider(height: 1, color: AppColors.hairline2),
      ],
    );
  }

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t('absence.balances.title'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                context.t('absence.balances.hint'),
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        GlassStepperPill(
          label: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$_year',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: AppColors.ink,
              ),
            ),
          ),
          onBack: () => _moveYear(-1),
          onForward: () => _moveYear(1),
          backTooltip: context.t('absence.entitlements.previousYear'),
          forwardTooltip: context.t('absence.entitlements.nextYear'),
        ),
      ],
    ),
  );

  List<Widget> _cards(BuildContext context) {
    final rows = _balances?.balances ?? const <AbsenceBalance>[];
    if (rows.isEmpty) {
      return [
        HiveEmptyState(
          title: context.t('absence.balances.empty'),
          message: context.t('absence.balances.emptyMessage'),
          card: false,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
        ),
      ];
    }
    return [
      Padding(
        // No side inset of its own. The section already insets its children by
        // 18, and every card adds its own — three nested paddings put the text
        // on a card further right than every other row in the section. The card
        // is the box here, so its padding is the one that counts.
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
        // The cards share the width rather than leaving a ragged edge: as many
        // per row as fit at their smallest, each stretched to fill what is left.
        // In the narrow column of a settings page that is one card, full width.
        child: LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 10.0;
            const min = _BalanceCard.minWidth;
            final columns = ((constraints.maxWidth + spacing) / (min + spacing))
                .floor()
                .clamp(1, 4);
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final row in rows)
                  SizedBox(
                    width: width,
                    child: _BalanceCard(
                      balance: row,
                      type: _typeOf(row.typeId),
                      workingDaysPerWeek: _balances?.workingDaysPerWeek ?? 5,
                      open: row.typeId == _openTypeId,
                      onTap: () => _openJournalFor(row.typeId),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _journal(BuildContext context) {
    final cubit = _entries;
    final typeId = _openTypeId;
    if (cubit == null || typeId == null) return const [];
    final type = _typeOf(typeId);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
        child: Text(
          type == null
              ? context.t('absence.balances.journal')
              : '${context.t('absence.balances.journal')}  ·  '
                    '${absenceTypeName(context, type)}',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.inkSoft,
          ),
        ),
      ),
      BlocProvider.value(
        value: cubit,
        child:
            BlocBuilder<
              PagedCubit<AbsenceLedgerEntry>,
              PagedState<AbsenceLedgerEntry>
            >(
              builder: (context, state) {
                if (state.isLoading && !state.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: HiveLoader(size: 26)),
                  );
                }
                if (state.items.isEmpty) {
                  return HiveEmptyState(
                    title: context.t('absence.balances.journalEmpty'),
                    message: context.t('absence.balances.journalEmptyMessage'),
                    card: false,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  );
                }
                // Built as they scroll into view. A journal grows by fifty rows
                // with every "read on", and a Column would lay out every row
                // anybody ever loaded on every frame of the settings page.
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: ListView.builder(
                    shrinkWrap: true,
                    primary: false,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: state.items.length + (state.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == state.items.length) {
                        return ReadOnTrigger(
                          count: state.items.length,
                          loading: state.isLoadingMore,
                          onReadOn: () => unawaited(cubit.loadMore()),
                        );
                      }
                      return LedgerRow(entry: state.items[index]);
                    },
                  ),
                );
              },
            ),
      ),
    ];
  }

  /// The way into the keeper's pages, for somebody an operator named who is not
  /// an administrator and would otherwise have no entry point at all.
  Widget _manageLink(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton.icon(
        onPressed: () => context.go('/absences/entitlements'),
        icon: const Icon(LucideIcons.usersRound, size: 16),
        label: Text(context.t('absence.balances.manage')),
      ),
    ),
  );
}

/// One type's standing for the year: what is left, out of what, and the two
/// halves of what is gone.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balance,
    required this.type,
    required this.workingDaysPerWeek,
    required this.open,
    required this.onTap,
  });

  final AbsenceBalance balance;
  final AbsenceType? type;
  final int workingDaysPerWeek;
  final bool open;
  final VoidCallback onTap;

  /// The narrowest a card stays readable: the big figure, its label and the two
  /// lines under it.
  static const double minWidth = 232;

  @override
  Widget build(BuildContext context) {
    final colour = absenceColor(context, type?.hue);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Container(
          // Sixteen, so the text inside lands where every other row's text in
          // this section does: the section's own 18 plus this one.
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(
              color: open ? colour : AppColors.hairline2,
              width: open ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(absenceIcon(type?.icon), size: 15, color: colour),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      type == null
                          ? context.t('absence.balances.title')
                          : absenceTypeName(context, type!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ..._figures(context),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _figures(BuildContext context) {
    if (balance.unlimited) {
      return [
        Text(
          context.t('absence.balances.unlimited'),
          style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
        ),
      ];
    }
    if (!balance.granted) {
      return [
        Text(
          context.t('absence.balances.notGranted'),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          context.t('absence.balances.notGrantedHint'),
          style: TextStyle(
            fontSize: 11,
            height: 1.35,
            color: AppColors.textSecondary,
          ),
        ),
      ];
    }
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            days(context, balance.remainingMilliDays),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              context.t('absence.balances.remaining'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        '${context.t('absence.balances.entitled')} '
        '${daysLabel(context, balance.accruedMilliDays)}',
        style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
      ),
      Text(
        '${context.t('absence.balances.taken')} '
        '${days(context, balance.takenMilliDays)}  ·  '
        '${context.t('absence.balances.planned')} '
        '${days(context, balance.plannedMilliDays)}',
        style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
      ),
      if (balance.expiresOn != null) ...[
        const SizedBox(height: 4),
        Text(
          context.t(
            'absence.balances.expiresOn',
            variables: {
              'date': MaterialLocalizations.of(
                context,
              ).formatMediumDate(balance.expiresOn!.toLocal()),
            },
          ),
          style: TextStyle(
            fontSize: 11,
            height: 1.35,
            color: AppColors.textSecondary,
          ),
        ),
      ],
      // § 3 BUrlG, said to the person it is about rather than only to the
      // operator who set it: four weeks of their own working week is the floor,
      // and a quota under it is something to ask about, not something to accept.
      if (balance.belowLegalMinimum) ...[
        const SizedBox(height: 6),
        Text(
          context.t(
            'absence.balances.belowMinimum',
            variables: {
              'days': days(context, balance.legalMinimumMilliDays),
              'week': '$workingDaysPerWeek',
            },
          ),
          style: const TextStyle(
            fontSize: 11,
            height: 1.35,
            color: AppColors.danger,
          ),
        ),
      ],
    ];
  }
}
