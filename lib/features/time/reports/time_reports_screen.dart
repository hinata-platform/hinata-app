import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/blocs/app_config_bloc.dart';
import '../../../core/blocs/auth_bloc.dart';
import '../../../core/blocs/paged_cubit.dart';
import '../../../core/blocs/time_policy_cubit.dart';
import '../../../core/blocs/time_report_cubit.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/absence_report_models.dart';
import '../../../core/models/time_report_models.dart';
import '../../../core/repositories/time_report_repository.dart';
import '../../../core/repositories/user_repository.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/server_link.dart';
import '../../../core/widgets/glass_filter_bar.dart';
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/glass_scope_row.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart'
    show GhostButton, PageHead, PrimaryButton;
import '../../../core/widgets/project_picker.dart';
import '../../shell/page_chrome.dart';
import '../../sprint/modals/glass_modal.dart';
import '../time_views.dart';
import 'absence_report_tab.dart';
import 'report_actions.dart';
import 'report_controls.dart';
import 'report_detail_views.dart';
import 'report_filter_sheet.dart';
import 'report_format.dart';
import 'report_import_wizard.dart';
import 'report_list_parts.dart';
import 'report_summary_view.dart';

/// The tabs of the report page (HIN-93).
enum ReportTab {
  summary('summary', LucideIcons.chartColumn),
  detailed('detailed', LucideIcons.list),
  workload('workload', LucideIcons.gauge),
  absences('absences', LucideIcons.calendarOff),
  saved('saved', LucideIcons.bookmark);

  const ReportTab(this.key, this.icon);

  final String key;
  final IconData icon;
}

/// The time reports: a summary with its chart, the entries themselves, booked
/// time against capacity, and the reports somebody kept (HIN-93).
///
/// Every number is computed by the server in the reader's own scope, whatever
/// the question and wherever it came from — typed here, saved, opened from a
/// colleague's link or a mail. [link] is `shared:<token>` or `saved:<id>` for
/// a report opened that way.
///
/// The head keeps the module's shape: on a phone the tabs are docked in the
/// app bar and the window, filters and grouping are one line under it, so the
/// head never grows past two rows of pills. Lists put the bottom inset inside
/// their scroll padding, so the last row scrolls up past the glass navigation
/// instead of stopping above it (HIN-118).
class TimeReportsScreen extends StatefulWidget {
  const TimeReportsScreen({super.key, this.link});

  final String? link;

  @override
  State<TimeReportsScreen> createState() => _TimeReportsScreenState();
}

class _TimeReportsScreenState extends State<TimeReportsScreen> {
  late final TimeReportRepository _repository = context
      .read<TimeReportRepository>();
  final _query = ReportQueryCubit();
  late final ReportGroupsCubit _groups = ReportGroupsCubit(
    (page, size) => _repository.summary(
      _query.state,
      page: page,
      size: size,
      weekStart: _weekStart,
    ),
  );
  late final PagedCubit<ReportEntry> _entries = PagedCubit<ReportEntry>(
    (page, size) => _repository.detailed(
      _query.state,
      page: page,
      size: size,
      weekStart: _weekStart,
    ),
    keyOf: (entry) => entry.id,
  );
  late final WorkloadRowsCubit _workload = WorkloadRowsCubit(
    (page, size) => _repository.workload(
      _query.state,
      projectId: _workloadProject,
      page: page,
      size: size,
      weekStart: _weekStart,
    ),
  );
  late final PagedCubit<SavedReport> _saved = PagedCubit<SavedReport>(
    (page, size) => _repository.savedReports(page: page, size: size),
    keyOf: (report) => report.id,
  );
  StreamSubscription<ReportQuery>? _querySub;

  /// The absence report's question (HIN-119), held here because the head
  /// exports what that tab shows.
  final _absenceQuery = ValueNotifier<AbsenceReportQuery>(
    const AbsenceReportQuery(),
  );

  /// The question the lists last answered, to tell a new question from a new
  /// chart of the same answer.
  ReportQuery _asked = const ReportQuery();

  ReportTab _tab = ReportTab.summary;

  /// The tabs whose lists answer the current question.
  final Set<ReportTab> _fresh = {};

  /// Names of the ids the filters hold.
  final ReportLabels _labels = {};

  /// The saved report on screen, when one was opened.
  SavedReport? _opened;

  /// Why a linked report could not be opened.
  String? _linkFailure;

  /// The project the workload report is narrowed to; null is the reader's own.
  String? _workloadProject;
  String? _workloadProjectName;

  @override
  void initState() {
    super.initState();
    _querySub = _query.stream.listen((next) {
      final before = _asked;
      _asked = next;
      // A different chart draws the same answer: nothing to ask the server.
      if (before.copyWith(chart: next.chart) == next) {
        setState(() {});
        return;
      }
      _fresh.clear();
      _loadTab();
    });
    // The policy first: it says whether the workload tab exists and which day
    // a week starts on, and a direct link to this page is the first reader of
    // it. A policy that cannot be read still leaves a report to show.
    unawaited(
      context.read<TimePolicyCubit>().ensureLoaded().whenComplete(() {
        if (!mounted) return;
        final link = widget.link;
        if (link != null) {
          unawaited(_openLink(link));
        } else {
          _loadTab();
        }
      }),
    );
  }

  @override
  void dispose() {
    unawaited(_querySub?.cancel());
    unawaited(_query.close());
    unawaited(_groups.close());
    unawaited(_entries.close());
    unawaited(_workload.close());
    unawaited(_saved.close());
    _absenceQuery.dispose();
    super.dispose();
  }

  /// The first day of a week: the approval rhythm's, which the server's week
  /// buckets follow too.
  int get _weekStart {
    const days = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    final name = context
        .read<TimePolicyCubit>()
        .state
        .approvalRhythm
        .weekStartsOn;
    final index = days.indexOf(name ?? '');
    return index < 0 ? DateTime.monday : index + 1;
  }

  bool get _admin => context.read<AuthBloc>().state.user?.isAdmin ?? false;

  void _loadTab() {
    if (_fresh.contains(_tab)) return;
    _fresh.add(_tab);
    unawaited(switch (_tab) {
      ReportTab.summary => _groups.load(),
      ReportTab.detailed => _entries.load(),
      ReportTab.workload => _workload.load(),
      // The absence report reads its own list, with its own question.
      ReportTab.absences => Future<void>.value(),
      ReportTab.saved => _saved.load(),
    });
  }

  void _switchTab(String key) {
    setState(() => _tab = ReportTab.values.firstWhere((tab) => tab.key == key));
    _loadTab();
  }

  Future<void> _openLink(String link) async {
    try {
      final report = switch (link) {
        _ when link.startsWith('shared:') => await _repository.openShared(
          link.substring('shared:'.length),
        ),
        _ when link.startsWith('saved:') => await _repository.openSaved(
          link.substring('saved:'.length),
        ),
        // Nothing this page knows how to open: the reports as they stand.
        _ => null,
      };
      if (!mounted) return;
      if (report == null) return _loadTab();
      _open(report);
    } on ApiFailure {
      if (!mounted) return;
      setState(() => _linkFailure = 'time.reports.saved.notFound');
      _loadTab();
    }
  }

  void _open(SavedReport report) {
    setState(() {
      _opened = report;
      _tab = ReportTab.summary;
    });
    unawaited(_resolveLabels(report.query));
    if (report.query == _query.state) {
      _fresh.clear();
      _loadTab();
    } else {
      _query.set(report.query);
    }
  }

  /// Names for the people a saved report filters by. Projects and teams are
  /// named when they are picked; people saved in a report need a lookup.
  Future<void> _resolveLabels(ReportQuery query) async {
    final missing = [
      for (final id in query.userIds)
        if (!_labels.containsKey(id)) id,
    ];
    if (missing.isEmpty) return;
    try {
      final users = await context.read<UserRepository>().usersByIds(missing);
      for (final user in users) {
        _labels[user.id] = user.displayName;
      }
    } on ApiFailure {
      // Unnamed ids read as ids in the chips; the report itself is unaffected.
    }
  }

  // --- the head ------------------------------------------------------------------

  List<GlassScope> _tabs({required bool workload, required bool absences}) => [
    for (final tab in ReportTab.values)
      if ((tab != ReportTab.workload || workload) &&
          (tab != ReportTab.absences || absences))
        (
          key: tab.key,
          icon: tab.icon,
          label: context.t('time.reports.tab.${tab.key}'),
        ),
  ];

  Future<void> _pickRange(Rect? anchor) async {
    final (from, to) = _query.state.window(
      DateTime.now(),
      weekStart: _weekStart,
    );
    final next = await pickReportRange(
      context,
      query: _query.state,
      from: from,
      to: to,
      anchor: anchor,
    );
    if (next != null) _query.set(next);
  }

  Future<void> _pickFilters(Rect? anchor) async {
    final policy = context.read<TimePolicyCubit>().state;
    final next = await showReportFilterSheet(
      context,
      query: _query.state,
      labels: _labels,
      people:
          _admin || (_groups.summary?.people ?? policy.leadsSeeMemberEntries),
      approvals: policy.approvalsEnabled,
    );
    if (next != null) _query.set(next);
  }

  Future<void> _export(Rect? anchor) async {
    final file = await showReportFileMenu(context, anchor);
    if (file == null || !mounted) return;
    await exportReport(
      context,
      query: _query.state,
      file: file,
      weekStart: _weekStart,
      anchor: anchor,
    );
  }

  Future<void> _import() async {
    final inserted = await showTimeImportWizard(context, admin: _admin);
    if (inserted == null || !mounted) return;
    showGlassToast(
      context,
      context.t('time.import.done', count: inserted),
      kind: GlassToastKind.success,
    );
    _fresh.clear();
    _loadTab();
  }

  Future<void> _save() async {
    final name = await askReportName(
      context,
      titleKey: 'time.reports.save.title',
    );
    if (name == null || !mounted) return;
    try {
      final saved = await _repository.saveReport(name, _query.state);
      if (!mounted) return;
      setState(() => _opened = saved);
      _fresh.remove(ReportTab.saved);
      _toast('time.reports.save.saved');
    } on ApiFailure catch (failure) {
      _toast(failure.message, error: true);
    }
  }

  Future<void> _updateOpened() async {
    final opened = _opened;
    if (opened == null) return;
    try {
      final updated = await _repository.updateReport(
        opened.id,
        query: _query.state,
      );
      if (!mounted) return;
      setState(() => _opened = updated);
      _fresh.remove(ReportTab.saved);
      _toast('time.reports.save.updated');
    } on ApiFailure catch (failure) {
      _toast(failure.message, error: true);
    }
  }

  Future<void> _exportAbsences(Rect? anchor) async {
    final file = await showReportFileMenu(
      context,
      anchor,
      files: ReportFile.forAbsences,
    );
    if (file == null || !mounted) return;
    await exportAbsenceReport(
      context,
      query: _absenceQuery.value,
      file: file,
      anchor: anchor,
    );
  }

  Future<void> _moreMenu(Rect? anchor) async {
    if (anchor == null) return;
    if (_tab == ReportTab.absences) return _exportAbsences(anchor);
    const import = 'import';
    const save = 'save';
    final chosen = await showGlassMenu<Object>(
      context: context,
      anchorRect: anchor,
      width: 250,
      value: '',
      items: [
        for (final file in ReportFile.forTime)
          GlassMenuItem(
            value: file,
            label: context.t(file.labelKey),
            leading: Icon(file.icon, size: 16, color: AppColors.inkSoft),
          ),
        GlassMenuItem(
          value: import,
          label: context.t('time.import.action'),
          leading: Icon(LucideIcons.fileUp, size: 16, color: AppColors.inkSoft),
          dividerAbove: true,
        ),
        GlassMenuItem(
          value: save,
          label: context.t('time.reports.save.title'),
          leading: Icon(
            LucideIcons.bookmarkPlus,
            size: 16,
            color: AppColors.inkSoft,
          ),
        ),
      ],
    );
    if (chosen == null || !mounted) return;
    if (chosen is ReportFile) {
      await exportReport(
        context,
        query: _query.state,
        file: chosen,
        weekStart: _weekStart,
        anchor: anchor,
      );
    } else if (chosen == import) {
      await _import();
    } else if (chosen == save) {
      await _save();
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

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final workload = context.select<TimePolicyCubit, bool>(
      (cubit) => cubit.state.workloadReportsEnabled,
    );
    // HIN-119: the absence report exists with absence management and its own
    // policy, and never without both.
    final absenceReports = context.select<TimePolicyCubit, bool>(
      (cubit) => cubit.state.absenceReportsEnabled,
    );
    final absenceModule = context.select<AppConfigBloc, bool>(
      (bloc) => bloc.state.meta?.absenceManagement ?? false,
    );
    final absences = absenceReports && absenceModule;
    if (_tab == ReportTab.workload && !workload ||
        _tab == ReportTab.absences && !absences) {
      _tab = ReportTab.summary;
    }
    final tabs = GlassScopeRow(
      scopes: _tabs(workload: workload, absences: absences),
      active: _tab.key,
      onSelected: _switchTab,
    );
    return PageChrome(
      contentMax: double.infinity,
      onTitleTap: compact
          ? (anchor) => unawaited(
              showTimeViewMenu<Never>(
                context,
                anchor: anchor,
                current: TimeView.reports,
              ),
            )
          : null,
      titleLeading: true,
      actions: compact
          ? [
              PageAction(
                icon: LucideIcons.ellipsis,
                label: context.t('time.reports.actions'),
                onTap: (anchor) => unawaited(_moreMenu(anchor)),
              ),
            ]
          : const [],
      bottom: compact ? tabs : null,
      bottomHeight: compact ? kGlassDockRow : 0,
      child: compact
          ? _body()
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
                  // The title, the switcher and three labelled buttons need
                  // about a thousand points; narrower, the three fold into
                  // the menu the phone uses.
                  child: LayoutBuilder(
                    builder: (context, constraints) => PageHead(
                      title: context.t('nav.time'),
                      actions: [
                        const TimeViewSwitcher(current: TimeView.reports),
                        if (_tab == ReportTab.absences)
                          // The absence report has one way out: its files.
                          Builder(
                            builder: (anchor) => GhostButton(
                              icon: LucideIcons.download,
                              label: context.t('time.reports.export.title'),
                              onPressed: () =>
                                  unawaited(_exportAbsences(_rectOf(anchor))),
                            ),
                          )
                        else if (constraints.maxWidth <
                            1000 * textFactor(context))
                          Builder(
                            builder: (anchor) => GhostButton(
                              icon: LucideIcons.ellipsis,
                              label: context.t('time.reports.actions'),
                              onPressed: () =>
                                  unawaited(_moreMenu(_rectOf(anchor))),
                              iconOnly: true,
                            ),
                          )
                        else ...[
                          GhostButton(
                            icon: LucideIcons.fileUp,
                            label: context.t('time.import.action'),
                            onPressed: () => unawaited(_import()),
                          ),
                          Builder(
                            builder: (anchor) => GhostButton(
                              icon: LucideIcons.download,
                              label: context.t('time.reports.export.title'),
                              onPressed: () =>
                                  unawaited(_export(_rectOf(anchor))),
                            ),
                          ),
                          PrimaryButton(
                            icon: LucideIcons.bookmarkPlus,
                            label: context.t('time.reports.save.title'),
                            onPressed: () => unawaited(_save()),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.pageGutter,
                    0,
                    context.pageGutter,
                    12,
                  ),
                  child: tabs,
                ),
                Expanded(child: _body()),
              ],
            ),
    );
  }

  static Rect? _rectOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// The gutter around a tab's list, the bottom inset included — inside the
  /// scroll padding, never outside it.
  EdgeInsets _padding() => EdgeInsets.fromLTRB(
    context.pageGutter,
    context.isCompact ? context.topGutter + 6 : 0,
    context.pageGutter,
    context.pageGutter + context.bottomGutter,
  );

  Widget _body() {
    final padding = _padding();
    if (_tab == ReportTab.absences) {
      return AbsenceReportTab(query: _absenceQuery, padding: padding);
    }
    return RefreshIndicator(
      edgeOffset: context.topGutter,
      onRefresh: () async {
        _fresh.remove(_tab);
        _loadTab();
      },
      child: switch (_tab) {
        ReportTab.summary => _summary(padding),
        ReportTab.detailed => _detailed(padding),
        ReportTab.workload => _workloadTab(padding),
        ReportTab.saved => _savedTab(padding),
        ReportTab.absences => const SizedBox.shrink(),
      },
    );
  }

  /// The controls row and the notes that stand over every report tab.
  List<Widget> _head(
    EdgeInsets padding, {
    required bool grouping,
    Widget? scope,
  }) {
    final horizontal = padding.copyWith(top: 0, bottom: 0);
    final people = _admin || (_groups.summary?.people ?? false);
    return [
      SliverPadding(padding: EdgeInsets.only(top: padding.top)),
      SliverPadding(
        padding: context.isCompact
            ? const EdgeInsets.only(bottom: 12)
            : horizontal.copyWith(bottom: 12),
        sliver: SliverToBoxAdapter(
          child: BlocBuilder<ReportQueryCubit, ReportQuery>(
            bloc: _query,
            builder: (context, query) {
              final (from, to) = query.window(
                DateTime.now(),
                weekStart: _weekStart,
              );
              return ReportControlsRow(
                query: query,
                from: from,
                to: to,
                onRange: (anchor) => unawaited(_pickRange(anchor)),
                onFilters: (anchor) => unawaited(_pickFilters(anchor)),
                onClear: () => _query.set(query.cleared()),
                groupings: grouping
                    ? [
                        for (final group in ReportGroupBy.values)
                          if (!group.readsPeople || people) group,
                      ]
                    : null,
                onGroupBy: grouping
                    ? (group) =>
                          _query.change((q) => q.copyWith(groupBy: group))
                    : null,
                scope: scope,
              );
            },
          ),
        ),
      ),
      if (_linkFailure != null)
        SliverPadding(
          padding: horizontal.copyWith(bottom: 12),
          sliver: SliverToBoxAdapter(
            child: _Note(
              icon: LucideIcons.unlink,
              text: context.t(_linkFailure!),
              onClose: () => setState(() => _linkFailure = null),
            ),
          ),
        ),
      if (_opened case final opened?)
        SliverPadding(
          padding: horizontal.copyWith(bottom: 12),
          sliver: SliverToBoxAdapter(
            child: _Note(
              icon: opened.owned ? LucideIcons.bookmark : LucideIcons.link,
              text: opened.owned
                  ? opened.name
                  : context.t(
                      'time.reports.saved.openedShared',
                      variables: {'name': opened.name},
                    ),
              action: opened.owned && opened.query != _query.state
                  ? (
                      label: context.t('time.reports.save.update'),
                      onTap: () => unawaited(_updateOpened()),
                    )
                  : null,
              onClose: () => setState(() => _opened = null),
            ),
          ),
        ),
    ];
  }

  // --- summary -------------------------------------------------------------------

  Widget _summary(EdgeInsets padding) {
    final horizontal = padding.copyWith(top: 0, bottom: 0);
    final compact = context.isCompact;
    return BlocBuilder<ReportGroupsCubit, PagedState<ReportGroup>>(
      bloc: _groups,
      builder: (context, state) {
        final summary = _groups.summary;
        final query = _query.state;
        return ReportPagedScroll(
          onEnd: _groups.loadMore,
          slivers: [
            ..._head(padding, grouping: true),
            if (state.errorKey != null && !state.hasData)
              _failure(horizontal, state.errorKey!, _groups.load)
            else if (summary == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: HiveLoader()),
              )
            else if (summary.totals.entries == 0)
              SliverToBoxAdapter(
                child: HiveEmptyState(
                  title: context.t('time.reports.empty'),
                  message: context.t('time.reports.emptyHint'),
                ),
              )
            else ...[
              SliverPadding(
                padding: horizontal.copyWith(bottom: 12),
                sliver: SliverToBoxAdapter(
                  child: ReportTotalsStrip(
                    totals: summary.totals,
                    compact: compact,
                  ),
                ),
              ),
              SliverPadding(
                padding: horizontal.copyWith(bottom: 12),
                sliver: SliverToBoxAdapter(
                  child: ReportChartCard(
                    groupBy: query.groupBy,
                    groups: summary.groups,
                    totalMinutes: summary.totals.minutes,
                    chart: query.chart,
                    compact: compact,
                    onChart: (chart) =>
                        _query.change((q) => q.copyWith(chart: chart)),
                  ),
                ),
              ),
              // Phones drop the column heads; the first row opens the card.
              if (!compact)
                SliverPadding(
                  padding: horizontal,
                  sliver: SliverToBoxAdapter(
                    child: ReportCardEdge(
                      top: true,
                      last: state.items.isEmpty,
                      child: ReportGroupHead(groupBy: query.groupBy),
                    ),
                  ),
                ),
              SliverPadding(
                padding: horizontal,
                sliver: SliverList.builder(
                  itemCount: state.items.length,
                  itemBuilder: (context, index) {
                    final group = state.items[index];
                    return ReportCardEdge(
                      top: compact && index == 0,
                      last: index == state.items.length - 1,
                      child: ReportGroupRow(
                        groupBy: query.groupBy,
                        group: group,
                        index: index,
                        totalMinutes: summary.totals.minutes,
                        compact: compact,
                        onTap: _drillInto(query, group),
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
        );
      },
    );
  }

  /// The entries behind one group: the same question narrowed to it, on the
  /// entries tab. Null for a group nothing can be narrowed to.
  VoidCallback? _drillInto(ReportQuery query, ReportGroup group) {
    final key = group.key;
    if (key == null) return null;
    ReportQuery? next;
    switch (query.groupBy) {
      case ReportGroupBy.project:
        _labels[key] = group.label ?? key;
        next = query.copyWith(projectIds: [key]);
      case ReportGroupBy.user:
        _labels[key] = group.label ?? key;
        next = query.copyWith(userIds: [key]);
      case ReportGroupBy.team:
        _labels[key] = group.label ?? key;
        next = query.copyWith(teamIds: [key]);
      case ReportGroupBy.tag:
        next = query.copyWith(tags: [key]);
      case ReportGroupBy.activity:
        next = query.copyWith(activities: [key]);
      case ReportGroupBy.day:
      case ReportGroupBy.week:
      case ReportGroupBy.month:
        final day = group.day;
        if (day == null) return null;
        final end = switch (query.groupBy) {
          ReportGroupBy.week => day.add(const Duration(days: 6)),
          ReportGroupBy.month => DateTime(day.year, day.month + 1, 0),
          _ => day,
        };
        next = query.copyWith(range: ReportRange.custom, from: day, to: end);
      case ReportGroupBy.issue:
        return null;
    }
    final target = next;
    return () {
      setState(() => _tab = ReportTab.detailed);
      _query.set(target);
      _loadTab();
    };
  }

  // --- detailed ------------------------------------------------------------------

  Widget _detailed(EdgeInsets padding) {
    final horizontal = padding.copyWith(top: 0, bottom: 0);
    final compact = context.isCompact;
    final people = _admin || (_groups.summary?.people ?? false);
    return BlocBuilder<PagedCubit<ReportEntry>, PagedState<ReportEntry>>(
      bloc: _entries,
      builder: (context, state) {
        // Day headings between the rows, from the rows already held: a list
        // of hundreds stays lazy.
        final rows = <Object>[];
        DateTime? day;
        for (final entry in state.items) {
          if (entry.date != day) {
            day = entry.date;
            rows.add(entry.date);
          }
          rows.add(entry);
        }
        return ReportPagedScroll(
          onEnd: _entries.loadMore,
          slivers: [
            ..._head(padding, grouping: false),
            if (state.errorKey != null && !state.hasData)
              _failure(horizontal, state.errorKey!, _entries.load)
            else if (!state.hasData)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: HiveLoader()),
              )
            else if (state.items.isEmpty)
              SliverToBoxAdapter(
                child: HiveEmptyState(
                  title: context.t('time.reports.detailedEmpty'),
                  message: context.t('time.reports.emptyHint'),
                ),
              )
            else
              SliverPadding(
                padding: horizontal,
                sliver: SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) => switch (rows[index]) {
                    final DateTime day => ReportDayHead(day: day),
                    final ReportEntry entry => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ReportEntryRow(
                        entry: entry,
                        showPerson: people,
                        compact: compact,
                      ),
                    ),
                    _ => const SizedBox.shrink(),
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
            SliverPadding(padding: EdgeInsets.only(bottom: padding.bottom)),
          ],
        );
      },
    );
  }

  // --- workload ------------------------------------------------------------------

  Future<void> _pickWorkloadGroup(Rect? anchor) async {
    const mine = '';
    const project = '@project';
    final picked = await showGlassOptions<String>(
      context,
      title: context.t('time.reports.workload.group'),
      anchorRect: anchor,
      options: [
        (
          value: mine,
          child: Text(context.t('time.reports.workload.myProjects')),
        ),
        (
          value: project,
          child: Text(context.t('time.reports.workload.pickProject')),
        ),
      ],
    );
    if (picked == null || !mounted) return;
    if (picked == mine) {
      setState(() {
        _workloadProject = null;
        _workloadProjectName = null;
      });
    } else {
      final projects = await showProjectPicker(
        context,
        anchorRect: anchor ?? Rect.zero,
        selected: {?_workloadProject},
        titleKey: 'time.reports.workload.pickProject',
        multi: false,
      );
      if (projects == null || projects.isEmpty || !mounted) return;
      setState(() {
        _workloadProject = projects.first.id;
        _workloadProjectName = projects.first.name;
      });
    }
    unawaited(_workload.load());
  }

  Widget _workloadTab(EdgeInsets padding) {
    final horizontal = padding.copyWith(top: 0, bottom: 0);
    final compact = context.isCompact;
    return BlocBuilder<WorkloadRowsCubit, PagedState<WorkloadRow>>(
      bloc: _workload,
      builder: (context, state) {
        final forbidden =
            state.errorKey == 'error.time.report.workloadForbidden';
        return ReportPagedScroll(
          onEnd: _workload.loadMore,
          slivers: [
            ..._head(
              padding,
              grouping: false,
              scope: GlassFilterPill(
                icon: LucideIcons.folderKanban,
                label:
                    _workloadProjectName ??
                    context.t('time.reports.workload.myProjects'),
                active: _workloadProject != null,
                onTap: (anchor) => unawaited(_pickWorkloadGroup(anchor)),
              ),
            ),
            if (forbidden)
              SliverToBoxAdapter(
                child: HiveEmptyState(
                  title: context.t('time.reports.workload.forbidden'),
                ),
              )
            else if (state.errorKey != null && !state.hasData)
              _failure(horizontal, state.errorKey!, _workload.load)
            else if (!state.hasData)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: HiveLoader()),
              )
            else if (state.items.isEmpty)
              SliverToBoxAdapter(
                child: HiveEmptyState(
                  title: context.t('time.reports.workload.empty'),
                  message: context.t('time.reports.workload.emptyHint'),
                ),
              )
            else ...[
              if (_workload.bookedInLedProjects || _workload.truncated)
                SliverPadding(
                  padding: horizontal.copyWith(bottom: 12),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      [
                        if (_workload.bookedInLedProjects)
                          context.t('time.reports.workload.ledOnly'),
                        if (_workload.truncated)
                          context.t('time.reports.workload.truncated'),
                      ].join(' '),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: horizontal,
                sliver: SliverList.builder(
                  itemCount: state.items.length,
                  itemBuilder: (context, index) => ReportCardEdge(
                    top: index == 0,
                    last: index == state.items.length - 1,
                    child: WorkloadRowView(
                      row: state.items[index],
                      compact: compact,
                    ),
                  ),
                ),
              ),
            ],
            SliverPadding(padding: EdgeInsets.only(bottom: padding.bottom)),
          ],
        );
      },
    );
  }

  // --- saved ---------------------------------------------------------------------

  Widget _savedTab(EdgeInsets padding) {
    final horizontal = padding.copyWith(top: 0, bottom: 0);
    return BlocBuilder<PagedCubit<SavedReport>, PagedState<SavedReport>>(
      bloc: _saved,
      builder: (context, state) => ReportPagedScroll(
        onEnd: _saved.loadMore,
        slivers: [
          SliverPadding(padding: EdgeInsets.only(top: padding.top)),
          if (state.errorKey != null && !state.hasData)
            _failure(horizontal, state.errorKey!, _saved.load)
          else if (!state.hasData)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: HiveLoader()),
            )
          else if (state.items.isEmpty)
            SliverToBoxAdapter(
              child: HiveEmptyState(
                title: context.t('time.reports.saved.empty'),
                message: context.t('time.reports.saved.emptyHint'),
              ),
            )
          else
            SliverPadding(
              padding: horizontal,
              sliver: SliverList.builder(
                itemCount: state.items.length,
                itemBuilder: (context, index) {
                  final report = state.items[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SavedReportTile(
                      report: report,
                      onOpen: () => _open(report),
                      onMenu: (anchor) => unawaited(_savedMenu(report, anchor)),
                    ),
                  );
                },
              ),
            ),
          SliverPadding(padding: EdgeInsets.only(bottom: padding.bottom)),
        ],
      ),
    );
  }

  Future<void> _savedMenu(SavedReport report, Rect? anchor) async {
    if (anchor == null) return;
    final chosen = await showGlassMenu<String>(
      context: context,
      anchorRect: anchor,
      width: 250,
      value: '',
      items: [
        GlassMenuItem(
          value: 'open',
          label: context.t('time.reports.saved.open'),
        ),
        GlassMenuItem(
          value: 'rename',
          label: context.t('time.reports.saved.rename'),
        ),
        GlassMenuItem(
          value: 'share',
          label: context.t(
            report.shared
                ? 'time.reports.saved.copyLink'
                : 'time.reports.saved.share',
          ),
          dividerAbove: true,
        ),
        if (report.shared)
          GlassMenuItem(
            value: 'unshare',
            label: context.t('time.reports.saved.unshare'),
          ),
        GlassMenuItem(
          value: 'schedule',
          label: context.t('time.reports.saved.schedule'),
        ),
        if (report.schedule != null)
          GlassMenuItem(
            value: 'unschedule',
            label: context.t('time.reports.saved.unschedule'),
          ),
        GlassMenuItem(
          value: 'delete',
          label: context.t('time.reports.saved.delete'),
          color: AppColors.danger,
          dividerAbove: true,
        ),
      ],
    );
    if (chosen == null || !mounted) return;
    try {
      switch (chosen) {
        case 'open':
          _open(report);
        case 'rename':
          final name = await askReportName(
            context,
            titleKey: 'time.reports.save.renameTitle',
            initial: report.name,
          );
          if (name == null) return;
          _saved.replaceItem(
            await _repository.updateReport(report.id, name: name),
          );
        case 'share':
          // A new link every time: the token is shown once and kept only as a
          // hash, so "copy the link again" is "make a new one" — and the old
          // one stops working, which is the point of being able to rotate it.
          final token = await _repository.shareReport(report.id);
          if (!mounted) return;
          final link = appWebLink(
            context.read<ApiClient>().baseUrl,
            '/time/reports?shared=$token',
          );
          await Clipboard.setData(ClipboardData(text: link));
          _toast('time.reports.saved.linkCopied');
          unawaited(_saved.load());
        case 'unshare':
          await _repository.unshareReport(report.id);
          _toast('time.reports.saved.unshared');
          unawaited(_saved.load());
        case 'schedule':
          final names = <String, String>{..._labels};
          final missing = [
            for (final id in report.schedule?.recipients ?? const <String>[])
              if (!names.containsKey(id)) id,
          ];
          if (missing.isNotEmpty) {
            for (final user in await context.read<UserRepository>().usersByIds(
              missing,
            )) {
              names[user.id] = user.displayName;
            }
          }
          if (!mounted) return;
          final schedule = await showReportScheduleSheet(
            context,
            current: report.schedule,
            names: names,
          );
          if (schedule == null) return;
          _saved.replaceItem(
            await _repository.scheduleReport(report.id, schedule),
          );
          _toast('time.reports.schedule.saved');
        case 'unschedule':
          _saved.replaceItem(await _repository.unscheduleReport(report.id));
          _toast('time.reports.schedule.ended');
        case 'delete':
          final sure = await showGlassConfirm(
            context,
            icon: LucideIcons.trash2,
            title: context.t('time.reports.saved.delete'),
            message: context.t(
              'time.reports.saved.deleteConfirm',
              variables: {'name': report.name},
            ),
            confirmLabel: context.t('time.reports.saved.delete'),
            destructive: true,
          );
          if (sure != true) return;
          await _repository.deleteReport(report.id);
          _saved.removeItem(report.id);
          if (_opened?.id == report.id) setState(() => _opened = null);
          _toast('time.reports.saved.deleted');
      }
    } on ApiFailure catch (failure) {
      _toast(failure.message, error: true);
    }
  }

  // --- shared --------------------------------------------------------------------

  Widget _failure(
    EdgeInsets horizontal,
    String key,
    Future<void> Function() retry,
  ) => SliverToBoxAdapter(
    child: HiveEmptyState(
      title: context.t('time.reports.loadError'),
      message: context.t(key),
      action: TextButton(
        onPressed: () => unawaited(retry()),
        child: Text(context.t('time.reports.retry')),
      ),
    ),
  );
}

/// A line over the report: which saved or shared report is on screen, or why
/// a linked one is not.
class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.text,
    required this.onClose,
    this.action,
  });

  final IconData icon;
  final String text;
  final VoidCallback onClose;
  final ({String label, VoidCallback onTap})? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.inkSoft),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          if (action case final action?)
            TextButton(onPressed: action.onTap, child: Text(action.label)),
          IconButton(
            tooltip: context.t('common.close'),
            onPressed: onClose,
            icon: Icon(LucideIcons.x, size: 16, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}
