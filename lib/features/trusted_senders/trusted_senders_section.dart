import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/account_models.dart';
import '../../core/repositories/account_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../account/account_widgets.dart' show AccountSection;
import '../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassErrorToast, showGlassToast;
import 'trusted_senders_cubit.dart';

/// Settings › Privacy › Trusted senders (HIN-181): the mail senders whose
/// external images load without asking, and taking that back.
class TrustedSendersSection extends StatelessWidget {
  const TrustedSendersSection({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        TrustedSendersCubit(context.read<AccountRepository>())..load(),
    child: const _TrustedSendersBody(),
  );
}

class _TrustedSendersBody extends StatelessWidget {
  const _TrustedSendersBody();

  Future<void> _distrust(BuildContext context, String domain) async {
    final done = context.t(
      'account.trustedSenders.removedToast',
      variables: {'domain': domain},
    );
    try {
      await context.read<TrustedSendersCubit>().distrust(domain);
      if (context.mounted) {
        showGlassToast(context, done, kind: GlassToastKind.success);
      }
    } on ApiFailure catch (failure) {
      if (context.mounted) {
        showGlassErrorToast(context, context.t(failure.message));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AccountSection(
    icon: LucideIcons.imageUp,
    title: context.t('account.trustedSenders.title'),
    subtitle: context.t('account.trustedSenders.subtitle'),
    children: [
      BlocBuilder<TrustedSendersCubit, PagedState<TrustedSender>>(
        builder: (context, state) {
          if (state.isLoading && state.items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: HiveLoader()),
            );
          }
          if (state.errorKey != null && state.items.isEmpty) {
            return HiveEmptyState(
              title: context.t(state.errorKey!),
              action: GhostButton(
                icon: LucideIcons.refreshCw,
                label: context.t('common.retry'),
                onPressed: () =>
                    unawaited(context.read<TrustedSendersCubit>().load()),
              ),
            );
          }
          if (state.items.isEmpty) {
            return HiveEmptyState(
              title: context.t('account.trustedSenders.emptyTitle'),
              message: context.t('account.trustedSenders.emptyMessage'),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < state.items.length; i++) ...[
                if (i > 0) Divider(height: 1, color: AppColors.hairline2),
                _SenderRow(
                  sender: state.items[i],
                  onRemove: () => _distrust(context, state.items[i].domain),
                ),
              ],
              if (state.hasMore)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: state.isLoadingMore
                      ? const HiveLoader(size: 24)
                      : GhostButton(
                          icon: LucideIcons.chevronsDown,
                          label: context.t('account.trustedSenders.more'),
                          onPressed: () => unawaited(
                            context.read<TrustedSendersCubit>().loadMore(),
                          ),
                        ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

/// One sender: the domain, since when, and taking the trust back.
class _SenderRow extends StatelessWidget {
  const _SenderRow({required this.sender, required this.onRemove});

  final TrustedSender sender;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final addedAt = sender.addedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(LucideIcons.mail, size: 18, color: AppColors.inkSoft),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sender.domain,
                  style: TextStyle(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                if (addedAt != null)
                  Text(
                    context.t(
                      'account.trustedSenders.since',
                      variables: {'date': recentDay(context, addedAt)},
                    ),
                    style: TextStyle(
                      fontSize: AppType.caption,
                      color: AppColors.inkSoft,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRemove,
            child: Text(
              context.t('account.trustedSenders.remove'),
              semanticsLabel: context.t(
                'account.trustedSenders.removeLabel',
                variables: {'domain': sender.domain},
              ),
            ),
          ),
        ],
      ),
    );
  }
}
