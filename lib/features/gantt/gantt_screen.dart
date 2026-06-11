import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/soft_card.dart';

/// Interactive project timeline. Bars are positioned on a day grid;
/// tapping a bar opens the issue (rescheduling happens in the issue form).
class GanttScreen extends StatefulWidget {
  const GanttScreen({super.key});

  @override
  State<GanttScreen> createState() => _GanttScreenState();
}

class _GanttScreenState extends State<GanttScreen> {
  List<Project> _projects = const [];
  String? _projectId;
  List<GanttTask> _tasks = const [];
  bool _loading = true;
  String? _error;

  static const _dayWidth = 28.0;
  static const _rowHeight = 44.0;
  static const _labelWidth = 180.0;

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
      _tasks = await repository.gantt(_projectId!);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              EdgeInsets.fromLTRB(context.pageGutter, 16, context.pageGutter, 8),
          child: Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                context.t('gantt.title'),
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (_projects.isNotEmpty)
                DropdownButton<String>(
                  value: _projectId,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(16),
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
            ],
          ),
        ),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.navy));
    }
    if (_error != null) {
      return Center(
          child: Text(context.t(_error!),
              style: const TextStyle(color: AppColors.textSecondary)));
    }
    if (_tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            context.t('gantt.empty'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final start = _tasks
        .map((task) => task.startDate!)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final end = _tasks
        .map((task) => task.dueDate ?? task.startDate!)
        .reduce((a, b) => a.isAfter(b) ? a : b)
        .add(const Duration(days: 3));
    final totalDays = end.difference(start).inDays + 1;

    return Padding(
      padding: EdgeInsets.all(context.pageGutter),
      child: SoftCard(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: _labelWidth + totalDays * _dayWidth,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TimeAxis(start: start, days: totalDays, dayWidth: _dayWidth,
                      labelWidth: _labelWidth),
                  const Divider(),
                  for (final task in _tasks)
                    SizedBox(
                      height: _rowHeight,
                      child: Row(
                        children: [
                          SizedBox(
                            width: _labelWidth,
                            child: Text(
                              '${task.readableId}  ${task.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                          _GanttBar(
                            task: task,
                            chartStart: start,
                            dayWidth: _dayWidth,
                            onTap: () => context.go('/issues/${task.id}'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeAxis extends StatelessWidget {
  const _TimeAxis({
    required this.start,
    required this.days,
    required this.dayWidth,
    required this.labelWidth,
  });

  final DateTime start;
  final int days;
  final double dayWidth;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: labelWidth),
        for (var i = 0; i < days; i++)
          SizedBox(
            width: dayWidth,
            child: Column(
              children: [
                Text(
                  '${start.add(Duration(days: i)).day}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: start.add(Duration(days: i)).day == 1
                        ? FontWeight.w800
                        : FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GanttBar extends StatelessWidget {
  const _GanttBar({
    required this.task,
    required this.chartStart,
    required this.dayWidth,
    required this.onTap,
  });

  final GanttTask task;
  final DateTime chartStart;
  final double dayWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final startOffset = task.startDate!.difference(chartStart).inDays;
    final duration = (task.dueDate ?? task.startDate!)
            .difference(task.startDate!)
            .inDays +
        1;
    final color = task.resolved ? AppColors.accentTeal : AppColors.accentPurple;
    return Padding(
      padding: EdgeInsets.only(left: startOffset * dayWidth),
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: '${task.readableId} · ${task.state} · ${task.progressPercent}%',
          child: Container(
            width: duration * dayWidth,
            height: 22,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (task.progressPercent / 100).clamp(0.02, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
