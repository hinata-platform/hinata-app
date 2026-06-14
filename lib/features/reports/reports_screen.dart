import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/content_models.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import 'logo_raster.dart';
import 'report_pdf.dart';

/// Project insight dashboard: distribution reports (state / priority /
/// assignee / time-per-activity) rendered as v2 bar cards, with CSV/JSON export.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<Project> _projects = const [];
  Map<String, String> _userNames = const {};
  String? _projectId;

  // report name → (key → count)
  Map<String, Map<String, int>> _reports = const {};
  List<TrendPoint> _trend = const [];
  bool _loading = true;
  String? _error;

  static const _reportNames = [
    'issues-by-state',
    'issues-by-priority',
    'issues-by-assignee',
    'time-per-activity',
  ];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = context.read<HivoraRepository>();
    try {
      final results = await Future.wait([repo.projects(), repo.users()]);
      _projects = results[0] as List<Project>;
      final users = results[1] as List<DirectoryUser>;
      _userNames = {for (final u in users) u.id: u.displayName};
      if (_projects.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      _projectId ??= _projects.first.id;
      await _loadReports();
    } on ApiFailure catch (failure) {
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _loadReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = context.read<HivoraRepository>();
    final now = DateTime.now();
    final from =
        now.subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);
    final to = now.toIso8601String().substring(0, 10);
    try {
      final futures = _reportNames.map((name) {
        final query = <String, dynamic>{'projectId': _projectId};
        if (name == 'time-per-activity') {
          query['from'] = from;
          query['to'] = to;
        }
        return repo.report(name, query);
      }).toList();
      final results = await Future.wait([
        Future.wait(futures),
        repo.createdVsResolved(_projectId!, days: 30),
      ]);
      final maps = results[0] as List<Map<String, int>>;
      _trend = results[1] as List<TrendPoint>;
      _reports = {
        for (var i = 0; i < _reportNames.length; i++) _reportNames[i]: maps[i],
      };
      setState(() => _loading = false);
    } on ApiFailure catch (failure) {
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  String _projectName() =>
      _projects.where((p) => p.id == _projectId).firstOrNull?.name ?? '';

  // ── export ───────────────────────────────────────────────────────────────

  String _labelFor(String report, String key) => switch (report) {
        'issues-by-state' => stateLabel(key),
        'issues-by-priority' =>
          key.isEmpty ? key : key[0] + key.substring(1).toLowerCase(),
        'issues-by-assignee' => _userNames[key] ?? key,
        _ => key,
      };

  String _buildCsv() {
    final buf = StringBuffer('report,label,value\n');
    String esc(String s) =>
        s.contains(',') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;
    for (final name in _reportNames) {
      final map = _reports[name] ?? const {};
      for (final entry in map.entries) {
        buf.writeln(
            '${esc(name)},${esc(_labelFor(name, entry.key))},${entry.value}');
      }
    }
    return buf.toString();
  }

  String _buildJson() {
    final out = {
      'project': _projectName(),
      'generatedAt': DateTime.now().toIso8601String(),
      'reports': {
        for (final name in _reportNames)
          name: {
            for (final e in (_reports[name] ?? const {}).entries)
              _labelFor(name, e.key): e.value,
          },
      },
    };
    return const JsonEncoder.withIndent('  ').convert(out);
  }

  Future<void> _export(String format) async {
    if (format == 'pdf') {
      // Pull the freshest branding so a logo configured after app start is
      // picked up; fall back to whatever was cached at launch.
      final repo = context.read<HivoraRepository>();
      final cached = context.read<AppConfigBloc>().state.meta;
      ServerMeta? meta = cached;
      try {
        meta = await repo.meta();
      } catch (_) {
        meta = cached;
      }
      // Fetch the org logo through the server-side proxy (same-origin → no web
      // CORS) and rasterize SVGs to PNG before embedding.
      Uint8List? logoPng;
      final logoAsset = await repo.organizationLogo();
      if (logoAsset != null) {
        logoPng = await logoToPng(
            bytes: logoAsset.bytes, isSvg: logoAsset.isSvg);
      }
      if (!mounted) return;
      final failMsg = context.t('reports.exportFailed');
      try {
        await shareReportPdf(_buildPdfData(meta, logoPng));
      } catch (_) {
        _toast(failMsg);
      }
      return;
    }
    final isCsv = format == 'csv';
    final content = isCsv ? _buildCsv() : _buildJson();
    final mime = isCsv ? 'text/csv' : 'application/json';
    final exportedMsg = context.t('reports.exported',
        variables: {'format': format.toUpperCase()});
    final copiedMsg = context.t('reports.copied',
        variables: {'format': format.toUpperCase()});
    if (kIsWeb) {
      // Browser handles the data: URI as a download / preview tab.
      final uri = Uri.parse(
          'data:$mime;charset=utf-8,${Uri.encodeComponent(content)}');
      await launchUrl(uri, webOnlyWindowName: '_blank');
      _toast(exportedMsg);
    } else {
      await Clipboard.setData(ClipboardData(text: content));
      _toast(copiedMsg);
    }
  }

  ReportPdfData _buildPdfData(ServerMeta? meta, Uint8List? logoPng) {
    final byState = _reports['issues-by-state'] ?? const {};
    final total = byState.values.fold<int>(0, (s, v) => s + v);
    final bd = _burndown();

    PdfSection section(String report, String titleKey,
        {bool duration = false}) {
      final rows = [
        for (final d in _data(report))
          (
            label: d.label,
            value: d.value,
            display: duration ? fmtDuration(d.value) : '${d.value}',
            color: d.color,
          ),
      ];
      return (title: context.t(titleKey), rows: rows);
    }

    return ReportPdfData(
      orgName: (meta?.organizationName?.trim().isNotEmpty ?? false)
          ? meta!.organizationName!.trim()
          : 'Hivora',
      logoBytes: logoPng,
      projectName: _projectName(),
      generatedAt: DateTime.now(),
      totalIssues: total,
      sections: [
        section('issues-by-state', 'reports.issues-by-state'),
        section('issues-by-priority', 'reports.issues-by-priority'),
        section('issues-by-assignee', 'reports.issues-by-assignee'),
        section('time-per-activity', 'reports.time-per-activity',
            duration: true),
      ],
      burndown: bd.points,
      burndownRemaining: bd.remaining,
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: context.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(
            title: context.t('reports.title'),
            subtitle: _projectName().isEmpty
                ? context.t('reports.subtitle')
                : context.t('reports.forProject',
                    variables: {'project': _projectName()}),
            actions: [
              if (_projects.isNotEmpty && !_loading && _error == null)
                _ExportButton(onSelected: _export),
            ],
          ),
          const SizedBox(height: 16),
          if (_projects.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: _ProjectPicker(
                projects: _projects,
                selected: _projectId,
                onChanged: (value) {
                  _projectId = value;
                  _loadReports();
                },
              ),
            ),
          const SizedBox(height: 20),
          _body(context),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator(color: AppColors.navy)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.t(_error!),
                  style: TextStyle(color: AppColors.inkSoft)),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: _loadReports,
                  child: Text(context.t('common.retry'))),
            ],
          ),
        ),
      );
    }
    if (_projects.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
            child: Text(context.t('projects.empty'),
                style: TextStyle(color: AppColors.inkSoft))),
      );
    }

    final byState = _reports['issues-by-state'] ?? const {};
    final total = byState.values.fold<int>(0, (s, v) => s + v);
    final bd = _burndown();

    final cards = <Widget>[
      _SummaryCard(total: total, projectName: _projectName()),
      _BarReportCard(
        title: context.t('reports.issues-by-state'),
        data: _data('issues-by-state'),
      ),
      _BarReportCard(
        title: context.t('reports.issues-by-priority'),
        data: _data('issues-by-priority'),
      ),
      _BarReportCard(
        title: context.t('reports.issues-by-assignee'),
        data: _data('issues-by-assignee'),
      ),
      _BarReportCard(
        title: context.t('reports.time-per-activity'),
        data: _data('time-per-activity'),
        durationValues: true,
      ),
    ];

    final grid = LayoutBuilder(builder: (context, c) {
      final twoCol = c.maxWidth > 720;
      const gap = 18.0;
      final width = twoCol ? (c.maxWidth - gap) / 2 : c.maxWidth;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final card in cards) SizedBox(width: width, child: card),
        ],
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bd.points.length >= 2) ...[
          _BurndownCard(points: bd.points, remaining: bd.remaining),
          const SizedBox(height: 18),
        ],
        grid,
      ],
    );
  }

  // Cumulative open-issue trend over the window, anchored to the current
  // open count, with a linear "ideal" reference burning down to zero.
  ({List<({int day, double remaining, double ideal})> points, int remaining})
      _burndown() {
    if (_trend.length < 2) return (points: const [], remaining: 0);
    final project =
        _projects.where((p) => p.id == _projectId).firstOrNull;
    final resolvedStates = (project?.resolvedStates ?? const []).toSet();
    final byState = _reports['issues-by-state'] ?? const {};
    final openNow = byState.entries
        .where((e) => !resolvedStates.contains(e.key))
        .fold<int>(0, (s, e) => s + e.value);

    final cum = <int>[];
    var run = 0;
    for (final p in _trend) {
      run += p.created - p.resolved;
      cum.add(run);
    }
    final cumLast = cum.last;
    final remaining = [
      for (final c in cum)
        (openNow - cumLast + c).toDouble().clamp(0.0, double.infinity),
    ];
    final start = remaining.first;
    final n = remaining.length;
    final points = [
      for (var i = 0; i < n; i++)
        (
          day: i,
          remaining: remaining[i],
          ideal: n == 1 ? start : start * (1 - i / (n - 1)),
        ),
    ];
    return (points: points, remaining: openNow);
  }

  List<_Datum> _data(String report) {
    final map = _reports[report] ?? const {};
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.isEmpty
        ? 1
        : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    return [
      for (final e in entries)
        _Datum(
          label: _labelFor(report, e.key),
          value: e.value,
          fraction: max == 0 ? 0 : e.value / max,
          color: _colorFor(report, e.key),
          leading: _leadingFor(report, e.key),
        ),
    ];
  }

  Color _colorFor(String report, String key) => switch (report) {
        'issues-by-state' => AppColors.stateColor(key.toUpperCase()),
        'issues-by-priority' => AppColors.priorityColor(key.toUpperCase()),
        'issues-by-assignee' => hiveHueColor(_userNames[key] ?? key),
        _ => AppColors.accent,
      };

  Widget? _leadingFor(String report, String key) => switch (report) {
        'issues-by-state' => Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
                color: AppColors.stateColor(key.toUpperCase()),
                shape: BoxShape.circle),
          ),
        'issues-by-priority' =>
          PriorityFlag(priority: key.toUpperCase()),
        'issues-by-assignee' =>
          HiveAvatar(name: _userNames[key] ?? key, size: 22),
        _ => null,
      };
}

// ─────────────────────────── data model ────────────────────────────────────

class _Datum {
  const _Datum({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
    this.leading,
  });

  final String label;
  final int value;
  final double fraction;
  final Color color;
  final Widget? leading;
}

// ─────────────────────────── cards ─────────────────────────────────────────

class _BurndownCard extends StatelessWidget {
  const _BurndownCard({required this.points, required this.remaining});

  final List<({int day, double remaining, double ideal})> points;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    final maxY = points
        .map((p) => p.remaining > p.ideal ? p.remaining : p.ideal)
        .fold<double>(1, (m, v) => v > m ? v : m);
    final lastX = (points.length - 1).toDouble();
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _SectionTitle(context.t('reports.burndown'))),
              Text(
                context.t('reports.remaining', variables: {'count': '$remaining'}),
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: lastX,
                minY: 0,
                maxY: maxY * 1.1,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (maxY / 4).clamp(1, double.infinity),
                  getDrawingHorizontalLine: (_) => FlLine(
                      color: AppColors.hairline2, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: lastX <= 0 ? 1 : lastX,
                      getTitlesWidget: (value, meta) {
                        final isStart = value <= 0;
                        if (!isStart && value < lastX) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            isStart
                                ? context.t('reports.windowStart')
                                : context.t('reports.windowEnd'),
                            style: TextStyle(
                                fontFamily: AppTheme.fontMono,
                                fontSize: 10,
                                color: AppColors.inkFaint),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  // ideal (dashed grey)
                  LineChartBarData(
                    spots: [
                      for (final p in points)
                        FlSpot(p.day.toDouble(), p.ideal),
                    ],
                    isCurved: false,
                    color: AppColors.inkFaint,
                    barWidth: 1.5,
                    dashArray: [5, 5],
                    dotData: const FlDotData(show: false),
                  ),
                  // actual remaining (amber)
                  LineChartBarData(
                    spots: [
                      for (final p in points)
                        FlSpot(p.day.toDouble(), p.remaining),
                    ],
                    isCurved: false,
                    color: AppColors.accentStrong,
                    barWidth: 2.6,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (s, _, b, i) => FlDotCirclePainter(
                        radius: 2.6,
                        color: AppColors.accentStrong,
                        strokeWidth: 0,
                      ),
                    ),
                  ),
                ],
                lineTouchData: const LineTouchData(enabled: false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarReportCard extends StatelessWidget {
  const _BarReportCard({
    required this.title,
    required this.data,
    this.durationValues = false,
  });

  final String title;
  final List<_Datum> data;
  final bool durationValues;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title),
          const SizedBox(height: 14),
          if (data.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(context.t('reports.empty'),
                  style: TextStyle(color: AppColors.inkFaint)),
            )
          else
            for (final d in data)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    if (d.leading != null) ...[
                      SizedBox(
                          width: 22,
                          child: Center(child: d.leading)),
                      const SizedBox(width: 8),
                    ],
                    SizedBox(
                      width: 96,
                      child: Text(d.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                        child: HiveProgress(value: d.fraction, color: d.color)),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: durationValues ? 64 : 40,
                      child: Text(
                        durationValues ? fmtDuration(d.value) : '${d.value}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontFamily: AppTheme.fontMono,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.total, required this.projectName});
  final int total;
  final String projectName;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(context.t('reports.totalIssues')),
          const SizedBox(height: 18),
          Center(
            child: Column(
              children: [
                Text('$total',
                    style: TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 44,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1,
                        height: 1,
                        color: AppColors.ink)),
                const SizedBox(height: 6),
                Text(
                  projectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
            color: AppColors.ink));
  }
}

// ─────────────────────────── controls ──────────────────────────────────────

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.onSelected});
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      tooltip: context.t('reports.export'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      offset: const Offset(0, 46),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'pdf',
          child: Row(children: [
            const Icon(Icons.picture_as_pdf_outlined, size: 18),
            const SizedBox(width: 10),
            Text(context.t('reports.exportPdf')),
          ]),
        ),
        PopupMenuItem(
          value: 'csv',
          child: Row(children: [
            const Icon(Icons.table_chart_outlined, size: 18),
            const SizedBox(width: 10),
            Text(context.t('reports.exportCsv')),
          ]),
        ),
        PopupMenuItem(
          value: 'json',
          child: Row(children: [
            const Icon(Icons.data_object_rounded, size: 18),
            const SizedBox(width: 10),
            Text(context.t('reports.exportJson')),
          ]),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_rounded, size: 16, color: AppColors.ink),
            const SizedBox(width: 8),
            Text(context.t('reports.export'),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink)),
          ],
        ),
      ),
    );
  }
}

class _ProjectPicker extends StatelessWidget {
  const _ProjectPicker({
    required this.projects,
    required this.selected,
    required this.onChanged,
  });

  final List<Project> projects;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = selected != null
        ? projects.where((p) => p.id == selected).firstOrNull?.name ??
            projects.first.name
        : projects.first.name;
    return PopupMenuButton<String>(
      initialValue: selected,
      onSelected: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      offset: const Offset(0, 46),
      itemBuilder: (_) => [
        for (final p in projects)
          PopupMenuItem(value: p.id, child: Text(p.name)),
      ],
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded,
                size: 16, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}
