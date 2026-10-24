import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/account_models.dart';
import '../../core/repositories/account_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../account/account_widgets.dart' show AccountSection;
import 'block_actions.dart';
import 'blocked_people_cubit.dart';

/// Settings › Privacy › Blocked people (HIN-168): who the reader blocks, and
/// lifting it again. Only shown where the server knows blocking.
class BlockedPeopleSection extends StatelessWidget {
  const BlockedPeopleSection({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        BlockedPeopleCubit(context.read<AccountRepository>())..load(),
    child: const _BlockedPeopleBody(),
  );
}

class _BlockedPeopleBody extends StatelessWidget {
  const _BlockedPeopleBody();

  Future<void> _lift(BuildContext context, BlockedPerson person) async {
    final list = context.read<BlockedPeopleCubit>();
    final lifted = await liftBlock(
      context,
      personId: person.id,
      name: person.displayName,
    );
    if (lifted) list.removeItem(person.id);
  }

  @override
  Widget build(BuildContext context) => AccountSection(
    icon: LucideIcons.userX,
    title: context.t('account.blocked.title'),
    subtitle: context.t('account.blocked.subtitle'),
    children: [
      BlocBuilder<BlockedPeopleCubit, PagedState<BlockedPerson>>(
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
                    unawaited(context.read<BlockedPeopleCubit>().load()),
              ),
            );
          }
          if (state.items.isEmpty) {
            return HiveEmptyState(
              title: context.t('blocks.list.emptyTitle'),
              message: context.t('blocks.list.emptyMessage'),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < state.items.length; i++) ...[
                if (i > 0) Divider(height: 1, color: AppColors.hairline2),
                _BlockedRow(
                  person: state.items[i],
                  onLift: () => _lift(context, state.items[i]),
                ),
              ],
              if (state.hasMore)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: state.isLoadingMore
                      ? const HiveLoader(size: 24)
                      : GhostButton(
                          icon: LucideIcons.chevronsDown,
                          label: context.t('blocks.list.more'),
                          onPressed: () => unawaited(
                            context.read<BlockedPeopleCubit>().loadMore(),
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

/// One person: who, since when, and lifting it.
class _BlockedRow extends StatelessWidget {
  const _BlockedRow({required this.person, required this.onLift});

  final BlockedPerson person;
  final VoidCallback onLift;

  /// The day alone within this year, as the rest of the app tells a recent
  /// date; with the year once it is older.
  String _since(BuildContext context, DateTime at) {
    final locale = Localizations.localeOf(context).toString();
    final local = at.toLocal();
    final format = local.year == DateTime.now().year
        ? DateFormat.MMMd(locale)
        : DateFormat.yMMMd(locale);
    return format.format(local);
  }

  @override
  Widget build(BuildContext context) {
    final blockedAt = person.blockedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          HiveAvatar(
            name: person.displayName,
            imageUrl: person.avatarUrl,
            size: 34,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.displayName,
                  style: TextStyle(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                if (blockedAt != null)
                  Text(
                    context.t(
                      'blocks.list.since',
                      variables: {'date': _since(context, blockedAt)},
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
            onPressed: onLift,
            child: Text(
              context.t('blocks.list.unblock'),
              // "Aufheben" alone does not say whose block a screen reader
              // lifts.
              semanticsLabel: context.t(
                'blocks.list.unblockLabel',
                variables: {'name': person.displayName},
              ),
            ),
          ),
        ],
      ),
    );
  }
}
