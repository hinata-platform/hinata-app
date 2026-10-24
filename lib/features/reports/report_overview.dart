import 'dart:async';
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
import '../../core/theme/app_type.dart';
import '../../core/widgets/budget/budget.dart';
import '../../core/widgets/figure_tiles.dart';
import '../../core/widgets/frosted_card.dart';
import '../../core/widgets/glass_filter_bar.dart'
    show GlassPill, kGlassControlHeight;
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
import 'report_overview_figures.dart';
import 'reports_cubit.dart';

part 'report_overview_charts.dart';

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

  /// Counts the loads; an answer to an older one, overtaken by a quicker
  /// switch of project or span, is dropped.
  int _request = 0;

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
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final overview = await _reports.overview(project.id, days: _span.days);
      // Names only for the people this report names, never the directory.
      final ids = overview.byAssignee.keys
          .where((id) => id.isNotEmpty && id != ReportOverview.unassigned)
          .toList();
      final named = ids.isEmpty ? const [] : await _reports.usersByIds(ids);
      if (!mounted || request != _request) return;
      setState(() {
        _overview = overview;
        _names = {for (final user in named) user.id: user.displayName};
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted || request != _request) return;
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
    final content = format == 'csv'
        ? overviewCsv(overview, _labelFor)
        : overviewJson(
            overview,
            projectName: project.name,
            label: _labelFor,
            generatedAt: DateTime.now(),
          );
    final mime = format == 'csv' ? 'text/csv' : 'application/json';
    if (kIsWeb) {
      await launchUrl(
        Uri.parse('data:$mime;charset=utf-8,${Uri.encodeComponent(content)}'),
        webOnlyWindowName: '_blank',
        mode: LaunchMode.externalApplication,
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

  String _labelFor(OverviewSection section, String key) => switch (section) {
    OverviewSection.state => stateLabel(key),
    OverviewSection.priority =>
      key.isEmpty ? key : key[0] + key.substring(1).toLowerCase(),
    OverviewSection.assignee =>
      key == ReportOverview.unassigned || key.isEmpty
          ? context.t('reports.unassigned')
          : (_names[key] ?? key),
    OverviewSection.activity => key,
  };

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
    final burn = burndownOf(overview, project.resolvedStates.toSet());
    final org = (server?.organizationName?.trim().isNotEmpty ?? false)
        ? server!.organizationName!.trim()
        : 'Hinata';
    final days = {'days': '${overview.days}'};
    PdfSection section(OverviewSection report, {bool minutes = false}) => (
      title: context.t(report.titleKey, variables: days),
      rows: [
        for (final item in _items(report, report.valuesOf(overview)))
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
        section(OverviewSection.state),
        section(OverviewSection.priority),
        section(OverviewSection.assignee),
        section(OverviewSection.activity, minutes: true),
      ],
      burndown: burn.points,
      burndownRemaining: burn.remaining,
      pdfTitleLabel: context.t('reports.pdf.title'),
      totalIssuesLabel: context.t('reports.totalIssues'),
      openOverDaysLabel: context.t('reports.pdf.openOverDays', variables: days),
      breakdownsLabel: context.t('reports.pdf.breakdowns'),
      burndownTitleLabel: context.t('reports.burndown', variables: days),
      openRemainingLabel: context.t(
        'reports.remaining',
        variables: {'count': '${burn.remaining}'},
      ),
      noDataLabel: context.t('reports.empty'),
      axisStartLabel: context.t('reports.windowStart', variables: days),
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

  List<LiquidItem> _items(OverviewSection report, Map<String, int> values) {
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final entry in entries)
        (
          label: _labelFor(report, entry.key),
          value: entry.value,
          color: switch (report) {
            OverviewSection.state => AppColors.stateColor(
              entry.key.toUpperCase(),
            ),
            OverviewSection.priority => AppColors.priorityColor(
              entry.key.toUpperCase(),
            ),
            OverviewSection.assignee => hiveHueColor(
              _names[entry.key] ?? entry.key,
            ),
            OverviewSection.activity => AppColors.accent,
          },
          limit: null,
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
        builder: (anchor) => _ControlPill(
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
        _ControlPill(
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
          builder: (anchor) => _ControlPill(
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
    final burn = burndownOf(overview, project.resolvedStates.toSet());
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
          child: _Trend(points: burn.points, days: overview.days),
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
            : LiquidColumns(
                items: _items(OverviewSection.state, overview.byState),
              ),
      ),
      FrostedCard(
        title: context.t('reports.overview.priorities'),
        child: overview.byPriority.isEmpty
            ? _empty()
            : LiquidRows(
                items: _items(OverviewSection.priority, overview.byPriority),
              ),
      ),
      FrostedCard(
        title: context.t('reports.overview.people'),
        child: overview.byAssignee.isEmpty
            ? _empty()
            : LiquidRows(
                items: _items(OverviewSection.assignee, overview.byAssignee),
              ),
      ),
      FrostedCard(
        title: context.t('reports.overview.activities'),
        child: overview.timePerActivity.isEmpty
            ? _empty()
            : LiquidRows(
                items: _items(
                  OverviewSection.activity,
                  overview.timePerActivity,
                ),
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

/// A control in the overview's row: a glass pill at the height of the app's
/// other controls, its label padded and centred in it.
class _ControlPill extends StatelessWidget {
  const _ControlPill({required this.child, this.onTap, this.active = false});

  final Widget child;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => GlassPill(
    height: kGlassControlHeight,
    active: active,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Center(widthFactor: 1, child: child),
    ),
  );
}
