import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/blocs/paged_cubit.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_privacy_models.dart';
import '../../../core/repositories/time_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassConfirm, showGlassToast;
import '../../time/lock_notice.dart' show formatPeriod;
import '../admin_form_helpers.dart';

/// Admin → Time tracking: the days opened for single people that are still open.
///
/// Under the requests they answer. Each opening closes by itself after two weeks;
/// this is where an administrator closes one sooner, which is recorded like the
/// opening was.
class AdminBackfillGrantsCard extends StatefulWidget {
  const AdminBackfillGrantsCard({super.key});

  @override
  State<AdminBackfillGrantsCard> createState() =>
      _AdminBackfillGrantsCardState();
}

class _AdminBackfillGrantsCardState extends State<AdminBackfillGrantsCard> {
  late final PagedCubit<TimeBackfillGrant> _grants =
      PagedCubit<TimeBackfillGrant>(
        (page, size) => context.read<TimeRepository>().backfillGrants(
          page: page,
          size: size,
        ),
        pageSize: 25,
        keyOf: (grant) => grant.id,
      );

  @override
  void initState() {
    super.initState();
    unawaited(_grants.load());
  }

  @override
  void dispose() {
    unawaited(_grants.close());
    super.dispose();
  }

  Future<void> _revoke(TimeBackfillGrant grant) async {
    final repository = context.read<TimeRepository>();
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.calendarX,
      title: context.t('admin.timeTracking.grantRevokeTitle'),
      message: context.t(
        'admin.timeTracking.grantRevokeMessage',
        variables: {
          'name': grant.userLabel ?? context.t('time.deletedUser'),
          'period': formatPeriod(context, grant.from, grant.to),
        },
      ),
      // The short word: the question above already says what closes, and two
      // buttons side by side have to fit a narrow dialog in every language.
      confirmLabel: context.t('common.close'),
      confirmIcon: LucideIcons.calendarX,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      await repository.revokeBackfillGrant(grant.id);
      if (!mounted) return;
      _grants.removeItem(grant.id);
      showGlassToast(
        context,
        context.t('admin.timeTracking.grantRevoked'),
        kind: GlassToastKind.success,
      );
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      showGlassToast(
        context,
        context.t(failure.message),
        kind: GlassToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) => AdminSectionCard(
    icon: LucideIcons.calendarCheck,
    title: context.t('admin.timeTracking.grantsTitle'),
    subtitle: context.t('admin.timeTracking.grantsHint'),
    children: [
      BlocBuilder<PagedCubit<TimeBackfillGrant>, PagedState<TimeBackfillGrant>>(
        bloc: _grants,
        builder: (context, state) {
          final quiet = TextStyle(
            fontSize: 12.5,
            height: 1.5,
            color: AppColors.textSecondary,
          );
          if (state.isLoading && state.items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: HiveLoader(size: 26),
            );
          }
          if (state.errorKey != null && state.items.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.t(state.errorKey!), style: quiet),
                const SizedBox(height: 8),
                GhostButton(
                  icon: LucideIcons.refreshCw,
                  label: context.t('common.retry'),
                  onPressed: () => unawaited(_grants.load()),
                ),
              ],
            );
          }
          if (state.items.isEmpty) {
            return Text(
              context.t('admin.timeTracking.grantsEmpty'),
              style: quiet,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final grant in state.items)
                _GrantRow(grant: grant, onRevoke: () => _revoke(grant)),
              if (state.hasMore)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: state.isLoadingMore
                      ? const HiveLoader(size: 24)
                      : GhostButton(
                          icon: LucideIcons.chevronsDown,
                          label: context.t('time.correction.more'),
                          onPressed: () => unawaited(_grants.loadMore()),
                        ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

/// One opening: for whom, which days, until when, and why.
class _GrantRow extends StatelessWidget {
  const _GrantRow({required this.grant, required this.onRevoke});

  final TimeBackfillGrant grant;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final expiresAt = grant.expiresAt;
    final details = [
      formatPeriod(context, grant.from, grant.to),
      if (expiresAt != null)
        context.t(
          'admin.timeTracking.grantOpenUntil',
          variables: {
            'date': DateFormat.yMMMd(locale).format(expiresAt.toLocal()),
          },
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              LucideIcons.calendarCheck,
              size: 16,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  grant.userLabel ?? context.t('time.deletedUser'),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  details.join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (grant.note case final note?) ...[
                  const SizedBox(height: 4),
                  Text(
                    note,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          GhostButton(
            icon: LucideIcons.calendarX,
            label: context.t('admin.timeTracking.grantRevoke'),
            onPressed: onRevoke,
            collapseToIcon: true,
          ),
        ],
      ),
    );
  }
}
