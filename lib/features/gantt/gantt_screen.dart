import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart';
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
          padding: EdgeInsets.fromLTRB(
              context.pageGutter, 22, context.pageGutter, 14),
          child: PageHead(
            title: context.t('gantt.title'),
            subtitle: context.t('gantt.subtitle'),
            actions: [
              if (_projects.isNotEmpty)
                _ProjectPicker(
                  projects: _projects,
                  selected: _projectId,
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
      padding: context.pagePadding,
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

/// Compact white dropdown for choosing the active project.
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
      offset: const Offset(0, 44),
      itemBuilder: (_) => [
        for (final p in projects)
          PopupMenuItem(value: p.id, child: Text(p.name)),
      ],
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
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
            const Icon(Icons.expand_more_rounded,
                size: 16, color: AppColors.inkSoft),
          ],
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
    final color = task.resolved
        ? AppColors.stDone
        : AppColors.stateColor(task.state.toUpperCase());
    return Padding(
      padding: EdgeInsets.only(left: startOffset * dayWidth),
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message:
              '${task.readableId} · ${task.state} · ${task.progressPercent}%',
          child: Container(
            width: duration * dayWidth,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(7),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (task.progressPercent / 100).clamp(0.0, 1.0),
                    child: Container(
                        color: Colors.white.withValues(alpha: 0.22)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      task.readableId,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
