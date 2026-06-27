import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/hinata_repository.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/project_palette.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';
import '../reports/logo_raster.dart';
import 'issue_detail_sheet.dart';
import 'issue_export.dart';
import 'issue_filter.dart';
import 'issue_filter_popup.dart';
import 'issue_form.dart';

typedef _IssuesData = ({
  List<Issue> issues,
  int total,
  Map<String, String> names,
  Map<String, String> avatars,
  Map<String, String> projectNames,
  List<String> stateOrder,
  ProjectPalette palette,
});

class IssuesScreen extends StatefulWidget {
  const IssuesScreen({super.key, this.projectId});

  final String? projectId;

  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  late FetchCubit<_IssuesData> _cubit;

  IssueFilter _filter = IssueFilter.empty;
  IssueGrouping _grouping = IssueGrouping.none;
  IssueTimeRange _timeRange = IssueTimeRange.none;

  /// Group keys currently collapsed in the grouped view (mirrors the board's
  /// swimlane collapse). Cleared whenever the grouping dimension changes.
  final Set<String> _collapsed = {};

  final GlobalKey _filterKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _cubit = FetchCubit<_IssuesData>(() async {
      final repo = context.read<HinataRepository>();
      final results = await Future.wait([
        repo.issues(projectId: widget.projectId, size: 500),
        repo.users(),
        repo.projects(),
      ]);
      final page = results[0] as ({List<Issue> issues, int total});
      final users = results[1] as List<DirectoryUser>;
      final projects = results[2] as List<Project>;
      final names = {for (final u in users) u.id: u.displayName};
      final avatars = {
        for (final u in users)
          if (u.avatarUrl != null && u.avatarUrl!.isNotEmpty) u.id: u.avatarUrl!,
      };
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
      return (
        issues: page.issues,
        total: page.total,
        names: names,
        avatars: avatars,
        projectNames: {for (final p in projects) p.id: p.name},
        stateOrder: stateOrder,
        palette: ProjectPalette.fromProjects(projects),
      );
    })..load();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
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
  List<_Section> _sections(List<Issue> list, _IssuesData data) {
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

  int Function(String, String) _keyComparator(_IssuesData data) {
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

  Widget _groupHeader(String key, int count, _IssuesData data) {
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
          leading = Icon(LucideIcons.userX, size: 18, color: AppColors.inkFaint);
          label = context.t('issues.unassigned');
        } else {
          final name = data.names[key] ?? key;
          leading = HiveAvatar(name: name, imageUrl: data.avatars[key], size: 22);
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

  void _openFilter(_IssuesData data) => openIssueFilter(
    context,
    anchorKey: _filterKey,
    filter: _filter,
    options: IssueFilterOptions.from(data.issues),
    names: data.names,
    avatars: data.avatars,
    projectNames: data.projectNames,
    onChanged: (f) => setState(() => _filter = f),
  );

  Future<void> _export(String format) async {
    final repo = context.read<HinataRepository>();
    if (format == 'pdf') {
      final cached = context.read<AppConfigBloc>().state.meta;
      ServerMeta? meta = cached;
      try {
        meta = await repo.meta();
      } catch (_) {
        meta = cached;
      }
      Uint8List? logoPng;
      final logoAsset = await repo.organizationLogo();
      if (logoAsset != null) {
        logoPng = await logoToPng(bytes: logoAsset.bytes, isSvg: logoAsset.isSvg);
      }
      if (!mounted) return;
      final failMsg = context.t('reports.exportFailed');
      try {
        await shareIssuesPdf(_buildExportData(meta, logoPng));
      } catch (_) {
        _toast(failMsg);
      }
      return;
    }
    final data = _buildExportData(null, null);
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
  }

  IssueExportData _buildExportData(ServerMeta? meta, Uint8List? logoPng) {
    final data = _cubit.state.data;
    final list = data == null ? const <Issue>[] : _filtered(data.issues);
    final names = data?.names ?? const {};
    final projectNames = data?.projectNames ?? const {};

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
    if (grouped && data != null) {
      groups = [
        for (final s in _sections(list, data))
          (title: _sectionLabel(s.key, data), rows: [for (final i in s.issues) rowOf(i)]),
      ];
    } else {
      groups = [(title: '', rows: [for (final i in list) rowOf(i)])];
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
  String _sectionLabel(String key, _IssuesData data) => switch (_grouping) {
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
      out.add(join(context.t('issues.colStatus'), _filter.states.map(stateLabel)));
    }
    if (_filter.priorities.isNotEmpty) {
      out.add(join(
        context.t('issues.colPriority'),
        _filter.priorities.map((p) => _enumLabel(context, 'priority', p)),
      ));
    }
    if (_filter.types.isNotEmpty) {
      out.add(join(
        context.t('issues.type'),
        _filter.types.map((t) => _enumLabel(context, 'type', t)),
      ));
    }
    if (_filter.assignees.isNotEmpty) {
      out.add(join(
        context.t('issues.colAssignee'),
        _filter.assignees.map(
          (a) => a == IssueFilter.noAssignee
              ? context.t('issues.unassigned')
              : (names[a] ?? a),
        ),
      ));
    }
    if (_filter.projects.isNotEmpty) {
      out.add(join(
        context.t('issues.project'),
        _filter.projects.map((p) => projectNames[p] ?? p),
      ));
    }
    if (_timeRange.isActive) {
      out.add('${context.t('issues.timeRange')}: ${_timeLabel(context, _timeRange)}');
    }
    return out;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<FetchCubit<_IssuesData>, FetchState<_IssuesData>>(
        builder: (context, state) {
          final data = state.data;
          final all = data?.issues ?? const <Issue>[];
          final palette = data?.palette ?? ProjectPalette.empty;
          final names = data?.names ?? const <String, String>{};
          final avatars = data?.avatars ?? const <String, String>{};
          final list = _filtered(all);
          final sections = data == null ? const <_Section>[] : _sections(list, data);

          return RefreshIndicator(
            onRefresh: _cubit.load,
            color: AppColors.accent,
            edgeOffset: context.topGutter,
            child: AsyncView(
              isLoading: state.isLoading,
              hasData: state.hasData,
              errorKey: state.errorKey,
              onRetry: _cubit.load,
              builder: (context) => CustomScrollView(
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
                        subtitle: _subtitle(list.length, all.length),
                        actions: [
                          PrimaryButton(
                            label: context.t('issues.new'),
                            collapseToIcon: true,
                            onPressed: () async {
                              final created = await showIssueForm(
                                context,
                                projectId: widget.projectId,
                              );
                              if (created != null) _cubit.load();
                            },
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
                        onFilter: data == null ? null : () => _openFilter(data),
                        timeRange: _timeRange,
                        onTimeRange: (r) => setState(() => _timeRange = r),
                        onExport: data == null ? null : _export,
                      ),
                    ),
                  ),
                  if (list.isEmpty)
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
                                  onPressed: () => setState(() {
                                    _filter = IssueFilter.empty;
                                    _timeRange = IssueTimeRange.none;
                                  }),
                                  child: Text(context.t('board.clearFilters')),
                                )
                              : null,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        context.pageGutter,
                        0,
                        context.pageGutter,
                        context.pageGutter + context.bottomGutter,
                      ),
                      sliver: SliverList.list(
                        children: _grouping == IssueGrouping.none
                            ? _flatRows(list, names, avatars, palette)
                            : _groupedRows(sections, names, avatars, palette),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  bool get _hasActiveView => !_filter.isEmpty || _timeRange.isActive;

  String _subtitle(int shown, int total) {
    if (_hasActiveView && shown != total) {
      return context.t(
        'issues.countFiltered',
        variables: {'count': '$shown', 'total': '$total'},
      );
    }
    return context.t('issues.countSummary', variables: {'count': '$shown'});
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

/// One grouped section: a stable [key], a rendered [header] and its issues.
class _Section {
  const _Section({required this.key, required this.header, required this.issues});
  final String key;
  final Widget header;
  final List<Issue> issues;
}

// ─────────────────────────── toolbar ────────────────────────────────────

/// The Issues controls row: Group-by + Filter + Time-range on the left (scrolls
/// horizontally when space is tight so it never overflows), Export pinned right.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.grouping,
    required this.onGrouping,
    required this.filterCount,
    required this.filterKey,
    required this.onFilter,
    required this.timeRange,
    required this.onTimeRange,
    required this.onExport,
  });

  final IssueGrouping grouping;
  final ValueChanged<IssueGrouping> onGrouping;
  final int filterCount;
  final GlobalKey filterKey;
  final VoidCallback? onFilter;
  final IssueTimeRange timeRange;
  final ValueChanged<IssueTimeRange> onTimeRange;
  final ValueChanged<String>? onExport;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _GroupByButton(value: grouping, onChanged: onGrouping),
                const SizedBox(width: 10),
                _FilterButton(
                  key: filterKey,
                  count: filterCount,
                  onTap: onFilter,
                ),
                const SizedBox(width: 10),
                _TimeRangeButton(value: timeRange, onChanged: onTimeRange),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (onExport != null) _ExportButton(onSelected: onExport!),
      ],
    );
  }
}

String _groupingLabel(BuildContext context, IssueGrouping g) => switch (g) {
  IssueGrouping.none => context.t('issues.group.none'),
  IssueGrouping.state => context.t('issues.group.state'),
  IssueGrouping.priority => context.t('issues.group.priority'),
  IssueGrouping.assignee => context.t('issues.group.assignee'),
  IssueGrouping.project => context.t('issues.group.project'),
  IssueGrouping.type => context.t('issues.group.type'),
};

/// Icon for a grouping dimension — shown left of each menu row and as the whole
/// button on compact (icon-only) layouts. Mirrors the filter popup's scope
/// icons so the same dimension reads identically across both controls.
IconData _groupingIcon(IssueGrouping g) => switch (g) {
  IssueGrouping.none => LucideIcons.rows3,
  IssueGrouping.state => LucideIcons.circleDot,
  IssueGrouping.priority => LucideIcons.flag,
  IssueGrouping.assignee => LucideIcons.user,
  IssueGrouping.project => LucideIcons.folder,
  IssueGrouping.type => LucideIcons.shapes,
};

class _GroupByButton extends StatelessWidget {
  const _GroupByButton({required this.value, required this.onChanged});

  final IssueGrouping value;
  final ValueChanged<IssueGrouping> onChanged;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final active = value != IssueGrouping.none;
    return GlassPopupMenu<IssueGrouping>(
      value: value,
      width: 230,
      onSelected: onChanged,
      items: [
        for (final g in IssueGrouping.values)
          GlassMenuItem(
            value: g,
            label: _groupingLabel(context, g),
            leading: Icon(_groupingIcon(g), size: 18),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(
            color: active ? AppColors.accentLine : AppColors.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _groupingIcon(value),
              size: 16,
              color: active ? AppColors.accentStrong : AppColors.inkSoft,
            ),
            if (!compact) ...[
              const SizedBox(width: 7),
              Text(
                active
                    ? _groupingLabel(context, value)
                    : context.t('board.groupBy'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                LucideIcons.chevronDown,
                size: 15,
                color: AppColors.inkFaint,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// White pill that opens the glass filter popup; shows an amber badge with the
/// active-criteria count. Its [key] anchors the popup's position.
class _FilterButton extends StatelessWidget {
  const _FilterButton({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(
              color: count > 0 ? AppColors.accentLine : AppColors.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.slidersHorizontal,
                size: 16,
                color: count > 0 ? AppColors.accentStrong : AppColors.inkSoft,
              ),
              if (!context.isCompact) ...[
                const SizedBox(width: 7),
                Text(
                  context.t('board.filterButton'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (count > 0) ...[
                const SizedBox(width: 7),
                Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2A2410),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── time range ─────────────────────────────────

String _timeLabel(BuildContext context, IssueTimeRange r) {
  if (r.preset == IssueTimePreset.custom && r.custom != null) {
    String d(DateTime x) =>
        '${x.day.toString().padLeft(2, '0')}.${x.month.toString().padLeft(2, '0')}.';
    return '${d(r.custom!.start)} – ${d(r.custom!.end)}';
  }
  return switch (r.preset) {
    IssueTimePreset.all => context.t('issues.timeRange'),
    IssueTimePreset.overdue => context.t('issues.time.overdue'),
    IssueTimePreset.today => context.t('issues.time.today'),
    IssueTimePreset.thisWeek => context.t('issues.time.thisWeek'),
    IssueTimePreset.thisMonth => context.t('issues.time.thisMonth'),
    IssueTimePreset.last7 => context.t('issues.time.last7'),
    IssueTimePreset.last30 => context.t('issues.time.last30'),
    IssueTimePreset.next7 => context.t('issues.time.next7'),
    IssueTimePreset.next30 => context.t('issues.time.next30'),
    IssueTimePreset.custom => context.t('issues.time.custom'),
  };
}

class _TimeRangeButton extends StatelessWidget {
  const _TimeRangeButton({required this.value, required this.onChanged});

  final IssueTimeRange value;
  final ValueChanged<IssueTimeRange> onChanged;

  Future<void> _onSelected(BuildContext context, IssueTimePreset preset) async {
    if (preset == IssueTimePreset.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 5),
        initialDateRange: value.custom,
        builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.accentStrong,
            ),
          ),
          child: child!,
        ),
      );
      if (picked != null) {
        onChanged(
          IssueTimeRange(preset: IssueTimePreset.custom, custom: picked),
        );
      }
      return;
    }
    onChanged(IssueTimeRange(preset: preset));
  }

  @override
  Widget build(BuildContext context) {
    final active = value.isActive;
    return GlassPopupMenu<IssueTimePreset>(
      value: value.preset,
      width: 230,
      onSelected: (p) => _onSelected(context, p),
      items: [
        GlassMenuItem(
          value: IssueTimePreset.all,
          label: context.t('issues.time.all'),
          leading: const Icon(LucideIcons.infinity, size: 18),
        ),
        GlassMenuItem(
          value: IssueTimePreset.overdue,
          label: context.t('issues.time.overdue'),
          leading: const Icon(LucideIcons.triangleAlert, size: 18),
          dividerAbove: true,
        ),
        GlassMenuItem(
          value: IssueTimePreset.today,
          label: context.t('issues.time.today'),
          leading: const Icon(LucideIcons.calendarClock, size: 18),
        ),
        GlassMenuItem(
          value: IssueTimePreset.thisWeek,
          label: context.t('issues.time.thisWeek'),
          leading: const Icon(LucideIcons.calendarDays, size: 18),
        ),
        GlassMenuItem(
          value: IssueTimePreset.thisMonth,
          label: context.t('issues.time.thisMonth'),
          leading: const Icon(LucideIcons.calendarRange, size: 18),
        ),
        GlassMenuItem(
          value: IssueTimePreset.last7,
          label: context.t('issues.time.last7'),
          leading: const Icon(LucideIcons.history, size: 18),
          dividerAbove: true,
        ),
        GlassMenuItem(
          value: IssueTimePreset.last30,
          label: context.t('issues.time.last30'),
          leading: const Icon(LucideIcons.history, size: 18),
        ),
        GlassMenuItem(
          value: IssueTimePreset.next7,
          label: context.t('issues.time.next7'),
          leading: const Icon(LucideIcons.calendarPlus, size: 18),
        ),
        GlassMenuItem(
          value: IssueTimePreset.next30,
          label: context.t('issues.time.next30'),
          leading: const Icon(LucideIcons.calendarPlus, size: 18),
        ),
        GlassMenuItem(
          value: IssueTimePreset.custom,
          label: context.t('issues.time.custom'),
          leading: const Icon(LucideIcons.calendarSearch, size: 18),
          dividerAbove: true,
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(
            color: active ? AppColors.accentLine : AppColors.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.calendar,
              size: 16,
              color: active ? AppColors.accentStrong : AppColors.inkSoft,
            ),
            if (!context.isCompact) ...[
              const SizedBox(width: 7),
              Text(
                _timeLabel(context, value),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.accentStrong : AppColors.ink,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                LucideIcons.chevronDown,
                size: 15,
                color: AppColors.inkFaint,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.onSelected});
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return GlassPopupMenu<String>(
      value: '',
      onSelected: onSelected,
      items: [
        GlassMenuItem(
          value: 'pdf',
          label: context.t('reports.exportPdf'),
          leading: const Icon(LucideIcons.fileText, size: 18),
        ),
        GlassMenuItem(
          value: 'csv',
          label: context.t('reports.exportCsv'),
          leading: const Icon(LucideIcons.table, size: 18),
        ),
        GlassMenuItem(
          value: 'json',
          label: context.t('reports.exportJson'),
          leading: const Icon(LucideIcons.braces, size: 18),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.download, size: 16, color: AppColors.ink),
            if (!context.isCompact) ...[
              const SizedBox(width: 8),
              Text(
                context.t('reports.export'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── group header / dot ─────────────────────────

/// A grouped-section header that toggles its rows on tap, with a chevron that
/// rotates to point right when collapsed — the same affordance as the board's
/// swimlanes.
class _CollapsibleHeader extends StatelessWidget {
  const _CollapsibleHeader({
    required this.collapsed,
    required this.header,
    required this.onTap,
  });

  final bool collapsed;
  final Widget header;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: AnimatedRotation(
                turns: collapsed ? -0.25 : 0,
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  LucideIcons.chevronDown,
                  size: 18,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
            Flexible(child: header),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.leading,
    required this.label,
    required this.count,
  });

  final Widget leading;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Localised label for an enum-like [code] under [prefix] (`type`/`priority`),
/// humanising the raw code when no translation exists.
String _enumLabel(BuildContext context, String prefix, String code) {
  final key = '$prefix.${code.toLowerCase()}';
  final value = context.t(key);
  if (value != key) return value;
  return code
      .split(RegExp(r'[_ ]'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

// ───────────────────────────── table ────────────────────────────────────

class _IssueTableHeader extends StatelessWidget {
  const _IssueTableHeader();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: AppColors.inkFaint,
    );
    Widget cell(String key, {int? flex, double? width}) {
      final text = Text(
        context.t(key).toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
      if (width != null) return SizedBox(width: width, child: text);
      return Expanded(flex: flex!, child: text);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          cell('issues.colId', width: 76),
          const SizedBox(width: 12),
          cell('issues.colTitle', flex: 5),
          const SizedBox(width: 12),
          cell('issues.colStatus', flex: 3),
          const SizedBox(width: 8),
          cell('issues.colPriority', flex: 3),
          const SizedBox(width: 8),
          cell('issues.colAssignee', flex: 3),
          const SizedBox(width: 8),
          cell('issues.colDue', width: 60),
          const SizedBox(width: 18),
        ],
      ),
    );
  }
}

class IssueRow extends StatelessWidget {
  const IssueRow({
    super.key,
    required this.issue,
    this.assignee,
    this.assigneeAvatar,
    this.onTap,
    this.palette,
  });

  final Issue issue;
  final String? assignee;
  final String? assigneeAvatar;
  final VoidCallback? onTap;
  final ProjectPalette? palette;

  @override
  Widget build(BuildContext context) {
    final due = dueLabel(issue.dueDate);
    final compact = context.isCompact;
    final name = assignee ?? '';

    final tap =
        onTap ??
        () => showIssueDetailSheet(
          context,
          issueId: issue.id,
          onChanged: () => context.read<FetchCubit<_IssuesData>>().load(),
        );

    if (compact) {
      return SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: tap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IdMono(issue.readableId),
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: PriorityFlag(priority: issue.priority, withLabel: true),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TypeGlyph(type: issue.type),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    issue.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: StateDotBadge(
                    state: issue.state,
                    color: palette?.stateColor(issue.state),
                  ),
                ),
                if (name.isNotEmpty)
                  HiveAvatar(name: name, imageUrl: assigneeAvatar, size: 22),
                if (due != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    due.text,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 12,
                      color: due.late ? AppColors.danger : AppColors.inkSoft,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      onTap: tap,
      child: Row(
        children: [
          SizedBox(width: 76, child: IdMono(issue.readableId)),
          const SizedBox(width: 12),
          // title
          Expanded(
            flex: 5,
            child: Row(
              children: [
                TypeGlyph(type: issue.type),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    issue.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (issue.tags.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: LabelTag(
                      issue.tags.first,
                      hue: palette?.labelHue(issue.tags.first),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StateDotBadge(
                state: issue.state,
                color: palette?.stateColor(issue.state),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: PriorityFlag(priority: issue.priority, withLabel: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: name.isEmpty
                ? Text('—', style: TextStyle(color: AppColors.inkFaint))
                : Row(
                    children: [
                      HiveAvatar(name: name, imageUrl: assigneeAvatar, size: 24),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          name.split(' ').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              due?.text ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 12,
                color: due != null && due.late
                    ? AppColors.danger
                    : AppColors.inkSoft,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Icon(LucideIcons.chevronRight, size: 18, color: AppColors.inkFaint),
        ],
      ),
    );
  }
}
