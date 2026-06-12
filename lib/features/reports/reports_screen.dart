import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';

/// Distribution reports per project (state / priority / assignee) plus
/// time-per-activity, rendered as donut + bars.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<Project> _projects = const [];
  String? _projectId;
  String _report = 'issues-by-state';
  Map<String, int> _data = const {};
  bool _loading = true;
  String? _error;

  static const _reports = [
    'issues-by-state',
    'issues-by-priority',
    'issues-by-assignee',
    'time-per-activity',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repository = context.read<HivoraRepository>();
    try {
      _projects = await repository.projects();
      if (_projects.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      _projectId ??= _projects.first.id;
      final query = <String, dynamic>{'projectId': _projectId};
      if (_report == 'time-per-activity') {
        final now = DateTime.now();
        query['from'] = now
            .subtract(const Duration(days: 30))
            .toIso8601String()
            .substring(0, 10);
        query['to'] = now.toIso8601String().substring(0, 10);
      }
      _data = await repository.report(_report, query);
      setState(() => _loading = false);
    } on ApiFailure catch (failure) {
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: context.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(
            title: context.t('reports.title'),
            subtitle: context.t('reports.subtitle'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_projects.isNotEmpty)
                _PickerBox(
                  child: DropdownButton<String>(
                    value: _projectId,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    borderRadius: BorderRadius.circular(12),
                    items: [
                      for (final project in _projects)
                        DropdownMenuItem(
                            value: project.id, child: Text(project.name)),
                    ],
                    onChanged: (value) {
                      _projectId = value;
                      _load();
                    },
                  ),
                ),
              _PickerBox(
                child: DropdownButton<String>(
                  value: _report,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  borderRadius: BorderRadius.circular(12),
                  items: [
                    for (final report in _reports)
                      DropdownMenuItem(
                        value: report,
                        child: Text(context.t('reports.$report')),
                      ),
                  ],
                  onChanged: (value) {
                    _report = value ?? _report;
                    _load();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(60),
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.navy)),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Text(context.t(_error!),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
            )
          else if (_data.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Text(context.t('reports.empty'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
            )
          else
            ResponsiveBuilder(
              builder: (context, size) {
                final donut = _DonutCard(data: _data);
                final legend = _LegendCard(data: _data);
                if (size == LayoutSize.compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [donut, const SizedBox(height: 16), legend],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: donut),
                    const SizedBox(width: 16),
                    Expanded(child: legend),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// White hairline-bordered wrapper that gives the dropdowns the v2 look.
class _PickerBox extends StatelessWidget {
  const _PickerBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: DropdownButtonHideUnderline(child: child),
    );
  }
}

const _chartColors = [
  AppColors.accentPurple,
  AppColors.accentOrange,
  AppColors.accentBlue,
  AppColors.accentTeal,
  AppColors.lavender,
  AppColors.warning,
  AppColors.success,
];

class _DonutCard extends StatelessWidget {
  const _DonutCard({required this.data});

  final Map<String, int> data;

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold<int>(0, (sum, value) => sum + value);
    return SoftCard(
      child: SizedBox(
        height: 260,
        child: PieChart(
          PieChartData(
            sectionsSpace: 3,
            centerSpaceRadius: 56,
            sections: [
              for (final (index, entry) in data.entries.indexed)
                PieChartSectionData(
                  value: entry.value.toDouble(),
                  title: total == 0
                      ? ''
                      : '${(entry.value * 100 / total).round()}%',
                  titleStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                  color: _chartColors[index % _chartColors.length],
                  radius: 48,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendCard extends StatelessWidget {
  const _LegendCard({required this.data});

  final Map<String, int> data;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, entry) in data.entries.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _chartColors[index % _chartColors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(entry.key, overflow: TextOverflow.ellipsis),
                  ),
                  Text('${entry.value}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
