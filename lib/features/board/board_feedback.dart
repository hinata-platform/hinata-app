import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';

/// What a board shows where it could not read what belongs there: why, and the
/// way to try again.
class BoardErrorRetry extends StatelessWidget {
  const BoardErrorRetry({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onRetry,
          child: Text(context.t('common.retry')),
        ),
      ],
    ),
  );
}

/// Dims what is on screen while a new read of it is under way, rather than
/// blanking it, so a search typed letter by letter keeps the board in view.
class BoardDimmed extends StatelessWidget {
  const BoardDimmed({super.key, required this.dimmed, required this.child});

  final bool dimmed;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: dimmed ? 0.6 : 1,
    duration: const Duration(milliseconds: 160),
    child: child,
  );
}
