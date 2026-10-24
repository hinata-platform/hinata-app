import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/widgets/quiet_content_line.dart';
import 'hidden_content_cubit.dart';

/// Shows [child], or the folded line when the reader blocks its author
/// (HIN-168) or reported it (HIN-173) and has not opened it in this session.
///
/// Asks [HiddenContentCubit] when one is above it and shows [child] when none
/// is, so a surface built without the app around it (a test, a preview)
/// renders as it always did.
class HiddenContentFold extends StatelessWidget {
  const HiddenContentFold({
    super.key,
    required this.authorId,
    required this.contentId,
    required this.authorName,
    required this.child,
  });

  final String authorId;
  final String contentId;
  final String authorName;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reason = context.select<HiddenContentCubit?, FoldReason?>(
      (hidden) =>
          hidden?.state.foldOf(authorId: authorId, contentId: contentId),
    );
    if (reason == null) return child;
    return QuietContentLine(
      icon: switch (reason) {
        FoldReason.blocked => LucideIcons.chevronsDownUp,
        FoldReason.reported => LucideIcons.flag,
      },
      text: switch (reason) {
        FoldReason.blocked => context.t(
          'blocks.folded',
          variables: {'name': authorName},
        ),
        FoldReason.reported => context.t('moderation.report.folded'),
      },
      actionLabel: context.t('blocks.show'),
      onAction: () => context.read<HiddenContentCubit>().reveal(contentId),
    );
  }
}
