import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_share_models.dart';
import '../../../core/repositories/time_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/hive_widgets.dart' show forwardChevron;

/// How many invitations wait for the reader's answer (HIN-95).
///
/// One page of one row is the question, so the count is the server's total and
/// nothing else travels. A failure keeps the last count: the notice is a way
/// in, and the page behind it says what went wrong.
class SharedInboxCubit extends Cubit<int> {
  SharedInboxCubit(this._time) : super(0);

  final TimeRepository _time;

  Future<void> refresh() async {
    try {
      final page = await _time.shares(TimeShareBox.inbox, size: 1);
      if (!isClosed) emit(page.total);
    } catch (_) {
      // Keep what is shown: the notice is a way in, not the inbox itself.
    }
  }
}

/// The line above the reader's entries while colleagues' invitations wait,
/// and nothing at all otherwise: an inbox that is empty is not news.
class SharedInboxNotice extends StatelessWidget {
  const SharedInboxNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final waiting = context.watch<SharedInboxCubit>().state;
    if (waiting == 0) return const SizedBox.shrink();
    final message = context.t('time.share.waiting', count: waiting);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: message,
        excludeSemantics: true,
        child: Material(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            onTap: () async {
              final inbox = context.read<SharedInboxCubit>();
              await context.push('/time/shared');
              unawaited(inbox.refresh());
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.inbox,
                      size: 18,
                      color: AppColors.accentInk,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          fontSize: AppType.label,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.t('time.share.open'),
                      style: TextStyle(
                        fontSize: AppType.label,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentInk,
                      ),
                    ),
                    Icon(
                      forwardChevron(context),
                      size: 16,
                      color: AppColors.accentInk,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
