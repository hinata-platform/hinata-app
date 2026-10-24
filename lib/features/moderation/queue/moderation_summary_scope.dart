import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/repositories/moderation_repository.dart';
import 'moderation_summary_cubit.dart';

/// Holds the moderation numbers for the page below it (HIN-174): read when it
/// opens and once a minute while it stays, paused while the app is in the
/// background, and ended with the page.
class ModerationSummaryScope extends StatefulWidget {
  const ModerationSummaryScope({super.key, required this.child});

  final Widget child;

  @override
  State<ModerationSummaryScope> createState() => _ModerationSummaryScopeState();
}

class _ModerationSummaryScopeState extends State<ModerationSummaryScope> {
  late final ModerationSummaryCubit _summary;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _summary = ModerationSummaryCubit(context.read<ModerationRepository>())
      ..start();
    _lifecycle = AppLifecycleListener(
      onHide: _summary.pause,
      onShow: _summary.start,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_summary.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocProvider.value(value: _summary, child: widget.child);
}
