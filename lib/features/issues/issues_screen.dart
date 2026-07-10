import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hinata/features/shell/app_shell.dart'
    show kNavGlassDark, kNavGlassLight, isNativeApp;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show LiquidRoundedSuperellipse, LiquidOval;
import 'package:liquid_glass_widgets/widgets/interactive/glass_button.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/events/issue_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/project_palette.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';
import '../reports/logo_raster.dart';
import 'issue_detail_sheet.dart';
import 'issue_export.dart';
import 'issue_filter.dart';
import 'issue_filter_popup.dart';
import 'issue_form.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/meta_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/user_repository.dart';

part 'issues_screen.toolbar.dart';
part 'issues_screen.rows.dart';

/// Shared lookup data for rendering issue rows — loaded once alongside the
/// paginated issue stream (users → names/avatars, projects → names/palette and
/// the unioned workflow-state order for status grouping).
typedef _RefData = ({
  Map<String, String> names,
  Map<String, String> avatars,
  Map<String, String> projectNames,
  List<String> stateOrder,
  ProjectPalette palette,
});

class IssuesScreen extends StatefulWidget {
  const IssuesScreen({
    super.key,
    this.projectId,
    this.initialView,
    this.scopeProjectIds = const [],
  });

  final String? projectId;

  /// Optional preset the screen opens pre-filtered on (dashboard KPI deep-link).
  final IssuesInitialView? initialView;

  /// Project scope carried from the dashboard so a KPI deep-link reproduces the
  /// same project selection the card was counted with. Empty ⇒ all projects.
  final List<String> scopeProjectIds;

  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  /// Empty lookups so rows can still render if reference data fails to load
  /// (names fall back to ids) without blocking the issue list.
  static final _RefData _emptyRef = (
    names: const {},
    avatars: const {},
    projectNames: const {},
    stateOrder: const [],
    palette: ProjectPalette.empty,
  );

  static const int _pageSize = 100;

  late final PagedCubit<Issue> _issues;
  final ScrollController _scroll = ScrollController();

  // Reference data (users + projects), loaded once in parallel with page 0.
  _RefData? _ref;
  bool _refLoading = true;
  bool _refError = false;

  // Guards the "export everything" flow so the menu can't fire twice.
  bool _exporting = false;

  IssueFilter _filter = IssueFilter.empty;
  IssueGrouping _grouping = IssueGrouping.none;
  IssueTimeRange _timeRange = IssueTimeRange.none;

  /// The deep-link preset is applied once, after projects load (so bucket
  /// presets can resolve to real state names); later refreshes keep the user's
  /// own filter choices.
  bool _initialViewApplied = false;

  /// Group keys currently collapsed in the grouped view (mirrors the board's
  /// swimlane collapse). Cleared whenever the grouping dimension changes.
  final Set<String> _collapsed = {};

  final GlobalKey _filterKey = GlobalKey();

  /// Re-fetch when an issue is created/changed elsewhere (e.g. the global
  /// nav-rail "new issue" button, which can't reach this screen's cubit).
  StreamSubscription<void>? _issueSub;

  @override
  void initState() {
    super.initState();
    _issueSub = IssueEvents.instance.changes.listen((_) => _reload());
    _issues = PagedCubit<Issue>(
      (page, size) async {
        final result = await context.read<IssueRepository>().issues(
          projectId: widget.projectId,
          archived: _filter.archivedOnly,
          page: page,
          size: size,
        );
        return (items: result.issues, total: result.total);
      },
      pageSize: _pageSize,
      keyOf: (i) => i.id,
    )..load();
    _scroll.addListener(_onScroll);
    _loadRef();
  }

  @override
  void dispose() {
    _issueSub?.cancel();
    _scroll.dispose();
    _issues.close();
    super.dispose();
  }

  /// Loads users + projects into [_ref]. Best-effort: a failure leaves rows to
  /// render with id fallbacks rather than blocking the whole screen.
  Future<void> _loadRef() async {
    if (mounted) {
      setState(() {
        _refLoading = true;
        _refError = false;
      });
    }
    try {
      final results = await Future.wait([context.read<UserRepository>().users(), context.read<ProjectRepository>().projects()]);
      final users = results[0] as List<DirectoryUser>;
      final projects = results[1] as List<Project>;
      // Workflow-state order (UPPER-CASE), unioned across projects in first-seen
      // order, so status grouping lists columns the way the projects define them.
      final stateOrder = <String>[];
      final seenStates = <String>{};
      for (final p in projects) {
        for (final name in p.stateNames) {
          final code = name.toUpperCase();
          if (seenStates.add(code)) stateOrder.add(code);
        }
      }
      if (!mounted) return;
      setState(() {
        _ref = (
          names: {for (final u in users) u.id: u.displayName},
          avatars: {
            for (final u in users)
              if (u.avatarUrl != null && u.avatarUrl!.isNotEmpty)
                u.id: u.avatarUrl!,
          },
          projectNames: {for (final p in projects) p.id: p.name},
          stateOrder: stateOrder,
          palette: ProjectPalette.fromProjects(projects),
        );
        _refLoading = false;
        // Apply a dashboard deep-link preset once, now that we know the
        // projects' workflow/resolved states.
        if (!_initialViewApplied && widget.initialView != null) {
          _applyInitialView(widget.initialView!, projects);
          _initialViewApplied = true;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _refLoading = false;
        _refError = true;
      });
    }
  }

  /// Translates a dashboard KPI deep-link preset into the concrete filter/time
  /// range. Bucket presets use the same rule as the dashboard's server-side
  /// completion split: done = the projects' resolved states, backlog =
  /// `Backlog`/`Open`, in-progress = everything else.
  void _applyInitialView(IssuesInitialView view, List<Project> projects) {
    // Each preset fully defines the view — start from a clean slate so nothing
    // from a previous state (filter or time range) leaks in.
    _filter = IssueFilter.empty;
    _timeRange = IssueTimeRange.none;
    // The dashboard's project scope (if any) applies to every preset so the
    // filtered list reproduces exactly what the KPI card counted.
    final scope = widget.scopeProjectIds.toSet();
    if (view == IssuesInitialView.today) {
      // "Today's tasks" = my open issues due today or overdue — the exact set the
      // dashboard KPI counts, so the filtered list length matches the card.
      final me = context.read<AuthBloc>().state.user?.id;
      _filter = IssueFilter(
        assignees: me == null ? const {} : {me},
        projects: scope,
      );
      _timeRange = const IssueTimeRange(preset: IssueTimePreset.dueByToday);
      return;
    }
    final done = <String>{};
    final all = <String>{};
    for (final p in projects) {
      for (final name in p.resolvedStates) {
        done.add(name.toUpperCase());
      }
      for (final name in p.stateNames) {
        all.add(name.toUpperCase());
      }
    }
    const backlog = {'BACKLOG', 'OPEN'};
    final states = switch (view) {
      IssuesInitialView.done => done,
      IssuesInitialView.backlog => all.intersection(backlog),
      IssuesInitialView.inProgress => all.difference(done).difference(backlog),
      IssuesInitialView.today => const <String>{},
    };
    _filter = IssueFilter(states: states, projects: scope);
  }

  /// Pull-to-refresh / retry: reload the first page and the reference data.
  Future<void> _reload() => Future.wait([_issues.load(), _loadRef()]);

  /// Infinite scroll: pull the next page as the user nears the bottom. The
  /// cubit guards against overlapping or past-the-end requests.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      _issues.loadMore();
    }
  }

  // ── filtering / sorting ────────────────────────────────────────────────

  List<Issue> _filtered(List<Issue> issues) {
    final list = issues
        .where((i) => _filter.matches(i) && _timeRange.matches(i))
        .toList();
    const rank = {'URGENT': 4, 'HIGH': 3, 'NORMAL': 2, 'LOW': 1};
    list.sort(
      (a, b) => (rank[b.priority.toUpperCase()] ?? 2).compareTo(
        rank[a.priority.toUpperCase()] ?? 2,
      ),
    );
    return list;
  }

  // ── grouping ──────────────────────────────────────────────────────────

  /// Buckets [list] into ordered sections for the active grouping. Returns an
  /// empty list when grouping is off (the caller renders a flat list instead).
  List<_Section> _sections(List<Issue> list, _RefData data) {
    if (_grouping == IssueGrouping.none) return const [];
    final buckets = <String, List<Issue>>{};
    String keyOf(Issue i) => switch (_grouping) {
      IssueGrouping.state => i.state.toUpperCase(),
      IssueGrouping.priority => i.priority.toUpperCase(),
      IssueGrouping.assignee =>
        (i.assigneeId?.isNotEmpty ?? false) ? i.assigneeId! : _kNone,
      IssueGrouping.project => i.projectId,
      IssueGrouping.type => i.type.toUpperCase(),
      IssueGrouping.none => '',
    };
    for (final issue in list) {
      buckets.putIfAbsent(keyOf(issue), () => []).add(issue);
    }
    final keys = buckets.keys.toList()..sort(_keyComparator(data));
    return [
      for (final k in keys)
        _Section(
          key: k,
          header: _groupHeader(k, buckets[k]!.length, data),
          issues: buckets[k]!,
        ),
    ];
  }

  int Function(String, String) _keyComparator(_RefData data) {
    switch (_grouping) {
      case IssueGrouping.state:
        return (a, b) {
          final ia = data.stateOrder.indexOf(a);
          final ib = data.stateOrder.indexOf(b);
          final ra = ia == -1 ? data.stateOrder.length : ia;
          final rb = ib == -1 ? data.stateOrder.length : ib;
          return ra != rb ? ra.compareTo(rb) : a.compareTo(b);
        };
      case IssueGrouping.priority:
        const order = ['URGENT', 'HIGH', 'NORMAL', 'LOW'];
        return (a, b) => _rankIn(order, a).compareTo(_rankIn(order, b));
      case IssueGrouping.type:
        const order = ['EPIC', 'STORY', 'TASK', 'BUG', 'FEATURE', 'SUBTASK'];
        return (a, b) => _rankIn(order, a).compareTo(_rankIn(order, b));
      case IssueGrouping.assignee:
        return (a, b) {
          if (a == _kNone) return 1;
          if (b == _kNone) return -1;
          return (data.names[a] ?? a).toLowerCase().compareTo(
            (data.names[b] ?? b).toLowerCase(),
          );
        };
      case IssueGrouping.project:
        return (a, b) => (data.projectNames[a] ?? a).toLowerCase().compareTo(
          (data.projectNames[b] ?? b).toLowerCase(),
        );
      case IssueGrouping.none:
        return (a, b) => 0;
    }
  }

  Widget _groupHeader(String key, int count, _RefData data) {
    Widget leading;
    String label;
    switch (_grouping) {
      case IssueGrouping.state:
        leading = _Dot(color: data.palette.stateColor(key));
        label = stateLabel(key);
      case IssueGrouping.priority:
        leading = PriorityFlag(priority: key);
        label = _enumLabel(context, 'priority', key);
      case IssueGrouping.type:
        leading = TypeGlyph(type: key, size: 18);
        label = _enumLabel(context, 'type', key);
      case IssueGrouping.assignee:
        if (key == _kNone) {
          leading = Icon(
            LucideIcons.userX,
            size: 18,
            color: AppColors.inkFaint,
          );
          label = context.t('issues.unassigned');
        } else {
          final name = data.names[key] ?? key;
          leading = HiveAvatar(
            name: name,
            imageUrl: data.avatars[key],
            size: 22,
          );
          label = name;
        }
      case IssueGrouping.project:
        leading = Icon(LucideIcons.folder, size: 17, color: AppColors.inkFaint);
        label = data.projectNames[key] ?? key;
      case IssueGrouping.none:
        leading = const SizedBox.shrink();
        label = '';
    }
    return _GroupHeader(leading: leading, label: label, count: count);
  }

  // ── actions ───────────────────────────────────────────────────────────

  void _openFilter(_RefData data, List<Issue> issues) => openIssueFilter(
    context,
    anchorKey: _filterKey,
    filter: _filter,
    options: IssueFilterOptions.from(issues),
    names: data.names,
    avatars: data.avatars,
    projectNames: data.projectNames,
    onChanged: (f) {
      // The archived facet is server-side — flipping it swaps the whole
      // backend result set, so the page cache must be refetched.
      final refetch = f.archivedOnly != _filter.archivedOnly;
      setState(() => _filter = f);
      if (refetch) _issues.load();
    },
  );

  Future<void> _export(String format) async {
    if (_exporting) return;
    // Read inherited blocs / repositories before the first await to avoid using
    // context across async gaps.
    final cachedMeta = context.read<AppConfigBloc>().state.meta;
    final issueApi = context.read<IssueRepository>();
    final metaApi = context.read<MetaRepository>();
    setState(() => _exporting = true);
    try {
      // Export EVERY matching issue, not just the pages scrolled into view:
      // page through the whole backend result set first so the file is complete
      // regardless of how far the user has scrolled.
      final List<Issue> all;
      try {
        all = await issueApi.allIssues(
          projectId: widget.projectId,
          archived: _filter.archivedOnly,
        );
      } catch (_) {
        if (mounted) _toast(context.t('reports.exportFailed'));
        return;
      }
      if (!mounted) return;
      final ref = _ref ?? _emptyRef;

      if (format == 'pdf') {
        ServerMeta? meta = cachedMeta;
        try {
          meta = await metaApi.meta();
        } catch (_) {
          meta = cachedMeta;
        }
        Uint8List? logoPng;
        try {
          final logoAsset = await metaApi.organizationLogo();
          if (logoAsset != null) {
            logoPng = await logoToPng(
              bytes: logoAsset.bytes,
              isSvg: logoAsset.isSvg,
            );
          }
        } catch (_) {
          logoPng = null;
        }
        if (!mounted) return;
        final failMsg = context.t('reports.exportFailed');
        try {
          await shareIssuesPdf(_buildExportData(ref, all, meta, logoPng));
        } catch (_) {
          _toast(failMsg);
        }
        return;
      }

      final data = _buildExportData(ref, all, null, null);
      final isCsv = format == 'csv';
      final content = isCsv ? buildIssuesCsv(data) : buildIssuesJson(data);
      final mime = isCsv ? 'text/csv' : 'application/json';
      final exportedMsg = context.t(
        'reports.exported',
        variables: {'format': format.toUpperCase()},
      );
      final copiedMsg = context.t(
        'reports.copied',
        variables: {'format': format.toUpperCase()},
      );
      if (kIsWeb) {
        final uri = Uri.parse(
          'data:$mime;charset=utf-8,${Uri.encodeComponent(content)}',
        );
        await launchUrl(uri, webOnlyWindowName: '_blank');
        _toast(exportedMsg);
      } else {
        await Clipboard.setData(ClipboardData(text: content));
        _toast(copiedMsg);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  IssueExportData _buildExportData(
    _RefData ref,
    List<Issue> allIssues,
    ServerMeta? meta,
    Uint8List? logoPng,
  ) {
    final list = _filtered(allIssues);
    final names = ref.names;
    final projectNames = ref.projectNames;

    IssueExportRow rowOf(Issue i) => (
      id: i.readableId,
      title: i.title,
      status: stateLabel(i.state),
      priority: _enumLabel(context, 'priority', i.priority.toUpperCase()),
      assignee: (i.assigneeId?.isNotEmpty ?? false)
          ? (names[i.assigneeId] ?? i.assigneeId!)
          : context.t('issues.unassigned'),
      project: projectNames[i.projectId] ?? i.projectId,
      type: _enumLabel(context, 'type', i.type.toUpperCase()),
      due: i.dueDate?.toIso8601String().substring(0, 10) ?? '',
    );

    final grouped = _grouping != IssueGrouping.none;
    final List<IssueExportGroup> groups;
    if (grouped) {
      groups = [
        for (final s in _sections(list, ref))
          (
            title: _sectionLabel(s.key, ref),
            rows: [for (final i in s.issues) rowOf(i)],
          ),
      ];
    } else {
      groups = [
        (title: '', rows: [for (final i in list) rowOf(i)]),
      ];
    }

    final scope = widget.projectId != null
        ? (projectNames[widget.projectId] ?? context.t('nav.issues'))
        : context.t('board.allProjects');

    return IssueExportData(
      orgName: (meta?.organizationName?.trim().isNotEmpty ?? false)
          ? meta!.organizationName!.trim()
          : 'Hinata',
      logoBytes: logoPng,
      scopeLabel: scope,
      generatedAt: DateTime.now(),
      groups: groups,
      grouped: grouped,
      groupByLabel: grouped
          ? '${context.t('board.groupBy')}: ${_groupingLabel(context, _grouping)}'
          : null,
      filterSummary: _filterSummary(names, projectNames),
    );
  }

  /// A plain-text label for a group key (no widgets) — used by the PDF/CSV/JSON
  /// export, which can't render header widgets.
  String _sectionLabel(String key, _RefData data) => switch (_grouping) {
    IssueGrouping.state => stateLabel(key),
    IssueGrouping.priority => _enumLabel(context, 'priority', key),
    IssueGrouping.type => _enumLabel(context, 'type', key),
    IssueGrouping.assignee =>
      key == _kNone ? context.t('issues.unassigned') : (data.names[key] ?? key),
    IssueGrouping.project => data.projectNames[key] ?? key,
    IssueGrouping.none => '',
  };

  List<String> _filterSummary(
    Map<String, String> names,
    Map<String, String> projectNames,
  ) {
    final out = <String>[];
    String join(String prefix, Iterable<String> values) =>
        '$prefix: ${values.join(', ')}';
    if (_filter.states.isNotEmpty) {
      out.add(
        join(context.t('issues.colStatus'), _filter.states.map(stateLabel)),
      );
    }
    if (_filter.priorities.isNotEmpty) {
      out.add(
        join(
          context.t('issues.colPriority'),
          _filter.priorities.map((p) => _enumLabel(context, 'priority', p)),
        ),
      );
    }
    if (_filter.types.isNotEmpty) {
      out.add(
        join(
          context.t('issues.type'),
          _filter.types.map((t) => _enumLabel(context, 'type', t)),
        ),
      );
    }
    if (_filter.assignees.isNotEmpty) {
      out.add(
        join(
          context.t('issues.colAssignee'),
          _filter.assignees.map(
            (a) => a == IssueFilter.noAssignee
                ? context.t('issues.unassigned')
                : (names[a] ?? a),
          ),
        ),
      );
    }
    if (_filter.projects.isNotEmpty) {
      out.add(
        join(
          context.t('issues.project'),
          _filter.projects.map((p) => projectNames[p] ?? p),
        ),
      );
    }
    if (_filter.archivedOnly) {
      out.add(context.t('issues.filterArchived'));
    }
    if (_timeRange.isActive) {
      out.add(
        '${context.t('issues.timeRange')}: ${_timeLabel(context, _timeRange)}',
      );
    }
    return out;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.t(message))));
  }

  // ── build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PagedCubit<Issue>, PagedState<Issue>>(
      bloc: _issues,
      builder: (context, state) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final ref = _ref ?? _emptyRef;
        final all = state.items;
        final list = _filtered(all);
        final sections = _sections(list, ref);

        // Filters/grouping/sorting run client-side over the loaded pages, so
        // while a filter is active we eagerly pull the remaining pages in the
        // background — otherwise a match living beyond the first page would
        // never surface (the user can't scroll a list that filtered to empty).
        if (_hasActiveView && state.hasMore && !state.isLoadingMore) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _issues.loadMore();
          });
        }

        // True while an active filter is still pulling pages but has matched
        // nothing yet — show a spinner instead of a premature "no results".
        final searchingMore =
            list.isEmpty &&
            (state.isLoadingMore || (_hasActiveView && state.hasMore));

        return RefreshIndicator(
          onRefresh: _reload,
          color: AppColors.accent,
          edgeOffset: context.topGutter,
          child: AsyncView(
            isLoading:
                state.isLoading || (_refLoading && _ref == null && !_refError),
            hasData: state.hasData && (_ref != null || _refError),
            errorKey: state.errorKey,
            onRetry: _reload,
            builder: (context) => CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    context.pageGutter,
                    24 + context.topGutter,
                    context.pageGutter,
                    14,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: PageHead(
                      title: context.t('nav.issues'),
                      subtitle: _subtitle(list.length, state.total),
                      actions: [
                        !isNativeApp
                            ? PrimaryButton(
                                label: context.t('issues.new'),
                                collapseToIcon: true,
                                onPressed: () async {
                                  final created = await showIssueForm(
                                    context,
                                    projectId: widget.projectId,
                                  );
                                  if (created != null) _reload();
                                },
                              )
                            : Tooltip(
                                message: context.t('issues.new'),
                                child: GlassButton.custom(
                                  onTap: () async {
                                    final created = await showIssueForm(
                                      context,
                                      projectId: widget.projectId,
                                    );
                                    if (created != null) _reload();
                                  },
                                  width: context.isCompact ? 46 : null,
                                  height: 46,
                                  shape: !context.isCompact
                                      ? const LiquidRoundedSuperellipse(
                                          borderRadius: 15,
                                        )
                                      : const LiquidOval(),
                                  useOwnLayer: true,
                                  settings: dark
                                      ? kNavGlassDark
                                      : kNavGlassLight,
                                  glowColor: AppColors.accent,
                                  stretch: 0.15,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Icon(
                                          LucideIcons.plus,
                                          size: 18,
                                          color: dark
                                              ? AppColors.inkDark
                                              : AppColors.ink,
                                        ),
                                        if (!context.isCompact) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            context.t('issues.new'),
                                            style: TextStyle(
                                              fontFamily: AppTheme.fontBrand,
                                              fontSize: 17,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.3,
                                              color: dark
                                                  ? AppColors.inkDark
                                                  : AppColors.ink,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
                // toolbar: group by · filter · time range · export
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    context.pageGutter,
                    0,
                    context.pageGutter,
                    14,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _Toolbar(
                      grouping: _grouping,
                      onGrouping: (g) => setState(() {
                        _grouping = g;
                        _collapsed.clear();
                      }),
                      filterCount: _filter.activeCount,
                      filterKey: _filterKey,
                      onFilter: () => _openFilter(ref, all),
                      timeRange: _timeRange,
                      onTimeRange: (r) => setState(() => _timeRange = r),
                      onExport: _export,
                      exporting: _exporting,
                    ),
                  ),
                ),
                if (list.isEmpty && !searchingMore)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.pageGutter,
                        vertical: 40,
                      ),
                      child: HiveEmptyState(
                        title: context.t('nav.issues'),
                        message: _hasActiveView
                            ? context.t('issues.emptyFiltered')
                            : context.t('issues.empty'),
                        action: _hasActiveView
                            ? OutlinedButton(
                                onPressed: () {
                                  final refetch = _filter.archivedOnly;
                                  setState(() {
                                    _filter = IssueFilter.empty;
                                    _timeRange = IssueTimeRange.none;
                                  });
                                  if (refetch) _issues.load();
                                },
                                child: Text(context.t('board.clearFilters')),
                              )
                            : null,
                      ),
                    ),
                  )
                else if (list.isNotEmpty)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      context.pageGutter,
                      0,
                      context.pageGutter,
                      14,
                    ),
                    sliver: SliverList.list(
                      children: _grouping == IssueGrouping.none
                          ? _flatRows(list, ref.names, ref.avatars, ref.palette)
                          : _groupedRows(
                              sections,
                              ref.names,
                              ref.avatars,
                              ref.palette,
                            ),
                    ),
                  ),
                // Infinite-scroll footer: the standard HiveLoader while the next
                // page (or a filter's background sweep) is loading.
                if (state.isLoadingMore || searchingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: HiveLoader(size: 30)),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: context.pageGutter + context.bottomGutter,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool get _hasActiveView => !_filter.isEmpty || _timeRange.isActive;

  /// [shown] is the number of currently-matched rows; [total] is the backend's
  /// full count (so it reflects everything, not just the pages loaded so far).
  String _subtitle(int shown, int total) {
    if (_hasActiveView) {
      return context.t(
        'issues.countFiltered',
        variables: {'count': '$shown', 'total': '$total'},
      );
    }
    return context.t('issues.countSummary', variables: {'count': '$total'});
  }

  List<Widget> _flatRows(
    List<Issue> list,
    Map<String, String> names,
    Map<String, String> avatars,
    ProjectPalette palette,
  ) => [
    if (!context.isCompact) const _IssueTableHeader(),
    for (final issue in list)
      Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: IssueRow(
          issue: issue,
          assignee: names[issue.assigneeId],
          assigneeAvatar: avatars[issue.assigneeId],
          palette: palette,
          onChanged: _reload,
        ),
      ),
  ];

  List<Widget> _groupedRows(
    List<_Section> sections,
    Map<String, String> names,
    Map<String, String> avatars,
    ProjectPalette palette,
  ) {
    final rows = <Widget>[];
    for (final section in sections) {
      final collapsed = _collapsed.contains(section.key);
      rows.add(
        _CollapsibleHeader(
          collapsed: collapsed,
          header: section.header,
          onTap: () => setState(() {
            if (!_collapsed.remove(section.key)) _collapsed.add(section.key);
          }),
        ),
      );
      if (!collapsed) {
        for (final issue in section.issues) {
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: IssueRow(
                issue: issue,
                assignee: names[issue.assigneeId],
                assigneeAvatar: avatars[issue.assigneeId],
                palette: palette,
                onChanged: _reload,
              ),
            ),
          );
        }
      }
      rows.add(SizedBox(height: collapsed ? 6 : 10));
    }
    return rows;
  }
}

/// Sentinel group key for "no assignee".
const _kNone = '__none__';

/// Rank of [value] within [order] (its index), or [order].length when absent so
/// unknown codes sort after the known ones.
int _rankIn(List<String> order, String value) {
  final i = order.indexOf(value);
  return i == -1 ? order.length : i;
}

