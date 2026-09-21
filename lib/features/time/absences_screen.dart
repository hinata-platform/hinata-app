/// Days away, where time is planned: the time module's fifth view (HIN-117).
///
/// Absences used to be entered on the account page, a long way from the
/// calendar they show up in. Here they sit beside the list, the calendar and
/// the timesheet: one's own absences with their balances, searchable and in
/// either order; the requests somebody made and what became of them; and the
/// ones waiting for the reader's decision. The calendar opens the same sheet
/// from the day an absence falls on, so this is a list of the same things, not
/// a second place with its own rules.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/my_absences_cubit.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/blocs/time_policy_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/absence_models.dart';
import '../../core/models/absence_request_models.dart';
import '../../core/models/availability_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/repositories/availability_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_filter_bar.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/glass_scope_row.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart' show PageHead, PrimaryButton;
import '../../core/widgets/soft_card.dart';
import '../absences/absence_actions.dart';
import '../absences/absence_balances_panel.dart';
import '../absences/absence_labels.dart';
import '../absences/absence_request_widgets.dart';
import '../absences/team_absence_calendar.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart';
import 'day_marks.dart' show timeOffIcon;
import 'time_views.dart';

/// The reader's own absences.
const String kAbsenceScopeMine = 'mine';

/// The requests the reader made, and what became of each.
const String kAbsenceScopeRequests = 'requests';

/// The requests waiting for the reader's decision.
const String kAbsenceScopeInbox = 'inbox';

/// This year's entitlements, what is taken, what is planned, and the journal
/// behind each number. A list of its own rather than a block above the
/// absences: it is tall, and it pushed the search and the filters of the list
/// it sat on off the screen.
const String kAbsenceScopeBalances = 'balances';

/// Who in a group is away when (HIN-118). Only while the operator switched the
/// team calendar on; otherwise the pill is not there and the scope falls back.
const String kAbsenceScopeTeam = 'team';

class TimeAbsencesScreen extends StatefulWidget {
  const TimeAbsencesScreen({super.key, this.scope});

  /// Which list the page opens on — a notification about somebody's request
  /// links to [kAbsenceScopeInbox], one about the reader's own to
  /// [kAbsenceScopeRequests].
  final String? scope;

  @override
  State<TimeAbsencesScreen> createState() => _TimeAbsencesScreenState();
}

class _TimeAbsencesScreenState extends State<TimeAbsencesScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _searchDebounce;

  late String _scope = _initialScope();

  late final PagedCubit<TimeOff> _absences;

  /// One per list rather than one that swaps its question: switching between
  /// them and back re-read page one and threw away everything scrolled.
  late final PagedCubit<AbsenceRequest> _myRequests;
  late final PagedCubit<AbsenceRequest> _inbox;

  /// The requests of the list on screen.
  PagedCubit<AbsenceRequest> get _requests =>
      _shownScope == kAbsenceScopeInbox ? _inbox : _myRequests;

  String _query = '';

  /// Whether the phone's docked row shows the search field instead of the
  /// filters. See [GlassSearchDock].
  bool _searching = false;
  DateTimeRange? _range;
  String? _typeId;
  TimeOffType? _plainType;
  bool _oldestFirst = false;

  String? get _meId => context.read<AuthBloc>().state.user?.id;

  /// The list actually on screen. Without absence management there is one —
  /// the absences themselves — and a link from an old notification naming a
  /// scope that does not exist here must not leave the page loading one list
  /// while it draws another.
  String get _shownScope {
    if (!_managed) return kAbsenceScopeMine;
    if (_scope == kAbsenceScopeTeam && !_teamCalendar) return kAbsenceScopeMine;
    return _scope;
  }

  bool get _teamCalendar =>
      context.read<TimePolicyCubit>().state.absenceCalendar.isOn;

  bool get _managed =>
      context.read<AppConfigBloc>().state.meta?.absenceManagement ?? false;

  String _initialScope() {
    final wanted = widget.scope;
    return wanted == kAbsenceScopeRequests ||
            wanted == kAbsenceScopeInbox ||
            wanted == kAbsenceScopeBalances ||
            wanted == kAbsenceScopeTeam
        ? wanted!
        : kAbsenceScopeMine;
  }

  @override
  void initState() {
    super.initState();
    _absences = PagedCubit<TimeOff>(
      (page, size) => context.read<AvailabilityRepository>().timeOff(
        from: _range?.start,
        to: _range?.end,
        query: _query,
        typeId: _typeId,
        type: _plainType,
        oldestFirst: _oldestFirst,
        page: page,
        size: size,
      ),
      pageSize: 30,
      keyOf: (absence) => absence.id ?? absence.from.toIso8601String(),
    );
    _myRequests = PagedCubit<AbsenceRequest>(
      (page, size) =>
          context.read<AbsenceRepository>().myRequests(page: page, size: size),
      pageSize: 25,
      keyOf: (request) => request.id,
    );
    _inbox = PagedCubit<AbsenceRequest>(
      (page, size) =>
          context.read<AbsenceRepository>().inbox(page: page, size: size),
      pageSize: 25,
      keyOf: (request) => request.id,
    );
    _scroll.addListener(_onScroll);
    unawaited(context.read<MyAbsencesCubit>().ensureLoaded(managed: _managed));
    if (_managed) unawaited(context.read<TimePolicyCubit>().ensureLoaded());
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant TimeAbsencesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A notification tapped while the page is open: the route stays, the
    // scope it names changes.
    if (widget.scope != oldWidget.scope) _switchScope(_initialScope());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _searchDebounce?.cancel();
    unawaited(_absences.close());
    unawaited(_myRequests.close());
    unawaited(_inbox.close());
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients ||
        _shownScope == kAbsenceScopeBalances ||
        _shownScope == kAbsenceScopeTeam) {
      return;
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      unawaited(
        _shownScope == kAbsenceScopeMine
            ? _absences.loadMore()
            : _requests.loadMore(),
      );
    }
  }

  Future<void> _reload() => switch (_shownScope) {
    // The balances and the team calendar read themselves, in what draws them.
    kAbsenceScopeBalances || kAbsenceScopeTeam => Future<void>.value(),
    kAbsenceScopeMine => _absences.load(),
    _ => _requests.load(),
  };

  void _switchScope(String scope) {
    if (_scope == scope) return;
    setState(() => _scope = scope);
    // Only a list that has nothing yet: each keeps its own pages, so coming
    // back to one is the rows that were already there, where they were.
    if (scope == kAbsenceScopeBalances || scope == kAbsenceScopeTeam) return;
    final cubit = scope == kAbsenceScopeMine ? _absences : _requests;
    if (!cubit.state.hasData) unawaited(_reload());
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || value.trim() == _query) return;
      setState(() => _query = value.trim());
      unawaited(_absences.load());
    });
  }

  void _applyFilters(VoidCallback change) {
    setState(change);
    unawaited(_absences.load());
  }

  bool get _filtered =>
      _query.isNotEmpty ||
      _range != null ||
      _typeId != null ||
      _plainType != null;

  /// Whether a request that still waits belongs under the filters above it.
  ///
  /// The waiting block and the entered rows are one list to whoever reads the
  /// page, so filtering it to sickness and still finding leave at the top reads
  /// as a broken filter. The server answers the same questions for the entered
  /// rows; these few the page already holds, so it asks them itself.
  bool _matchesFilters(AbsenceRequest request) {
    final typeId = _typeId;
    if (typeId != null && request.typeId != typeId) return false;
    final plain = _plainType;
    if (plain != null && request.typeSystemKey != plain.name) return false;
    final range = _range;
    if (range != null &&
        (request.to.isBefore(DateUtils.dateOnly(range.start)) ||
            request.from.isAfter(DateUtils.dateOnly(range.end)))) {
      return false;
    }
    final query = _query;
    return query.isEmpty ||
        (request.note ?? '').toLowerCase().contains(query.toLowerCase());
  }

  void _clearFilters() {
    _search.clear();
    _applyFilters(() {
      _query = '';
      _range = null;
      _typeId = null;
      _plainType = null;
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showGlassDateRangePicker(
      context,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialRange: _range,
      title: context.t('time.filter.range'),
    );
    if (picked == null || !mounted) return;
    _applyFilters(() => _range = picked);
  }

  Future<void> _pickType(Rect? anchor) async {
    final types = context.read<MyAbsencesCubit>().state.types;
    const all = '';
    final picked = await showGlassOptions<String>(
      context,
      title: context.t('absence.view.type'),
      anchorRect: anchor,
      options: [
        (value: all, child: Text(context.t('absence.view.allTypes'))),
        if (types.isNotEmpty)
          for (final type in types)
            (
              value: 'id:${type.id}',
              child: Row(
                children: [
                  Icon(
                    absenceIcon(type.icon),
                    size: 16,
                    color: absenceColor(context, type.hue),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(absenceTypeName(context, type))),
                ],
              ),
            )
        else
          for (final type in TimeOffType.values)
            (
              value: 'plain:${type.wire}',
              child: Row(
                children: [
                  Icon(timeOffIcon(type), size: 16, color: AppColors.inkSoft),
                  const SizedBox(width: 10),
                  Expanded(child: Text(context.t(type.labelKey))),
                ],
              ),
            ),
      ],
    );
    if (picked == null || !mounted) return;
    _applyFilters(() {
      _typeId = picked.startsWith('id:') ? picked.substring(3) : null;
      _plainType = picked.startsWith('plain:')
          ? TimeOffType.fromWire(picked.substring(6))
          : null;
    });
  }

  String _typeFilterLabel(BuildContext context) {
    final typeId = _typeId;
    if (typeId != null) {
      final type = context
          .read<MyAbsencesCubit>()
          .state
          .types
          .where((type) => type.id == typeId)
          .firstOrNull;
      if (type != null) return absenceTypeName(context, type);
    }
    final plain = _plainType;
    if (plain != null) return context.t(plain.labelKey);
    return context.t('absence.view.allTypes');
  }

  Future<void> _decide(
    Future<AbsenceRequest> Function() step,
    String doneKey,
  ) async {
    try {
      await step();
      if (!mounted) return;
      showGlassToast(context, context.t(doneKey));
      unawaited(context.read<MyAbsencesCubit>().changed());
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      showGlassErrorToast(context, context.t(failure.message));
    }
  }

  Future<void> _reject(AbsenceRequest request) async {
    final reason = await showAbsenceReasonSheet(
      context,
      titleKey: 'absence.request.rejectTitle',
      required: true,
    );
    if (reason == null || !mounted) return;
    await _decide(
      () => context.read<AbsenceRepository>().reject(request.id, note: reason),
      'absence.request.rejected',
    );
  }

  /// Cancels approved leave that is still ahead; the reason is optional.
  Future<void> _cancel(AbsenceRequest request) async {
    final reason = await showAbsenceReasonSheet(
      context,
      titleKey: 'absence.request.cancelTitle',
      required: false,
    );
    if (reason == null || !mounted) return;
    await _decide(
      () => context.read<AbsenceRepository>().cancel(
        request.id,
        note: reason.isEmpty ? null : reason,
      ),
      'absence.request.cancelled',
    );
  }

  // --- drawing ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final managed = context.select<AppConfigBloc, bool>(
      (bloc) => bloc.state.meta?.absenceManagement ?? false,
    );
    // Read here so the pill appears as soon as the policy arrives.
    final team = context.select<TimePolicyCubit, bool>(
      (cubit) => cubit.state.absenceCalendar.isOn,
    );
    return BlocListener<MyAbsencesCubit, MyAbsencesState>(
      // Something of the reader's changed — from here, from the calendar's
      // sheet, from a "+" anywhere — and the lists on this page show it.
      listenWhen: (before, after) => before.revision != after.revision,
      listener: (context, state) => unawaited(_reload()),
      child: PageChrome(
        contentMax: double.infinity,
        onTitleTap: compact
            ? (anchor) => unawaited(
                showTimeViewMenu<Never>(
                  context,
                  anchor: anchor,
                  current: TimeView.absences,
                ),
              )
            : null,
        titleLeading: true,
        actions: compact
            ? [
                PageAction(
                  icon: LucideIcons.plus,
                  label: context.t('time.add.title'),
                  primary: true,
                  onTap: (anchor) => unawaited(_addMenu(anchor)),
                ),
              ]
            : const [],
        bottom: compact && managed ? _scopeRow(team) : null,
        bottomHeight: compact && managed ? kGlassDockRow : 0,
        child: compact
            ? _body(managed)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      context.pageGutter,
                      18 + context.topGutter,
                      context.pageGutter,
                      12,
                    ),
                    child: PageHead(
                      title: context.t('nav.time'),
                      actions: [
                        const TimeViewSwitcher(current: TimeView.absences),
                        const SizedBox(width: 8),
                        PrimaryButton(
                          icon: LucideIcons.calendarPlus,
                          label: context.t(
                            managed
                                ? 'absence.request.ask'
                                : 'availability.timeOff.add',
                          ),
                          onPressed: () => unawaited(askForAbsence(context)),
                          collapseToIcon: true,
                        ),
                      ],
                    ),
                  ),
                  if (managed)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        context.pageGutter,
                        0,
                        context.pageGutter,
                        12,
                      ),
                      child: _scopeRow(team),
                    ),
                  Expanded(child: _body(managed)),
                ],
              ),
      ),
    );
  }

  Future<void> _addMenu(Rect? anchor) async {
    if (anchor == null) return;
    final chosen = await showGlassMenu<String>(
      context: context,
      anchorRect: anchor,
      width: 240,
      value: '',
      items: absenceMenuItems(context, managed: _managed),
    );
    if (chosen == null || !mounted) return;
    await followAbsenceChoice(context, chosen);
  }

  /// The lists, each a glass pill of its own, as on the approvals page. The
  /// team calendar joins them only while it exists.
  Widget _scopeRow(bool team) => GlassScopeRow(
    scopes: [
      for (final (scope, icon) in [
        (kAbsenceScopeMine, LucideIcons.calendarOff),
        (kAbsenceScopeRequests, LucideIcons.listChecks),
        (kAbsenceScopeInbox, LucideIcons.inbox),
        (kAbsenceScopeBalances, LucideIcons.wallet),
        if (team) (kAbsenceScopeTeam, LucideIcons.usersRound),
      ])
        (
          key: scope,
          icon: icon,
          label: context.t('absence.view.scope.$scope'),
        ),
    ],
    active: _shownScope,
    onSelected: _switchScope,
  );

  /// The gap over the first row of the list.
  ///
  /// On a phone the scopes are docked into the app bar and the filters are the
  /// line right under them, so the two read as one head. A full gutter between
  /// them pushed the filters a finger's width away from the pills they belong
  /// with; 6 points leave them as close together as the title and the scopes
  /// above. Without the dock (module off) the ordinary gutter stands.
  EdgeInsets _padding() => EdgeInsets.fromLTRB(
    context.pageGutter,
    context.isCompact
        ? context.topGutter + (_managed ? 6 : context.pageGutter)
        : 0,
    context.pageGutter,
    context.pageGutter + context.bottomGutter,
  );

  Widget _body(bool managed) {
    final padding = _padding();
    return RefreshIndicator(
      onRefresh: () async {
        await context.read<MyAbsencesCubit>().changed();
      },
      edgeOffset: context.topGutter,
      child: switch (_shownScope) {
        kAbsenceScopeMine => _mine(padding, managed),
        kAbsenceScopeBalances => _balances(padding),
        kAbsenceScopeTeam => TeamAbsenceCalendar(padding: padding),
        _ => _requestList(padding),
      },
    );
  }

  // --- mine ---------------------------------------------------------------------

  Widget _mine(EdgeInsets padding, bool managed) {
    final horizontal = padding.copyWith(top: 0, bottom: 0);
    return BlocProvider.value(
      value: _absences,
      child: BlocBuilder<PagedCubit<TimeOff>, PagedState<TimeOff>>(
        builder: (context, state) => CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(padding: EdgeInsets.only(top: padding.top)),
            SliverPadding(
              padding: horizontal.copyWith(bottom: 12),
              sliver: SliverToBoxAdapter(child: _filters()),
            ),
            if (managed) ..._pending(horizontal),
            ..._absenceRows(state, horizontal, managed),
            SliverPadding(
              padding: horizontal.copyWith(bottom: padding.bottom),
              sliver: SliverToBoxAdapter(
                child: state.isLoadingMore
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: HiveLoader(size: 26)),
                      )
                    : const SizedBox(height: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The balances, on their own list. It carries the whole panel — the cards,
  /// the journal and, for a keeper, the way to the entitlements and the types.
  Widget _balances(EdgeInsets padding) => ListView(
    controller: _scroll,
    padding: padding,
    children: const [
      SoftCard(padding: EdgeInsets.zero, child: AbsenceBalancesPanel()),
    ],
  );

  /// The page's tools. On a phone they are one docked line — the search takes
  /// the row over only while somebody types in it, the way the list's do; a
  /// field above a row of pills put three lines of chrome over the first
  /// absence. On a wide window they lay out and wrap.
  Widget _filters() => context.isCompact
      ? Align(
          alignment: AlignmentDirectional.centerStart,
          child: GlassSearchDock(
            searching: _searching,
            controller: _search,
            hint: context.t('absence.view.search'),
            onChanged: _onSearchChanged,
            onClose: () => setState(() => _searching = false),
            controls: SizedBox(
              height: kGlassControlHeight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // The gutter is spent outside; inside it would clip the last
                // pill rather than let it scroll into view.
                clipBehavior: Clip.none,
                child: Row(
                  children: [
                    GlassSearchButton(
                      tooltip: context.t('absence.view.search'),
                      active: _query.isNotEmpty,
                      onTap: () => setState(() => _searching = true),
                    ),
                    for (final pill in _filterPills()) ...[
                      const SizedBox(width: 8),
                      pill,
                    ],
                  ],
                ),
              ),
            ),
          ),
        )
      : Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: GlassSearchField(
                controller: _search,
                hint: context.t('absence.view.search'),
                onChanged: _onSearchChanged,
              ),
            ),
            ..._filterPills(),
          ],
        );

  List<Widget> _filterPills() {
    final localizations = MaterialLocalizations.of(context);
    final range = _range;
    return [
      GlassFilterPill(
        icon: LucideIcons.calendarRange,
        label: range == null
            ? context.t('time.filter.allTime')
            : '${localizations.formatShortDate(range.start)} – '
                  '${localizations.formatShortDate(range.end)}',
        active: range != null,
        onTap: (_) => unawaited(_pickRange()),
      ),
      GlassFilterPill(
        icon: LucideIcons.tag,
        label: _typeFilterLabel(context),
        active: _typeId != null || _plainType != null,
        onTap: (anchor) => unawaited(_pickType(anchor)),
      ),
      GlassFilterPill(
        icon: LucideIcons.arrowDownUp,
        label: context.t(
          _oldestFirst
              ? 'absence.view.oldestFirst'
              : 'absence.view.newestFirst',
        ),
        active: _oldestFirst,
        chevron: false,
        onTap: (_) => _applyFilters(() => _oldestFirst = !_oldestFirst),
      ),
      if (_filtered) GlassClearFiltersPill(onTap: _clearFilters),
    ];
  }

  /// What waits for a decision, above what is settled — it is the part that
  /// may still change, and the part somebody opens this page to look for.
  List<Widget> _pending(EdgeInsets horizontal) {
    final mine = context.watch<MyAbsencesCubit>().state;
    final waiting = mine.pending.where(_matchesFilters).toList();
    if (waiting.isEmpty) return const [];
    return [
      SliverPadding(
        padding: horizontal.copyWith(bottom: 8),
        sliver: SliverToBoxAdapter(
          child: _SectionTitle(
            text: context.t('absence.view.pending'),
            count: waiting.length,
          ),
        ),
      ),
      SliverPadding(
        padding: horizontal.copyWith(bottom: 12),
        sliver: SliverList.builder(
          itemCount: waiting.length,
          itemBuilder: (context, index) {
            final request = waiting[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AbsenceRequestCard(
                request: request,
                type: mine.types
                    .where((type) => type.id == request.typeId)
                    .firstOrNull,
                inbox: false,
                isMine: true,
                onOpen: () => unawaited(
                  openAbsence(context, AbsenceTarget.requested(request)),
                ),
                onWithdraw: () => unawaited(
                  _decide(
                    () =>
                        context.read<AbsenceRepository>().withdraw(request.id),
                    'absence.request.withdrawn',
                  ),
                ),
              ),
            );
          },
        ),
      ),
      SliverPadding(
        padding: horizontal.copyWith(bottom: 8),
        sliver: SliverToBoxAdapter(
          child: _SectionTitle(text: context.t('absence.view.settled')),
        ),
      ),
    ];
  }

  List<Widget> _absenceRows(
    PagedState<TimeOff> state,
    EdgeInsets horizontal,
    bool managed,
  ) {
    if (state.isLoading && state.items.isEmpty) {
      return [
        SliverPadding(
          padding: horizontal,
          sliver: const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: HiveLoader()),
            ),
          ),
        ),
      ];
    }
    if (state.errorKey != null && state.items.isEmpty) {
      return [
        SliverPadding(
          padding: horizontal,
          sliver: SliverToBoxAdapter(
            child: HiveEmptyState(
              title: context.t('absence.view.title'),
              message: context.t(state.errorKey!),
              action: OutlinedButton(
                onPressed: () => unawaited(_absences.load()),
                child: Text(context.t('common.retry')),
              ),
            ),
          ),
        ),
      ];
    }
    if (state.items.isEmpty) {
      return [
        SliverPadding(
          padding: horizontal,
          sliver: SliverToBoxAdapter(
            child: HiveEmptyState(
              title: context.t(
                _filtered ? 'absence.view.noMatch' : 'absence.view.empty.mine',
              ),
              message: context.t(
                _filtered
                    ? 'absence.view.noMatchMessage'
                    : 'absence.view.emptyMessage.mine',
              ),
              action: _filtered
                  ? OutlinedButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(LucideIcons.filterX, size: 16),
                      label: Text(context.t('absence.view.clearFilters')),
                    )
                  : FilledButton.icon(
                      onPressed: () => unawaited(askForAbsence(context)),
                      icon: const Icon(LucideIcons.calendarPlus, size: 16),
                      label: Text(
                        context.t(
                          managed
                              ? 'absence.request.ask'
                              : 'availability.timeOff.add',
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ];
    }
    final types = context.watch<MyAbsencesCubit>().state.types;
    return [
      SliverPadding(
        padding: horizontal,
        sliver: SliverList.builder(
          itemCount: state.items.length,
          itemBuilder: (context, index) {
            final absence = state.items[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AbsenceRow(
                absence: absence,
                type: types
                    .where((type) => type.id == absence.typeId)
                    .firstOrNull,
                onTap: () => unawaited(
                  openAbsence(context, AbsenceTarget.entered(absence)),
                ),
              ),
            );
          },
        ),
      ),
    ];
  }

  // --- requests and the inbox -----------------------------------------------------

  Widget _requestList(EdgeInsets padding) {
    final horizontal = padding.copyWith(top: 0, bottom: 0);
    final inbox = _shownScope == kAbsenceScopeInbox;
    return BlocProvider.value(
      value: _requests,
      child:
          BlocBuilder<PagedCubit<AbsenceRequest>, PagedState<AbsenceRequest>>(
            builder: (context, state) {
              final types = context.watch<MyAbsencesCubit>().state.types;
              final slivers = <Widget>[
                SliverPadding(padding: EdgeInsets.only(top: padding.top)),
              ];
              if (state.isLoading && state.items.isEmpty) {
                slivers.add(
                  SliverPadding(
                    padding: horizontal,
                    sliver: const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: HiveLoader()),
                      ),
                    ),
                  ),
                );
              } else if (state.items.isEmpty) {
                slivers.add(
                  SliverPadding(
                    padding: horizontal,
                    sliver: SliverToBoxAdapter(
                      child: HiveEmptyState(
                        title: context.t('absence.view.empty.$_shownScope'),
                        message: context.t(
                          'absence.view.emptyMessage.$_shownScope',
                        ),
                        action: inbox
                            ? null
                            : FilledButton.icon(
                                onPressed: () =>
                                    unawaited(askForAbsence(context)),
                                icon: const Icon(
                                  LucideIcons.calendarPlus,
                                  size: 16,
                                ),
                                label: Text(context.t('absence.request.ask')),
                              ),
                      ),
                    ),
                  ),
                );
              } else {
                slivers.add(
                  SliverPadding(
                    padding: horizontal,
                    sliver: SliverList.builder(
                      itemCount: state.items.length,
                      itemBuilder: (context, index) {
                        final request = state.items[index];
                        final repository = context.read<AbsenceRepository>();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AbsenceRequestCard(
                            request: request,
                            type: types
                                .where((type) => type.id == request.typeId)
                                .firstOrNull,
                            inbox: inbox,
                            isMine: request.userId == _meId,
                            onOpen: () => unawaited(
                              openAbsence(
                                context,
                                AbsenceTarget.requested(request),
                              ),
                            ),
                            onApprove: () => unawaited(
                              _decide(
                                () => repository.approve(request.id),
                                'absence.request.approved',
                              ),
                            ),
                            onReject: () => unawaited(_reject(request)),
                            onWithdraw: () => unawaited(
                              _decide(
                                () => repository.withdraw(request.id),
                                'absence.request.withdrawn',
                              ),
                            ),
                            onCancel: () => unawaited(_cancel(request)),
                          ),
                        );
                      },
                    ),
                  ),
                );
              }
              slivers.add(
                SliverPadding(
                  padding: horizontal.copyWith(bottom: padding.bottom),
                  sliver: SliverToBoxAdapter(
                    child: state.isLoadingMore
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: HiveLoader(size: 26)),
                          )
                        : const SizedBox(height: 8),
                  ),
                ),
              );
              return CustomScrollView(controller: _scroll, slivers: slivers);
            },
          ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, this.count});

  final String text;
  final int? count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.inkSoft,
        ),
      ),
      if (count != null) ...[
        const SizedBox(width: 6),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.accentInk,
          ),
        ),
      ],
    ],
  );
}

/// One absence in a list: what it is, when, and whether it came from a request.
class AbsenceRow extends StatelessWidget {
  const AbsenceRow({
    super.key,
    required this.absence,
    required this.type,
    required this.onTap,
  });

  final TimeOff absence;

  /// The operator's type it was entered under, when the catalogue has it.
  final AbsenceType? type;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = this.type;
    final name = type == null
        ? context.t(absence.type.labelKey)
        : absenceTypeName(context, type);
    final note = absence.note;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            type == null ? timeOffIcon(absence.type) : absenceIcon(type.icon),
            size: 18,
            color: type == null
                ? AppColors.inkSoft
                : absenceColor(context, type.hue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    spanLabel(context, absence.from, absence.to),
                    if (absence.halfDay) context.t('absence.sheet.halfDay'),
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (note != null && note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (absence.fromRequest)
            const AbsenceStatusChip(status: AbsenceRequestStatus.approved)
          else
            AbsenceEnteredChip(sick: absence.type == TimeOffType.sick),
        ],
      ),
    );
  }
}
