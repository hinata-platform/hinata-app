import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/blocs/paged_cubit.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_case_models.dart';
import '../../../core/repositories/moderation_repository.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/util/dates.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/read_on_trigger.dart';
import '../../people/person_profile_screen.dart' show personLocation;
import '../../shell/page_chrome.dart';
import '../queue/moderation_screen.dart' show moderationLocation;
import 'suspensions_cubit.dart';

/// The accounts moderation suspended, newest first (HIN-174): who, until
/// when, and the case behind it.
class SuspensionsScreen extends StatelessWidget {
  const SuspensionsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        SuspensionsCubit(context.read<ModerationRepository>())..load(),
    child: PageChrome(
      title: context.t('moderation.suspension.pageTitle'),
      child: const SuspensionsView(),
    ),
  );
}

class SuspensionsView extends StatelessWidget {
  const SuspensionsView({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<SuspensionsCubit, PagedState<SuspendedAccount>>(
        builder: (context, state) {
          final cubit = context.read<SuspensionsCubit>();
          if (!state.hasData && state.isLoading) {
            return const Center(child: HiveLoader());
          }
          if (!state.hasData && state.errorKey != null) {
            return HiveEmptyState(
              title: context.t('moderation.suspension.failedTitle'),
              message: context.t('moderation.queue.failedMessage'),
              action: OutlinedButton(
                onPressed: () => unawaited(cubit.load()),
                child: Text(context.t('common.retry')),
              ),
            );
          }
          if (state.hasData && state.items.isEmpty) {
            return HiveEmptyState(
              title: context.t('moderation.suspension.emptyTitle'),
              message: context.t('moderation.suspension.emptyMessage'),
            );
          }
          return RefreshIndicator(
            onRefresh: cubit.load,
            child: ListView.builder(
              padding: context.pagePadding,
              itemCount: state.items.length + 1,
              itemBuilder: (context, index) {
                if (index == state.items.length) {
                  return state.hasMore
                      ? ReadOnTrigger(
                          count: state.items.length,
                          loading: state.isLoadingMore,
                          onReadOn: () => unawaited(cubit.loadMore()),
                        )
                      : const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SuspendedRow(account: state.items[index]),
                );
              },
            ),
          );
        },
      );
}

class _SuspendedRow extends StatelessWidget {
  const _SuspendedRow({required this.account});

  final SuspendedAccount account;

  @override
  Widget build(BuildContext context) {
    final person = account.person;
    final until = account.until;
    final caseId = account.caseId;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: person.id.isEmpty
              ? null
              : () => context.go(personLocation(person.id)),
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                AppAvatar(
                  name: person.displayName,
                  imageUrl: person.avatarUrl,
                  radius: 18,
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
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        until == null
                            ? context.t('moderation.suspension.indefinite')
                            : context.t(
                                'moderation.suspension.until',
                                variables: {
                                  'date': recentMoment(context, until),
                                },
                              ),
                        style: TextStyle(
                          fontSize: AppType.label,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                if (caseId != null)
                  TextButton.icon(
                    onPressed: () => context.go(
                      moderationLocation(view: CaseView.done, caseId: caseId),
                    ),
                    icon: const Icon(LucideIcons.gavel, size: 16),
                    label: Text(context.t('moderation.suspension.openCase')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
