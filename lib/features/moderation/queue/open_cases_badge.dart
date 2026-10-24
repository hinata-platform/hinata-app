import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/widgets/count_badge.dart';
import 'moderation_summary_cubit.dart';

/// The cases waiting for moderation, on the Moderation entry of the settings
/// (HIN-174).
///
/// It reads the count itself, so a new count rebuilds the badge and not the
/// page that lists the entry. Nothing at zero, before the first count, or
/// without a [ModerationSummaryCubit] above it, which only moderators have.
class OpenCasesBadge extends StatelessWidget {
  const OpenCasesBadge({super.key, required this.gap});

  /// The space after the badge, toward the entry's glyph.
  final double gap;

  @override
  Widget build(BuildContext context) {
    final open = context.select<ModerationSummaryCubit?, int>(
      (summary) => summary?.state?.open ?? 0,
    );
    if (open <= 0) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsetsDirectional.only(end: gap),
      child: CountBadge(
        open,
        semanticLabel: context.t('moderation.queue.openCount', count: open),
      ),
    );
  }
}
