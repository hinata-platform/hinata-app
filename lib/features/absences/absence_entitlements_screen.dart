import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/absence_models.dart';
import '../../core/models/core_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_filter_bar.dart' show GlassStepperPill;
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart' show HiveAvatar;
import '../../core/widgets/read_on_trigger.dart';
import '../../core/widgets/soft_card.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart';
import 'absence_entitlement_sheets.dart';
import 'absence_labels.dart';

/// Admin → Entitlements (HIN-116): who has how much of one absence type in one
/// leave year, and everything a keeper does about it.
///
/// **Why a page rather than a card.** The list is the whole organisation, one
/// row per person, and every row carries four numbers and four actions. It is
/// paged and searchable for the same reason the directory is: an instance with
/// two hundred people is the instance where absence management starts to matter.
///
/// **Why one type at a time.** A person's vacation and their training days have
/// different quotas, different accrual and different carryover, and a table that
/// showed all of them at once would be a spreadsheet nobody could grant from.
/// The type is picked once at the top and the whole page follows it.
class AbsenceEntitlementsScreen extends StatefulWidget {
  const AbsenceEntitlementsScreen({super.key});

  @override
  State<AbsenceEntitlementsScreen> createState() =>
      _AbsenceEntitlementsScreenState();
}

class _AbsenceEntitlementsScreenState extends State<AbsenceEntitlementsScreen> {
  /// How many people arrive per page. The server caps it at a hundred.
  static const int _pageSize = 25;

  List<AbsenceType> _types = const [];
  AbsenceType? _type;
  int _year = DateTime.now().year;
  String _query = '';
  bool _loading = true;
  String? _errorKey;

  /// The people ticked for a bulk grant, by id. Cleared whenever the type, the
  /// year or the search changes: a selection that survived a filter change
  /// would be a grant somebody wrote without seeing who was in it.
  final Set<String> _chosen = {};

  /// Names for the rows on screen, so a row reads as a person. The overview
  /// answers with ids — it is about entitlements, not about the directory — and
  /// these are read alongside it.
  final Map<String, DirectoryUser> _people = {};

  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  late final PagedCubit<AbsenceStanding> _standings =
      PagedCubit<AbsenceStanding>(
        (page, size) async {
          final type = _type;
          if (type == null) return (items: <AbsenceStanding>[], total: 0);
          final result = await context.read<AbsenceRepository>().overview(
            typeId: type.id,
            year: _year,
            query: _query,
            page: page,
            size: size,
          );
          // Not awaited: the overview is the page, and the names are a
          // decoration that fills in a moment later. Awaiting it here made
          // every page and every "read on" two round trips end to end.
          unawaited(_readNames(result.items.map((row) => row.userId)));
          return result;
        },
        pageSize: _pageSize,
        keyOf: (row) => row.userId,
      );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    unawaited(_standings.close());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final types = await context.read<AbsenceRepository>().types(
        includeInactive: true,
      );
      if (!mounted) return;
      // Only the types that have something to grant: an unlimited type has no
      // quota and one that does not count against a balance has nothing to
      // count. Picking one of those here would open a page about nothing.
      final grantable = types
          .where((type) => type.countsAgainstBalance && !type.unlimited)
          .toList(growable: false);
      setState(() {
        _types = grantable;
        _type = grantable.firstOrNull;
        _loading = false;
      });
      if (_type != null) unawaited(_standings.load());
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = failure.message;
      });
    }
  }

  /// Fills in the names this page does not have yet, in one request.
  Future<void> _readNames(Iterable<String> ids) async {
    final missing = ids
        .where((id) => !_people.containsKey(id))
        .toSet()
        .toList(growable: false);
    if (missing.isEmpty) return;
    try {
      final found = await context.read<UserRepository>().usersByIds(missing);
      if (!mounted) return;
      setState(() {
        for (final person in found) {
          _people[person.id] = person;
        }
      });
    } catch (_) {
      // A name that cannot be read leaves the row showing an id, which is still
      // a row a keeper can act on. It is not worth an error over a list.
    }
  }

  String _nameOf(String userId) => _people[userId]?.displayName ?? userId;

  void _reload() {
    _chosen.clear();
    unawaited(_standings.load());
  }

  void _pickType(AbsenceType type) {
    setState(() => _type = type);
    _reload();
  }

  void _moveYear(int by) {
    setState(() => _year += by);
    _reload();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    // Long enough that typing a name is one request rather than eight, short
    // enough that the list does not feel like it is thinking about it.
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = text.trim());
      _reload();
    });
  }

  Future<void> _grant(List<String> userIds) async {
    final type = _type;
    if (type == null || userIds.isEmpty) return;
    final granted = await showAbsenceGrantSheet(
      context,
      typeId: type.id,
      typeName: absenceTypeName(context, type),
      year: _year,
      userIds: userIds,
      names: {for (final id in userIds) id: _nameOf(id)},
    );
    if (granted == true && mounted) _reload();
  }

  Future<void> _adjust(AbsenceStanding row) async {
    final type = _type;
    if (type == null) return;
    final booked = await showAbsenceAdjustSheet(
      context,
      userId: row.userId,
      name: _nameOf(row.userId),
      typeId: type.id,
      year: _year,
    );
    if (booked == true && mounted) _reload();
  }

  Future<void> _employment(AbsenceStanding row) async {
    final saved = await showAbsenceEmploymentSheet(
      context,
      userId: row.userId,
      name: _nameOf(row.userId),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _ledger(AbsenceStanding row) async {
    final type = _type;
    if (type == null) return;
    await showAbsenceLedgerSheet(
      context,
      userId: row.userId,
      name: _nameOf(row.userId),
      typeId: type.id,
      year: _year,
    );
  }

  @override
  Widget build(BuildContext context) => PageChrome(
    // One φ² column, published here rather than bounded in the body: the shell
    // lays the sub-page bar out in the same width, so the grant button lands on
    // the rows' own edge.
    contentMax: Breakpoints.mediumMax,
    title: context.t('absence.entitlements.pageTitle'),
    actions: [
      if (_chosen.isNotEmpty)
        PageAction(
          icon: LucideIcons.calendarPlus,
          label: context.t('absence.entitlements.grant'),
          primary: true,
          onTap: (_) => unawaited(_grant(_chosen.toList(growable: false))),
        ),
    ],
    child: _body(context),
  );

  Widget _body(BuildContext context) {
    if (_loading && _types.isEmpty && _errorKey == null) {
      return const Center(child: HiveLoader());
    }
    if (_errorKey != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: HiveEmptyState(
            title: context.t('absence.entitlements.pageTitle'),
            message: context.t(_errorKey!),
            action: OutlinedButton(
              onPressed: () => unawaited(_load()),
              child: Text(context.t('common.retry')),
            ),
          ),
        ),
      );
    }
    if (_types.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: HiveEmptyState(
            title: context.t('absence.entitlements.noTypes'),
            message: context.t('absence.entitlements.noTypesMessage'),
          ),
        ),
      );
    }
    final padding = context.pagePadding;
    return BlocProvider.value(
      value: _standings,
      child:
          BlocBuilder<PagedCubit<AbsenceStanding>, PagedState<AbsenceStanding>>(
            builder: (context, state) => RefreshIndicator(
              onRefresh: () => _standings.load(),
              edgeOffset: context.topGutter,
              // Slivers rather than one Column of rows: the list is the whole
              // organisation, a page at a time, and a concrete child list would
              // build every row an operator ever scrolled past on every frame.
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: padding.copyWith(bottom: 12),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            context.t('absence.entitlements.intro'),
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _controls(context),
                        ],
                      ),
                    ),
                  ),
                  ..._rowSlivers(context, state, padding),
                ],
              ),
            ),
          ),
    );
  }

  /// The rows, or the one thing that stands instead of them.
  List<Widget> _rowSlivers(
    BuildContext context,
    PagedState<AbsenceStanding> state,
    EdgeInsets padding,
  ) {
    final horizontal = padding.copyWith(top: 0, bottom: 0);
    final placeholder = _placeholder(context, state);
    if (placeholder != null) {
      return [
        SliverPadding(
          padding: horizontal.copyWith(bottom: padding.bottom),
          sliver: SliverToBoxAdapter(child: placeholder),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: horizontal,
        sliver: SliverList.builder(
          itemCount: state.items.length,
          itemBuilder: (context, index) {
            final row = state.items[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _StandingCard(
                row: row,
                person: _people[row.userId],
                chosen: _chosen.contains(row.userId),
                onChoose: (value) => setState(() {
                  if (value) {
                    _chosen.add(row.userId);
                  } else {
                    _chosen.remove(row.userId);
                  }
                }),
                onGrant: () => unawaited(_grant([row.userId])),
                onAdjust: () => unawaited(_adjust(row)),
                onLedger: () => unawaited(_ledger(row)),
                onEmployment: () => unawaited(_employment(row)),
              ),
            );
          },
        ),
      ),
      SliverPadding(
        padding: horizontal.copyWith(bottom: padding.bottom),
        sliver: SliverToBoxAdapter(
          child: state.hasMore
              ? ReadOnTrigger(
                  count: state.items.length,
                  loading: state.isLoadingMore,
                  onReadOn: () => unawaited(_standings.loadMore()),
                )
              : const SizedBox.shrink(),
        ),
      ),
    ];
  }

  /// What stands in place of the list while it is loading, refused or empty.
  Widget? _placeholder(
    BuildContext context,
    PagedState<AbsenceStanding> state,
  ) {
    if (state.isLoading && !state.hasData) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: HiveLoader()),
      );
    }
    if (state.errorKey != null && !state.hasData) {
      return HiveEmptyState(
        title: context.t('absence.entitlements.pageTitle'),
        message: context.t(state.errorKey!),
        action: OutlinedButton(
          onPressed: () => unawaited(_standings.load()),
          child: Text(context.t('common.retry')),
        ),
      );
    }
    if (state.items.isEmpty) {
      return HiveEmptyState(
        title: context.t('absence.entitlements.empty'),
        message: context.t('absence.entitlements.emptyMessage'),
      );
    }
    return null;
  }

  Widget _controls(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Builder(
        builder: (anchor) => OutlinedButton.icon(
          icon: Icon(absenceIcon(_type?.icon), size: 16),
          label: Text(_type == null ? '—' : absenceTypeName(context, _type!)),
          onPressed: () async {
            final picked = await showGlassOptions<AbsenceType>(
              context,
              title: context.t('absence.entitlements.type'),
              anchorRect: anchorRectOfContext(anchor),
              options: [
                for (final type in _types)
                  (value: type, child: Text(absenceTypeName(context, type))),
              ],
            );
            if (picked != null && mounted) _pickType(picked);
          },
        ),
      ),
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
      SizedBox(
        width: 240,
        child: TextField(
          controller: _search,
          onChanged: _onSearch,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(LucideIcons.search, size: 16),
            hintText: context.t('absence.entitlements.search'),
          ),
        ),
      ),
      if (_chosen.isNotEmpty)
        Text(
          context.t(
            'absence.entitlements.peopleChosen',
            count: _chosen.length,
            variables: {'count': '${_chosen.length}'},
          ),
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.accentStrong,
          ),
        ),
    ],
  );
}

/// One person's row: who they are, where they stand, and the four things a
/// keeper can do about it.
class _StandingCard extends StatelessWidget {
  const _StandingCard({
    required this.row,
    required this.person,
    required this.chosen,
    required this.onChoose,
    required this.onGrant,
    required this.onAdjust,
    required this.onLedger,
    required this.onEmployment,
  });

  final AbsenceStanding row;
  final DirectoryUser? person;
  final bool chosen;
  final ValueChanged<bool> onChoose;
  final VoidCallback onGrant;
  final VoidCallback onAdjust;
  final VoidCallback onLedger;
  final VoidCallback onEmployment;

  @override
  Widget build(BuildContext context) {
    final name = person?.displayName ?? row.userId;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: chosen,
            onChanged: (value) => onChoose(value ?? false),
            visualDensity: VisualDensity.compact,
          ),
          HiveAvatar(name: name, imageUrl: person?.avatarUrl, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _dates(context),
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                ),
                const SizedBox(height: 8),
                _numbers(context),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _actions(context),
        ],
      ),
    );
  }

  /// Joining and leaving beside the numbers, because they are the reason the
  /// numbers are what they are.
  String _dates(BuildContext context) {
    final formats = MaterialLocalizations.of(context);
    final parts = <String>[
      if (row.hiredOn != null)
        context.t(
          'absence.entitlements.joined',
          variables: {'date': formats.formatMediumDate(row.hiredOn!.toLocal())},
        ),
      if (row.leftOn != null)
        context.t(
          'absence.entitlements.left',
          variables: {'date': formats.formatMediumDate(row.leftOn!.toLocal())},
        ),
    ];
    if (parts.isEmpty) {
      return person?.title ?? context.t('absence.entitlements.notSet');
    }
    return parts.join('  ·  ');
  }

  Widget _numbers(BuildContext context) {
    if (!row.granted) {
      return Text(
        context.t('absence.entitlements.notGranted'),
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.inkSoft,
        ),
      );
    }
    return Wrap(
      spacing: 18,
      runSpacing: 6,
      children: [
        _Figure(
          label: context.t('absence.entitlements.entitled'),
          value: daysLabel(context, row.accruedMilliDays),
        ),
        _Figure(
          label: context.t('absence.entitlements.taken'),
          value: daysLabel(context, row.takenMilliDays),
        ),
        _Figure(
          label: context.t('absence.entitlements.planned'),
          value: daysLabel(context, row.plannedMilliDays),
        ),
        _Figure(
          label: context.t('absence.entitlements.remaining'),
          value: daysLabel(context, row.remainingMilliDays),
          strong: true,
        ),
      ],
    );
  }

  Widget _actions(BuildContext context) => Column(
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!row.granted)
            IconButton(
              tooltip: context.t('absence.entitlements.grant'),
              onPressed: onGrant,
              icon: Icon(
                LucideIcons.calendarPlus,
                size: 17,
                color: AppColors.inkSoft,
              ),
            ),
          IconButton(
            tooltip: context.t('absence.entitlements.adjust'),
            onPressed: onAdjust,
            icon: Icon(LucideIcons.scale, size: 17, color: AppColors.inkSoft),
          ),
          IconButton(
            tooltip: context.t('absence.entitlements.ledger'),
            onPressed: onLedger,
            icon: Icon(
              LucideIcons.scrollText,
              size: 17,
              color: AppColors.inkSoft,
            ),
          ),
          IconButton(
            tooltip: context.t('absence.entitlements.employment'),
            onPressed: onEmployment,
            icon: Icon(
              LucideIcons.calendarClock,
              size: 17,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
    ],
  );
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: AppColors.inkFaint,
        ),
      ),
      const SizedBox(height: 1),
      Text(
        value,
        style: TextStyle(
          fontSize: strong ? 14 : 13,
          fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: strong ? AppColors.accentStrong : AppColors.ink,
        ),
      ),
    ],
  );
}
