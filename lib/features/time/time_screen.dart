import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/blocs/time_policy_cubit.dart';
import '../../core/blocs/timer_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_models.dart';
import '../../core/models/time_approval_models.dart';
import '../../core/models/time_policy_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/time_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_filter_bar.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../issues/work_item_labels.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart'
    show
        GlassToastKind,
        anchorRectOfContext,
        showGlassConfirm,
        showGlassDateRangePicker,
        showGlassToast;
import 'lock_notice.dart';
import 'placement_picker.dart';
import 'time_entry_history_sheet.dart';
import 'time_entry_sheet.dart';
import 'time_views.dart';
import 'timer_bar.dart';

/// The module's home: what this person has tracked, newest first, with the
/// timer above it.
///
/// Only their own entries — the server offers no way to ask for anyone else's
/// here, and that is the point rather than a limitation. Reading somebody
/// else's hours is what the timesheet and the reports are for, each with a rule
/// of its own; this page is "my time", which is what R2 of the epic makes the
/// default.
class TimeScreen extends StatefulWidget {
  const TimeScreen({super.key});

  @override
  State<TimeScreen> createState() => _TimeScreenState();
}

class _TimeScreenState extends State<TimeScreen> {
  final _scroll = ScrollController();
  late final PagedCubit<WorkItem> _entries;
  final _searchController = TextEditingController();

  TimeEntryFilter _filter = const TimeEntryFilter();
  Timer? _searchDebounce;

  /// Whether the phone's docked row is showing the search field instead of the
  /// filters. See [GlassSearchDock] — the band above a page holds two lines,
  /// and a field plus a row of filters is one too many.
  bool _searching = false;

  /// Names for exactly the projects the loaded rows mention. Never the whole
  /// catalogue: an instance can hold hundreds, and a page of entries names a
  /// handful.
  Map<String, Project> _projects = const {};

  @override
  void initState() {
    super.initState();
    _entries = PagedCubit<WorkItem>(
      (page, size) => context.read<TimeRepository>().entries(
        filter: _filter,
        page: page,
        size: size,
      ),
      pageSize: 50,
      keyOf: (entry) => entry.id,
    );
    _scroll.addListener(_onScroll);
    // The operator's rules, once. Without this the list holds
    // TimePolicySnapshot.none for the whole session: nothing is ever marked
    // frozen, and the lock a person would run into on save is invisible until
    // they hit it.
    unawaited(context.read<TimePolicyCubit>().ensureLoaded());
    unawaited(_reload());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.dispose();
    _searchController.dispose();
    unawaited(_entries.close());
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      unawaited(_entries.loadMore());
    }
  }

  Future<void> _reload() async {
    await _entries.load();
    if (mounted) unawaited(_resolveProjects());
  }

  /// Labels for the project ids on screen. A failure keeps whatever labels are
  /// already held rather than blanking the chips: a name that could not be
  /// fetched is still better shown as the last one known than as nothing.
  Future<void> _resolveProjects() async {
    final ids = {
      for (final entry in _entries.state.items)
        if (entry.projectId != null) entry.projectId!,
    }..removeWhere(_projects.containsKey);
    if (ids.isEmpty) return;
    try {
      final resolved = await context.read<ProjectRepository>().resolveProjects(
        ids.toList(),
      );
      if (!mounted) return;
      setState(
        () => _projects = {
          ..._projects,
          for (final project in resolved) project.id: project,
        },
      );
    } catch (_) {
      // Keep the labels we have.
    }
  }

  void _applyFilter(TimeEntryFilter filter) {
    setState(() => _filter = filter);
    unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    // The shell draws a title and actions only for a *sub*-page, and this is a
    // nav destination — so on a wide window a PageChrome title would never
    // appear. A top-level page wears its own head, as Reports, Gantt and the
    // timesheet do.
    return PageChrome(
      fullWidth: true,
      // The way between the module's three pages, where the calendar keeps it
      // too: a phone's app bar has room for one trailing action, and that one
      // is "new entry".
      onTitleTap: compact ? _openModuleMenu : null,
      // Left, like the calendar's and the timesheet's. The module's three
      // pages are one place seen three ways, and a title that jumps from the
      // centre to the edge as you step between them reads as three places. It
      // is also the edge the chevron belongs on: a centred title with a
      // control after it is a control nobody finds twice in the same spot.
      titleLeading: true,
      // Compact only: this is a nav destination, so a wide window builds no
      // sub-page bar and would drop the action on the floor. A wide window
      // offers the two ways of adding time separately — the entry button in
      // the page's own head, the timer on the bar beside it — and this one
      // slot cannot, which is why the phone's button asks which.
      actions: compact
          ? [
              PageAction(
                icon: LucideIcons.plus,
                label: context.t('time.add.title'),
                primary: true,
                onTap: (anchor) => unawaited(
                  showTimeAddMenu(
                    context,
                    anchor: anchor,
                    onNewEntry: _newEntry,
                    onTimerStopped: _reload,
                  ),
                ),
              ),
            ]
          : const [],
      // On a phone the filters ride as glass pills inside the app bar's blur
      // rather than as fields down the page: laid out in the body they would
      // cost a third of the screen before the first entry is visible.
      bottom: compact ? _dockedFilters() : null,
      bottomHeight: compact ? _kDockHeight : 0,
      child: BlocProvider.value(
        value: _entries,
        // A stop files an entry, and the list has to show it — whichever bar
        // pressed the button. On a phone the bar floats in the shell and knows
        // nothing about this page, so listening for the transition here is what
        // makes the two layouts behave the same.
        child: BlocListener<TimerCubit, TimerState>(
          listenWhen: (previous, current) =>
              previous.isRunning && !current.isRunning,
          listener: (context, state) => unawaited(_reload()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!compact) ...[
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
                      const TimeViewSwitcher(current: TimeView.list),
                      const SizedBox(width: 8),
                      PrimaryButton(
                        icon: LucideIcons.plus,
                        label: context.t('time.entry.new'),
                        onPressed: _newEntry,
                        collapseToIcon: true,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.pageGutter,
                    0,
                    context.pageGutter,
                    12,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: TimerBar(onStopped: _reload),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.pageGutter,
                    0,
                    context.pageGutter,
                    10,
                  ),
                  child: _wideFilters(),
                ),
              ],
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
                  child: _list(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The phone's one docked line, in the band the app bar is already blurring.
  ///
  /// One line, not two. It used to be a search field with the filter pills
  /// under it, which — counting the app bar's own title row — put three lines
  /// of chrome above the first entry. The field is now a pill like the rest and
  /// takes the row over only while somebody is typing in it.
  Widget _dockedFilters() {
    final gutter = context.pageGutter;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      // The `Align` is load-bearing vertically: the bar hands the reserved
      // height down as a *tight* constraint, and the row has to be able to come
      // in under it. Its horizontal half is not a detail either — the row sizes
      // to its pills, so a centred one drifts away from the page's leading edge
      // as pills are added and removed, under a title that does not move.
      // Directional, so a right-to-left reading starts where its reader does.
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: GlassSearchDock(
          searching: _searching,
          controller: _searchController,
          hint: context.t('time.filter.search'),
          onChanged: _onSearchChanged,
          onClose: () => setState(() => _searching = false),
          controls: SizedBox(
            height: kGlassControlHeight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // The gutter is already spent above; inside the scroller it would
              // clip the last pill instead of letting it come into view.
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  GlassSearchButton(
                    tooltip: context.t('time.filter.search'),
                    active: _filter.query?.isNotEmpty ?? false,
                    onTap: () => setState(() => _searching = true),
                  ),
                  const SizedBox(width: 8),
                  ..._filterPills(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openModuleMenu(Rect? anchor) => unawaited(
    showTimeViewMenu<Never>(context, anchor: anchor, current: TimeView.list),
  );

  /// The same controls on a wide window, wrapping rather than scrolling —
  /// there is room for them in one line at most widths, and a second line when
  /// there is not.
  Widget _wideFilters() => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        width: 260,
        child: GlassSearchField(
          controller: _searchController,
          hint: context.t('time.filter.search'),
          onChanged: _onSearchChanged,
        ),
      ),
      // The gaps in _filterPills are the scroller's business; a Wrap spaces
      // its own children.
      ..._filterPills().whereType<_FilterPill>(),
      if (!_filter.isEmpty)
        _ClearFiltersPill(
          onTap: () {
            _searchController.clear();
            _applyFilter(const TimeEntryFilter());
          },
        ),
    ],
  );

  List<Widget> _filterPills() {
    final localizations = MaterialLocalizations.of(context);
    return [
      _FilterPill(
        icon: LucideIcons.calendarRange,
        label: _filter.from == null || _filter.to == null
            ? context.t('time.filter.allTime')
            : '${localizations.formatShortDate(_filter.from!)} – '
                  '${localizations.formatShortDate(_filter.to!)}',
        active: _filter.from != null,
        onTap: (_) => _pickRange(),
      ),
      const SizedBox(width: 8),
      _FilterPill(
        icon: LucideIcons.folder,
        label: _filter.projectId == null
            ? context.t('time.filter.allProjects')
            : _projects[_filter.projectId]?.name ??
                  context.t('time.placement.assigned'),
        active: _filter.projectId != null,
        onTap: _pickProjectFilter,
      ),
      // One pill to undo them all, rather than a clear button inside each —
      // an icon button nested in a pill makes the pill chunky and puts a second
      // tap target inside the first.
      if (!_filter.isEmpty) ...[
        const SizedBox(width: 8),
        _ClearFiltersPill(
          onTap: () {
            _searchController.clear();
            _applyFilter(const TimeEntryFilter());
          },
        ),
      ],
    ];
  }

  /// The date range, in the app's date-range dialog.
  ///
  /// No anchor: a two-month calendar is a dialog everywhere in this app, and
  /// hanging one off a filter pill would put a 400-point panel over the page it
  /// is filtering. The pill beside it opens a searchable list, which is what a
  /// popover is for.
  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showGlassDateRangePicker(
      context,
      firstDate: DateTime(now.year - 3, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
      initialRange: _filter.from != null && _filter.to != null
          ? DateTimeRange(start: _filter.from!, end: _filter.to!)
          : null,
      title: context.t('time.filter.range'),
    );
    if (range == null || !mounted) return;
    _applyFilter(_filter.copyWith(from: range.start, to: range.end));
  }

  Future<void> _pickProjectFilter(Rect? anchor) async {
    final picked = await showTimePlacementPicker(
      context,
      anchorRect: anchor,
      current: TimePlacement(projectId: _filter.projectId),
      // The filter narrows by project; an issue row would silently collapse to
      // its project, and "no project" here means "clear the filter" rather than
      // "unfiled entries only".
      projectsOnly: true,
    );
    if (picked == null || !mounted) return;
    _applyFilter(
      picked.projectId == null
          ? _filter.copyWith(clearProject: true)
          : _filter.copyWith(projectId: picked.projectId),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _applyFilter(
        value.trim().isEmpty
            ? _filter.copyWith(clearQuery: true)
            : _filter.copyWith(query: value.trim()),
      );
    });
  }

  /// What the body has to leave clear at the top.
  ///
  /// On a phone the body scrolls *under* the glass app bar — which is also
  /// carrying this page's docked search and filters — and the shell hands that
  /// height over as [BuildContext.topGutter] rather than reserving it, so the
  /// page spends it itself. On a wide window the head, the timer and the filters
  /// sit above the body in the column and have already spent it.
  ///
  /// Without it the day this list opens on is behind the header: not clipped,
  /// which would at least look broken, but blurred into the bar — so the page
  /// reads as an empty screen with a smear of something above it.
  double _bodyTopInset(BuildContext context) =>
      context.isCompact ? context.topGutter : 0;

  /// A state that is not a list: below the header, hugging its own content, on
  /// a surface that can still be pulled to refresh.
  ///
  /// In a scroll view rather than straight into the column, for two reasons a
  /// [HiveEmptyState] makes plain. Given a tight height its card fills it — on a
  /// phone that is one empty rectangle from the toolbar down past the
  /// navigation, which reads as a broken page rather than an empty one. And an
  /// empty page is exactly where a reader reaches for pull-to-refresh, which a
  /// fixed child cannot offer them.
  Widget _placeholder(Widget child) => RefreshIndicator(
    onRefresh: _reload,
    edgeOffset: _bodyTopInset(context),
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        0,
        _bodyTopInset(context) + 24,
        0,
        context.bottomGutter + 24,
      ),
      children: [child],
    ),
  );

  Widget _list() {
    // Watched here, above the builder, rather than inside it: the context an
    // itemBuilder is handed belongs to the sliver that owns every row, so the
    // dependency would land there and one emit would rebuild the whole list —
    // and the lookup would run again for every row the scroll materialises.
    final policy = context.watch<TimePolicyCubit>().state;
    return BlocBuilder<PagedCubit<WorkItem>, PagedState<WorkItem>>(
      builder: (context, state) {
        if (state.isLoading && !state.hasData) {
          // Not a placeholder card: a spinner has nothing to refresh yet, and
          // it belongs in the middle of the page a reader is waiting on.
          return Padding(
            padding: EdgeInsets.only(top: _bodyTopInset(context)),
            child: const Center(child: HiveLoader(size: 44)),
          );
        }
        if (state.errorKey != null && !state.hasData) {
          return _placeholder(
            HiveEmptyState(
              title: context.t('time.error.title'),
              message: context.t(state.errorKey!),
              action: FilledButton.icon(
                onPressed: _reload,
                icon: const Icon(LucideIcons.refreshCw, size: 15),
                label: Text(context.t('common.retry')),
              ),
            ),
          );
        }
        if (state.items.isEmpty) {
          return _placeholder(
            HiveEmptyState(
              title: context.t(
                _filter.isEmpty ? 'time.empty.title' : 'time.empty.filtered',
              ),
              message: context.t(
                _filter.isEmpty ? 'time.empty.message' : 'time.empty.tryOther',
              ),
              action: _filter.isEmpty
                  ? FilledButton.icon(
                      onPressed: _newEntry,
                      icon: const Icon(LucideIcons.plus, size: 15),
                      label: Text(context.t('time.entry.new')),
                    )
                  : TextButton.icon(
                      onPressed: () {
                        _searchController.clear();
                        _applyFilter(const TimeEntryFilter());
                      },
                      icon: const Icon(LucideIcons.x, size: 15),
                      label: Text(context.t('common.clear')),
                    ),
            ),
          );
        }
        final groups = _groupByDay(state.items);
        return RefreshIndicator(
          onRefresh: _reload,
          // Where the spinner drops from. Without it the refresh indicator
          // appears behind the glass bar, which on a phone is most of the way
          // to invisible.
          edgeOffset: _bodyTopInset(context),
          child: ListView.builder(
            controller: _scroll,
            padding: EdgeInsets.only(
              top: _bodyTopInset(context),
              bottom: context.bottomGutter + 24,
            ),
            itemCount: groups.length + (state.isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= groups.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: HiveLoader(size: 28)),
                );
              }
              final group = groups[index];
              return _DayGroup(
                day: group.day,
                entries: group.entries,
                projects: _projects,
                // The last group of a list that has more pages is the one day
                // whose entries are not all here, so its total would be the sum
                // of what happens to be loaded — presented identically to a
                // complete day's. It shows none until the day is whole.
                showTotal: !(state.hasMore && index == groups.length - 1),
                onEdit: _editEntry,
                onDelete: _deleteEntry,
                onContinue: _continueEntry,
                onHistory: _showHistory,
                policy: policy,
              );
            },
          ),
        );
      },
    );
  }

  /// The loaded rows, cut into days.
  ///
  /// Built from what is on screen, not asked of the server: the list arrives
  /// sorted by day already, so grouping is a walk. The last group of a list
  /// with more pages carries no total — see [_DayGroup.showTotal].
  List<({DateTime day, List<WorkItem> entries})> _groupByDay(
    List<WorkItem> entries,
  ) {
    final groups = <({DateTime day, List<WorkItem> entries})>[];
    for (final entry in entries) {
      final date = entry.date;
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      if (groups.isNotEmpty && groups.last.day == day) {
        groups.last.entries.add(entry);
      } else {
        groups.add((day: day, entries: [entry]));
      }
    }
    return groups;
  }

  Future<void> _newEntry() async {
    final saved = await showTimeEntrySheet(context);
    if (saved == null || !mounted) return;
    _afterSave(saved);
  }

  Future<void> _editEntry(WorkItem entry) async {
    final saved = await showTimeEntrySheet(context, entry: entry);
    if (saved == null || !mounted) return;
    _afterSave(saved);
  }

  void _afterSave(SavedTimeEntry saved) {
    unawaited(_reload());
    if (saved.hasOverlaps) {
      showGlassToast(
        context,
        // count: rather than a {'count': ...} variable. i18next casts the
        // variable to int to pick a plural form; a string casts to null, so
        // "overlaps 3 entries" silently read as the singular form.
        context.t('time.overlapWarning', count: saved.overlaps.length),
        kind: GlassToastKind.warning,
      );
    }
  }

  Future<void> _deleteEntry(WorkItem entry) async {
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('time.deleteTitle'),
      message: context.t('time.deleteMessage'),
      confirmLabel: context.t('common.delete'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<TimeRepository>().delete(entry.id);
      if (!mounted) return;
      unawaited(_reload());
    } catch (failure) {
      if (!mounted) return;
      showGlassToast(
        context,
        context.t(failure.toString()),
        kind: GlassToastKind.error,
      );
    }
  }

  Future<void> _continueEntry(WorkItem entry) =>
      context.read<TimerCubit>().continueEntry(entry.id);

  Future<void> _showHistory(WorkItem entry) =>
      showTimeEntryHistorySheet(context, entry: entry);
}

/// How much of the app bar the docked band takes: the module's one row. Stated
/// as a constant because the shell reserves it in the page's top gutter before
/// the band has laid itself out.
const double _kDockHeight = kGlassDockRow;

/// A docked filter: a glass pill that opens a picker, wearing the amber wash
/// when it is narrowing something.
///
/// Its proportions are the audit log's, deliberately — one toolbar idiom in the
/// app rather than two. [kGlassControlHeight] is shorter than the search field
/// above it, which is what the token exists for.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;

  /// Receives the pill's own rectangle on screen, so what it opens can hang off
  /// it on a wide window instead of rising out of the bottom of the display.
  /// Measured here rather than by the caller: the caller holds the page's
  /// context, and the page is the whole page.
  ///
  /// Null when the pill is no longer on screen, which is an answer and not a
  /// failure — the pickers read it as "no anchor" and fall back to the sheet
  /// rather than pinning a popover to the top-left corner of the display.
  final ValueChanged<Rect?> onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accentStrong : AppColors.inkSoft;
    return GlassPill(
      height: kGlassControlHeight,
      active: active,
      onTap: () => onTap(anchorRectOfContext(context)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 7),
            ConstrainedBox(
              // A project name can be long; the pill may not grow with it.
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? AppColors.accentStrong : AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 13, color: color),
          ],
        ),
      ),
    );
  }
}

/// Undoes every filter at once — icon-only, matched to the pill height.
class _ClearFiltersPill extends StatelessWidget {
  const _ClearFiltersPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GlassPill(
    height: kGlassControlHeight,
    onTap: onTap,
    child: SizedBox(
      width: kGlassControlHeight,
      child: Icon(LucideIcons.filterX, size: 16, color: AppColors.inkSoft),
    ),
  );
}

/// One day's entries under a header carrying the day and what it adds up to.
class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.day,
    required this.entries,
    required this.projects,
    required this.showTotal,
    required this.onEdit,
    required this.onDelete,
    required this.onContinue,
    required this.onHistory,
    required this.policy,
  });

  final DateTime day;
  final List<WorkItem> entries;
  final Map<String, Project> projects;

  /// Whether this day's entries are all loaded. False for the last group of a
  /// list with more pages, where a sum would be a sum of a fragment.
  final bool showTotal;
  final ValueChanged<WorkItem> onEdit;
  final ValueChanged<WorkItem> onDelete;
  final ValueChanged<WorkItem> onContinue;
  final ValueChanged<WorkItem> onHistory;

  /// The operator's rules, so a frozen day can say so rather than let somebody
  /// open an editor whose save is going to be refused.
  final TimePolicySnapshot policy;

  @override
  Widget build(BuildContext context) {
    final total = showTotal
        ? entries.fold<int>(0, (sum, e) => sum + e.durationMinutes)
        : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Row(
            children: [
              Text(
                _dayLabel(context, day),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              if (showTotal)
                Text(
                  fmtDuration(context, total),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: AppColors.inkSoft,
                  ),
                ),
            ],
          ),
        ),
        for (final entry in entries)
          _EntryRow(
            entry: entry,
            project: entry.projectId == null
                ? null
                : projects[entry.projectId!],
            onEdit: () => onEdit(entry),
            onDelete: () => onDelete(entry),
            onContinue: () => onContinue(entry),
            onHistory: () => onHistory(entry),
            lock: policy.lockFor(entry.date, entryId: entry.id),
          ),
      ],
    );
  }

  static String _dayLabel(BuildContext context, DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) return context.t('common.today');
    if (difference == 1) return context.t('common.yesterday');
    return MaterialLocalizations.of(context).formatFullDate(day);
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.project,
    required this.onEdit,
    required this.onDelete,
    required this.onContinue,
    required this.onHistory,
    this.lock,
  });

  final WorkItem entry;
  final Project? project;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onContinue;
  final VoidCallback onHistory;

  /// Whether the operator has frozen this entry's day. The row still opens —
  /// reading a locked entry is not forbidden, and the editor explains why the
  /// save is greyed out — but the destructive actions are gone rather than
  /// offered and refused.
  final TimeLockInfo? lock;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final interval = entry.startedAt != null && entry.endedAt != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.description?.trim().isNotEmpty ?? false
                            ? entry.description!.trim()
                            : context.t('time.entry.noDescription'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: entry.description?.trim().isNotEmpty ?? false
                              ? AppColors.ink
                              : AppColors.inkFaint,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _MetaChip(
                            icon: entry.projectId == null
                                ? LucideIcons.circleSlash
                                : LucideIcons.folder,
                            label: entry.projectId == null
                                ? context.t('time.placement.none')
                                : project?.name ??
                                      context.t('time.placement.assigned'),
                          ),
                          _MetaChip(
                            icon: LucideIcons.tag,
                            // The shared helper, which falls back to the raw
                            // value: an MCP client may send an activity the
                            // bundle has never heard of, and printing the
                            // untranslated key at it is worse than printing it.
                            label: activityLabel(context, entry.activityType),
                          ),
                          if (interval)
                            _MetaChip(
                              icon: LucideIcons.clock,
                              label:
                                  '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(entry.startedAt!), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))} – '
                                  '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(entry.endedAt!), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}',
                            ),
                          if (entry.billable)
                            _MetaChip(
                              icon: LucideIcons.banknote,
                              label: context.t('time.billable'),
                            ),
                          // The whole sentence on its tooltip, and the reason in
                          // its word: "Locked" on its own left somebody with
                          // nothing to do about it.
                          if (lock != null) LockChip(lock: lock!),
                          for (final tag in entry.tags)
                            _MetaChip(icon: LucideIcons.hash, label: tag),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  fmtDuration(context, entry.durationMinutes),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 4),
                _RowMenu(
                  onEdit: onEdit,
                  onDelete: onDelete,
                  onContinue: onContinue,
                  onHistory: onHistory,
                  locked: lock != null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 11, color: AppColors.inkFaint),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint)),
    ],
  );
}

class _RowMenu extends StatelessWidget {
  const _RowMenu({
    required this.onEdit,
    required this.onDelete,
    required this.onContinue,
    required this.onHistory,
    this.locked = false,
  });

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onContinue;
  final VoidCallback onHistory;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return GlassPopupMenu<String>(
      // Material's PopupMenuButton paints its own opaque surface, which is the
      // one menu in the product that would not be glass.
      value: '',
      width: 200,
      items: [
        GlassMenuItem(
          value: 'continue',
          label: context.t('time.entry.continue'),
          leading: Icon(LucideIcons.play, size: 15, color: AppColors.inkSoft),
        ),
        if (!locked)
          GlassMenuItem(
            value: 'edit',
            label: context.t('common.edit'),
            leading: Icon(
              LucideIcons.pencil,
              size: 15,
              color: AppColors.inkSoft,
            ),
          ),
        // Who changed this entry, and when. Offered on every entry, not only
        // the ones somebody else touched: "nobody but me" is the answer people
        // most often want, and a menu item that appears only when there is bad
        // news is a menu item nobody trusts.
        GlassMenuItem(
          value: 'history',
          label: context.t('time.history.open'),
          leading: Icon(
            LucideIcons.history,
            size: 15,
            color: AppColors.inkSoft,
          ),
        ),
        if (!locked)
          GlassMenuItem(
            value: 'delete',
            label: context.t('common.delete'),
            color: AppColors.danger,
            dividerAbove: true,
            leading: const Icon(
              LucideIcons.trash2,
              size: 15,
              color: AppColors.danger,
            ),
          ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'continue':
            onContinue();
          case 'history':
            onHistory();
          case 'edit':
            onEdit();
          case 'delete':
            onDelete();
        }
        // No default branch on purpose: a fourth row added without a case here
        // must do nothing, not fall through to the destructive one.
      },
      child: Tooltip(
        message: context.t('time.entryActions'),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            LucideIcons.ellipsisVertical,
            size: 16,
            color: AppColors.inkFaint,
          ),
        ),
      ),
    );
  }
}
