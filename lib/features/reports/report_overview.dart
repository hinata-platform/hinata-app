import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/report_overview_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/dashboard_repository.dart';
import '../../core/repositories/meta_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_type.dart';
import '../../core/widgets/budget/budget.dart';
import '../../core/widgets/frosted_card.dart';
import '../../core/widgets/glass_filter_bar.dart' show GlassPill;
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/project_picker.dart';
import '../sprint/modals/glass_modal.dart'
    show GlassToastKind, anchorRectOfContext, showGlassToast;
import '../time/budget/budget_history_sheet.dart';
import '../time/budget/project_usage.dart';
import 'logo_raster.dart';
import 'report_pdf.dart';
import 'reports_cubit.dart';

/// The report page's overview of one project (HIN-157): how many issues it
/// holds and how that moved, where they stand, who works on them, where the
/// time goes and, with the extended module, how its budget fills.
///
/// One request for every figure (`/reports/overview`), where the old page made
/// five; the project is picked from the server-paged picker, never from a list
/// of every project. Drawn in the app's own material: frosted cards on the
/// ambient background, distributions as glass vessels filling with colour,
/// the trend as a honey area.
class ReportOverviewView extends StatelessWidget {
  const ReportOverviewView({
    super.key,
    required this.padding,
    this.initialProjectId,
  });

  /// Around the scroll, the bottom inset included.
  final EdgeInsets padding;

  /// The project to open on; the first the reader sees otherwise.
  final String? initialProjectId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => ReportsCubit(
      projects: context.read<ProjectRepository>(),
      users: context.read<UserRepository>(),
      dashboard: context.read<DashboardRepository>(),
      meta: context.read<MetaRepository>(),
    ),
    child: _Overview(padding: padding, initialProjectId: initialProjectId),
  );
}

class _Overview extends StatefulWidget {
  const _Overview({required this.padding, this.initialProjectId});

  final EdgeInsets padding;
  final String? initialProjectId;

  @override
  State<_Overview> createState() => _OverviewState();
}

enum _Span {
  month(30),
  quarter(90);

  const _Span(this.days);
  final int days;
}

class _OverviewState extends State<_Overview> {
  late final ReportsCubit _reports = context.read<ReportsCubit>();

  Project? _project;
  ReportOverview? _overview;
  Map<String, String> _names = const {};
  _Span _span = _Span.month;
  bool _loading = true;
  String? _error;
  bool _noProjects = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final project = await _reports.project(widget.initialProjectId);
      if (!mounted) return;
      if (project == null) {
        setState(() {
          _loading = false;
          _noProjects = true;
        });
        return;
      }
      _project = project;
      await _load();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _load() async {
    final project = _project;
    if (project == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final overview = await _reports.overview(project.id, days: _span.days);
      // Names only for the people this report names, never the directory.
      final ids = overview.byAssignee.keys
          .where((id) => id.isNotEmpty)
          .toList();
      final named = ids.isEmpty ? const [] : await _reports.usersByIds(ids);
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _names = {for (final user in named) user.id: user.displayName};
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _pickProject(BuildContext anchorContext) async {
    // Null means the pill is not on screen to hang the picker off.
    final anchor = anchorRectOfContext(anchorContext);
    if (anchor == null) return;
    final picked = await showProjectPicker(
      anchorContext,
      anchorRect: anchor,
      selected: {?_project?.id},
      titleKey: 'reports.pickProject',
      multi: false,
    );
    final project = picked?.firstOrNull;
    if (project == null || !mounted) return;
    _project = project;
    await _load();
  }

  // ── export ────────────────────────────────────────────────────────────────

  Future<void> _export(BuildContext anchorContext) async {
    final anchor = anchorRectOfContext(anchorContext);
    if (anchor == null) return;
    final format = await showGlassMenu<String>(
      context: context,
      anchorRect: anchor,
      value: '',
      items: [
        GlassMenuItem(
          value: 'pdf',
          label: context.t('reports.exportPdf'),
          leading: const Icon(LucideIcons.fileText, size: 18),
        ),
        GlassMenuItem(
          value: 'csv',
          label: context.t('reports.exportCsv'),
          leading: const Icon(LucideIcons.sheet, size: 18),
        ),
        GlassMenuItem(
          value: 'json',
          label: context.t('reports.exportJson'),
          leading: const Icon(LucideIcons.braces, size: 18),
        ),
      ],
    );
    if (format == null || !mounted) return;
    final overview = _overview;
    final project = _project;
    if (overview == null || project == null) return;
    if (format == 'pdf') return _exportPdf(overview, project);
    final content = format == 'csv' ? _csv(overview) : _json(overview, project);
    final mime = format == 'csv' ? 'text/csv' : 'application/json';
    if (kIsWeb) {
      await launchUrl(
        Uri.parse('data:$mime;charset=utf-8,${Uri.encodeComponent(content)}'),
        webOnlyWindowName: '_blank',
      );
      if (!mounted) return;
      _toast(
        context.t(
          'reports.exported',
          variables: {'format': format.toUpperCase()},
        ),
      );
    } else {
      await Clipboard.setData(ClipboardData(text: content));
      if (!mounted) return;
      _toast(
        context.t(
          'reports.copied',
          variables: {'format': format.toUpperCase()},
        ),
      );
    }
  }

  void _toast(String message, {GlassToastKind kind = GlassToastKind.success}) {
    if (mounted) showGlassToast(context, message, kind: kind);
  }

  Map<String, Map<String, int>> _sections(ReportOverview overview) => {
    'issues-by-state': overview.byState,
    'issues-by-priority': overview.byPriority,
    'issues-by-assignee': overview.byAssignee,
    'time-per-activity': overview.timePerActivity,
  };

  String _labelFor(String report, String key) => switch (report) {
    'issues-by-state' => stateLabel(key),
    'issues-by-priority' =>
      key.isEmpty ? key : key[0] + key.substring(1).toLowerCase(),
    'issues-by-assignee' =>
      key.isEmpty ? context.t('reports.unassigned') : (_names[key] ?? key),
    _ => key,
  };

  String _csv(ReportOverview overview) {
    String esc(String s) =>
        s.contains(',') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;
    final out = StringBuffer('report,label,value\n');
    _sections(overview).forEach((name, values) {
      for (final entry in values.entries) {
        out.writeln(
          '${esc(name)},${esc(_labelFor(name, entry.key))},${entry.value}',
        );
      }
    });
    return out.toString();
  }

  String _json(ReportOverview overview, Project project) =>
      const JsonEncoder.withIndent('  ').convert({
        'project': project.name,
        'days': overview.days,
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'reports': {
          for (final section in _sections(overview).entries)
            section.key: {
              for (final entry in section.value.entries)
                _labelFor(section.key, entry.key): entry.value,
            },
        },
      });

  Future<void> _exportPdf(ReportOverview overview, Project project) async {
    ServerMeta? server = context.read<AppConfigBloc>().state.meta;
    try {
      server = await _reports.meta();
    } on Object {
      // The branding cached at launch will do.
    }
    // Branding must never be the reason an export the reader asked for does
    // not happen: a logo that cannot be read leaves the masthead plain.
    Uint8List? logo;
    try {
      final asset = await _reports.organizationLogo();
      if (asset != null) {
        logo = await logoToPng(bytes: asset.bytes, isSvg: asset.isSvg);
      }
    } on Object {
      logo = null;
    }
    if (!mounted) return;
    final now = DateTime.now();
    final locale = Localizations.localeOf(context).toString();
    final burn = _burndown(overview, project);
    final org = (server?.organizationName?.trim().isNotEmpty ?? false)
        ? server!.organizationName!.trim()
        : 'Hinata';
    PdfSection section(
      String report,
      String titleKey, {
      bool minutes = false,
    }) => (
      title: context.t(titleKey),
      rows: [
        for (final item in _items(report, _sections(overview)[report]!))
          (
            label: item.label,
            value: item.value,
            display: minutes
                ? fmtDuration(context, item.value)
                : '${item.value}',
            color: item.color,
          ),
      ],
    );
    final data = ReportPdfData(
      orgName: org,
      logoBytes: logo,
      projectName: project.name,
      generatedAt: now,
      generatedAtLabel: context.t(
        'reports.pdf.generated',
        variables: {'date': DateFormat('MMM d, y · HH:mm', locale).format(now)},
      ),
      totalIssues: overview.totalIssues,
      sections: [
        section('issues-by-state', 'reports.issues-by-state'),
        section('issues-by-priority', 'reports.issues-by-priority'),
        section('issues-by-assignee', 'reports.issues-by-assignee'),
        section(
          'time-per-activity',
          'reports.time-per-activity',
          minutes: true,
        ),
      ],
      burndown: burn.points,
      burndownRemaining: burn.remaining,
      pdfTitleLabel: context.t('reports.pdf.title'),
      totalIssuesLabel: context.t('reports.totalIssues'),
      openLast30DaysLabel: context.t('reports.pdf.openLast30Days'),
      breakdownsLabel: context.t('reports.pdf.breakdowns'),
      burndownTitleLabel: context.t('reports.burndown'),
      openRemainingLabel: context.t(
        'reports.remaining',
        variables: {'count': '${burn.remaining}'},
      ),
      noDataLabel: context.t('reports.empty'),
      axis30dLabel: context.t('reports.windowStart'),
      axisTodayLabel: context.t('reports.windowEnd'),
      pageFooterTemplate: context.t(
        'reports.pdf.pageFooter',
        variables: {'org': org},
      ),
    );
    final failed = context.t('reports.exportFailed');
    try {
      await shareReportPdf(data);
    } on Object {
      _toast(failed, kind: GlassToastKind.error);
    }
  }

  // ── figures ───────────────────────────────────────────────────────────────

  /// The open issues over the span, anchored to today's count, with a
  /// straight line burning down to zero to read it against.
  ({List<({int day, double remaining, double ideal})> points, int remaining})
  _burndown(ReportOverview overview, Project project) {
    final resolved = project.resolvedStates.toSet();
    final openNow = overview.byState.entries
        .where((entry) => !resolved.contains(entry.key))
        .fold<int>(0, (sum, entry) => sum + entry.value);
    if (overview.trend.length < 2) {
      return (points: const [], remaining: openNow);
    }
    final running = <int>[];
    var run = 0;
    for (final point in overview.trend) {
      run += point.created - point.resolved;
      running.add(run);
    }
    final remaining = [
      for (final value in running)
        math.max(0, openNow - running.last + value).toDouble(),
    ];
    final start = remaining.first;
    final n = remaining.length;
    return (
      points: [
        for (var i = 0; i < n; i++)
          (
            day: i,
            remaining: remaining[i],
            ideal: n == 1 ? start : start * (1 - i / (n - 1)),
          ),
      ],
      remaining: openNow,
    );
  }

  List<LiquidItem> _items(String report, Map<String, int> values) {
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final entry in entries)
        (
          label: _labelFor(report, entry.key),
          value: entry.value,
          color: switch (report) {
            'issues-by-state' => AppColors.stateColor(entry.key.toUpperCase()),
            'issues-by-priority' => AppColors.priorityColor(
              entry.key.toUpperCase(),
            ),
            'issues-by-assignee' => hiveHueColor(
              _names[entry.key] ?? entry.key,
            ),
            _ => AppColors.accent,
          },
        ),
    ];
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_noProjects) ...[_controls(), const SizedBox(height: 18)],
            _content(),
          ],
        ),
      ),
    );
  }

  Widget _controls() => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Builder(
        builder: (anchor) => GlassPill(
          active: true,
          onTap: () => unawaited(_pickProject(anchor)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.folder, size: 15, color: AppColors.ink),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  _project?.name ?? context.t('reports.pickProject'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.label,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronDown, size: 14, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
      for (final span in _Span.values)
        GlassPill(
          active: _span == span,
          onTap: () {
            if (_span == span) return;
            setState(() => _span = span);
            unawaited(_load());
          },
          child: Text(
            context.t('reports.span.${span.name}'),
            style: TextStyle(
              fontSize: AppType.label,
              fontWeight: _span == span ? FontWeight.w700 : FontWeight.w500,
              color: AppColors.ink,
            ),
          ),
        ),
      if (_overview != null)
        Builder(
          builder: (anchor) => GlassPill(
            onTap: () => unawaited(_export(anchor)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.download, size: 15, color: AppColors.ink),
                const SizedBox(width: 6),
                Text(
                  context.t('reports.export'),
                  style: TextStyle(
                    fontSize: AppType.label,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _content() {
    if (_noProjects) {
      return HiveEmptyState(
        title: context.t('reports.title'),
        message: context.t('projects.empty'),
      );
    }
    if (_loading && _overview == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: HiveLoader()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Text(
              context.t(_error!),
              style: TextStyle(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => unawaited(_load()),
              child: Text(context.t('common.retry')),
            ),
          ],
        ),
      );
    }
    final overview = _overview!;
    final project = _project!;
    final burn = _burndown(overview, project);
    final module =
        context.read<AppConfigBloc>().state.meta?.advancedTimeTracking ?? false;
    final cards = <Widget>[
      if (burn.points.length >= 2)
        FrostedCard(
          title: context.t('reports.overview.trend'),
          trailing: Text(
            context.t(
              'reports.remaining',
              variables: {'count': '${burn.remaining}'},
            ),
            style: TextStyle(fontSize: AppType.label, color: AppColors.inkSoft),
          ),
          child: _Trend(points: burn.points),
        ),
      if (module)
        ProjectUsage(
          projectId: project.id,
          builder: (context, usage) => usage?.budget == null
              ? const SizedBox.shrink()
              : FrostedCard(
                  title: context.t('reports.overview.budget'),
                  child: BudgetMeter(
                    label: context.t('budget.timeBudget'),
                    gauge: usage!.budget,
                    footer: ProjectForecast(
                      projectId: project.id,
                      builder: (context, forecast) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (forecast != null)
                            ForecastLine(forecast: forecast),
                          TextButton.icon(
                            onPressed: () => showBudgetHistorySheet(
                              context,
                              projectId: project.id,
                              projectName: project.name,
                            ),
                            icon: const Icon(LucideIcons.chartArea, size: 16),
                            label: Text(context.t('budget.history.open')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      FrostedCard(
        title: context.t('reports.overview.states'),
        child: overview.byState.isEmpty
            ? _empty()
            : LiquidColumns(items: _items('issues-by-state', overview.byState)),
      ),
      FrostedCard(
        title: context.t('reports.overview.priorities'),
        child: overview.byPriority.isEmpty
            ? _empty()
            : LiquidRows(
                items: _items('issues-by-priority', overview.byPriority),
              ),
      ),
      FrostedCard(
        title: context.t('reports.overview.people'),
        child: overview.byAssignee.isEmpty
            ? _empty()
            : LiquidRows(
                items: _items('issues-by-assignee', overview.byAssignee),
              ),
      ),
      FrostedCard(
        title: context.t('reports.overview.activities'),
        child: overview.timePerActivity.isEmpty
            ? _empty()
            : LiquidRows(
                items: _items('time-per-activity', overview.timePerActivity),
                format: (minutes) => fmtDuration(context, minutes),
              ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Figures(overview: overview, open: burn.remaining),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final two = constraints.maxWidth >= 860;
            const gap = 18.0;
            final width = two
                ? (constraints.maxWidth - gap) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in cards) SizedBox(width: width, child: card),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _empty() => Text(
    context.t('reports.empty'),
    style: TextStyle(fontSize: AppType.label, color: AppColors.inkSoft),
  );
}

/// The four figures over the cards: open, new and done in the span, and the
/// time recorded in it.
class _Figures extends StatelessWidget {
  const _Figures({required this.overview, required this.open});

  final ReportOverview overview;
  final int open;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      (LucideIcons.inbox, context.t('reports.overview.open'), '$open'),
      (
        LucideIcons.circlePlus,
        context.t(
          'reports.overview.created',
          variables: {'days': '${overview.days}'},
        ),
        '${overview.createdInSpan}',
      ),
      (
        LucideIcons.circleCheck,
        context.t(
          'reports.overview.resolved',
          variables: {'days': '${overview.days}'},
        ),
        '${overview.resolvedInSpan}',
      ),
      (
        LucideIcons.timer,
        context.t(
          'reports.overview.recorded',
          variables: {'days': '${overview.days}'},
        ),
        fmtDuration(context, overview.minutesInSpan),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 860
            ? 4
            : constraints.maxWidth >= 420
            ? 2
            : 1;
        const gap = 14.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (icon, label, value) in tiles)
              SizedBox(
                width: width,
                child: Semantics(
                  label: '$label: $value',
                  excludeSemantics: true,
                  child: FrostedCard(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: AppColors.accentSoft,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(
                                icon,
                                size: 16,
                                color: AppColors.accentText,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: AppType.label,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          value,
                          style: TextStyle(
                            fontFamily: AppTheme.fontBrand,
                            fontSize: AppType.hero,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.6,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Open issues over the span as a honey area, with the straight line it would
/// follow to zero dashed beside it.
class _Trend extends StatelessWidget {
  const _Trend({required this.points});

  final List<({int day, double remaining, double ideal})> points;

  @override
  Widget build(BuildContext context) {
    final colors = HoneyGlass.liquid(BudgetLevel.within);
    final top = points
        .map((p) => math.max(p.remaining, p.ideal))
        .fold<double>(1, math.max);
    final last = (points.length - 1).toDouble();
    final label = TextStyle(
      fontSize: AppType.caption,
      color: AppColors.inkFaint,
    );
    return SizedBox(
      height: 190,
      child: LineChart(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 400),
        LineChartData(
          minX: 0,
          maxX: last,
          minY: 0,
          maxY: top * 1.12,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: math.max(1, (top / 4).ceilToDouble()),
            getDrawingHorizontalLine: (_) =>
                FlLine(color: AppColors.hairline2, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: math.max(1, (top / 4).ceilToDouble()),
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text('${value.round()}', style: label),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: last <= 0 ? 1 : last,
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(
                    value <= 0
                        ? context.t('reports.windowStart')
                        : context.t('reports.windowEnd'),
                    style: label,
                  ),
                ),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (final p in points) FlSpot(p.day.toDouble(), p.ideal),
              ],
              color: AppColors.inkFaint,
              barWidth: 1.4,
              dashArray: const [5, 5],
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: [
                for (final p in points) FlSpot(p.day.toDouble(), p.remaining),
              ],
              color: colors[2],
              barWidth: 2.6,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors[0].withValues(alpha: 0.55),
                    colors[1].withValues(alpha: 0.06),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
