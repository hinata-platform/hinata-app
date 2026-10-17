import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/blocs/app_config_bloc.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_usage_models.dart';
import '../../../core/repositories/time_usage_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/budget/budget.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../sprint/modals/glass_modal.dart'
    show GlassModalHeader, showGlassModal;
import 'project_usage.dart';

/// A project's budget over time (HIN-156): the tube, the burn-down of the
/// last 90 days and when the budget runs out at the present pace. Opened from
/// a budget capsule or a dashboard cell.
Future<void> showBudgetHistorySheet(
  BuildContext context, {
  required String projectId,
  required String projectName,
}) => showGlassModal<void>(
  context,
  width: 620,
  builder: (_) =>
      _BudgetHistory(projectId: projectId, projectName: projectName),
);

class _BudgetHistory extends StatefulWidget {
  const _BudgetHistory({required this.projectId, required this.projectName});

  final String projectId;
  final String projectName;

  @override
  State<_BudgetHistory> createState() => _BudgetHistoryState();
}

class _BudgetHistoryState extends State<_BudgetHistory> {
  BudgetHistory? _history;
  BudgetForecast? _forecast;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final repository = context.read<TimeUsageRepository>();
    try {
      final results = await Future.wait([
        repository.history(widget.projectId),
        repository.forecast(widget.projectId),
      ]);
      if (!mounted) return;
      setState(() {
        _history = results[0] as BudgetHistory;
        _forecast = results[1] as BudgetForecast;
      });
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = _history;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassModalHeader(
          icon: LucideIcons.chartArea,
          title: context.t('budget.history.title'),
          subtitle: widget.projectName,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
            child: ProjectUsage(
              projectId: widget.projectId,
              builder: (context, usage) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BudgetMeter(
                    label: context.t('budget.timeBudget'),
                    gauge: usage?.budget,
                    footer: _forecast == null
                        ? null
                        : ForecastLine(forecast: _forecast!),
                  ),
                  const SizedBox(height: 22),
                  if (history != null)
                    BurnDownChart(
                      history: history,
                      limitMinutes: usage?.budgetMinutes,
                      estimatedMinutes: usage?.estimatedMinutes,
                    )
                  else if (_failed)
                    Text(
                      context.t('errors.unexpected'),
                      style: TextStyle(
                        fontSize: AppType.label,
                        color: AppColors.inkSoft,
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: HiveLoader(size: 28)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The forecast of one project, asked once, for a line under a budget.
/// Nothing with the extended module off or while it loads.
class ProjectForecast extends StatefulWidget {
  const ProjectForecast({
    super.key,
    required this.projectId,
    required this.builder,
  });

  final String projectId;
  final Widget Function(BuildContext context, BudgetForecast? forecast) builder;

  @override
  State<ProjectForecast> createState() => _ProjectForecastState();
}

class _ProjectForecastState extends State<ProjectForecast> {
  BudgetForecast? _forecast;
  String? _asked;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(ProjectForecast old) {
    super.didUpdateWidget(old);
    if (old.projectId != widget.projectId) _load();
  }

  void _load() {
    final id = widget.projectId;
    if (id == _asked) return;
    _asked = id;
    _forecast = null;
    try {
      final on =
          context.read<AppConfigBloc>().state.meta?.advancedTimeTracking ??
          false;
      if (!on) return;
      unawaited(
        context.read<TimeUsageRepository>().forecast(id).then((forecast) {
          if (mounted && _asked == id) {
            setState(() => _forecast = forecast);
          }
        }, onError: (Object _) {}),
      );
    } on ProviderNotFoundException {
      return;
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _forecast);
}
