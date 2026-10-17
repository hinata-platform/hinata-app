import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/blocs/time_usage_cubit.dart';
import '../../../core/models/time_usage_models.dart';

/// Builds [builder] with one project's usage from the app-wide
/// [TimeUsageCubit], asking for it when it is missing or stale (HIN-152).
///
/// Rebuilds only when that one project's figures change: the selector reads
/// the project, not the whole map, so a board head does not repaint because
/// the dashboard learned about another project. With the extended module off,
/// or before the figures arrive, [builder] gets null and the surface shows
/// nothing extra.
class ProjectUsage extends StatefulWidget {
  const ProjectUsage({
    super.key,
    required this.projectId,
    required this.builder,
  });

  final String projectId;
  final Widget Function(BuildContext context, ProjectTimeUsage? usage) builder;

  @override
  State<ProjectUsage> createState() => _ProjectUsageState();
}

class _ProjectUsageState extends State<ProjectUsage> {
  TimeUsageCubit? _cubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final found = _lookUp();
    if (!identical(found, _cubit)) {
      _cubit = found;
      _ask();
    }
  }

  @override
  void didUpdateWidget(ProjectUsage old) {
    super.didUpdateWidget(old);
    if (old.projectId != widget.projectId) _ask();
  }

  TimeUsageCubit? _lookUp() => TimeUsageCubit.maybeOf(context);

  void _ask() {
    final cubit = _cubit;
    if (cubit != null) unawaited(cubit.watch([widget.projectId]));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = _cubit;
    if (cubit == null) return widget.builder(context, null);
    return BlocSelector<TimeUsageCubit, TimeUsageState, ProjectTimeUsage?>(
      bloc: cubit,
      selector: (state) => state.of(widget.projectId),
      builder: widget.builder,
    );
  }
}
