import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';

/// Small rounded pill, e.g. "High Priority" or a workflow state.
class PillChip extends StatelessWidget {
  const PillChip({super.key, required this.label, this.background, this.foreground});

  final String label;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background ?? Colors.white,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground ?? AppColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

Color priorityColor(String priority) => switch (priority) {
      'SHOWSTOPPER' || 'CRITICAL' => AppColors.danger,
      'MAJOR' => AppColors.accentOrange,
      'MINOR' => AppColors.textSecondary,
      _ => AppColors.accentBlue,
    };

/// Centralized async UI: loading spinner, error with retry, empty hint.
class AsyncView extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.isLoading,
    required this.hasData,
    required this.builder,
    this.errorKey,
    this.onRetry,
    this.emptyKey = 'common.empty',
  });

  final bool isLoading;
  final bool hasData;
  final String? errorKey;
  final VoidCallback? onRetry;
  final String emptyKey;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    if (isLoading && !hasData) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: AppColors.navy),
        ),
      );
    }
    if (errorKey != null && !hasData) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 40, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                context.t(errorKey!),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                OutlinedButton(onPressed: onRetry, child: Text(context.t('common.retry'))),
              ],
            ],
          ),
        ),
      );
    }
    if (!hasData) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            context.t(emptyKey),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return builder(context);
  }
}
