import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/blocs/app_config_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/repositories/shift_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../git/widgets/copy_field.dart';
import '../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassConfirm, showGlassToast;
import 'account_widgets.dart';
import 'shift_feed_cubit.dart';

/// [ShiftFeedSection] with the gap above it, both only while shift planning
/// is on, so the notifications page never ends on an empty space.
class ShiftFeedSlot extends StatelessWidget {
  const ShiftFeedSlot({super.key});

  @override
  Widget build(BuildContext context) {
    final on = context.select<AppConfigBloc, bool>(
      (bloc) => bloc.state.meta?.shiftPlanning ?? false,
    );
    if (!on) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(top: 16),
      child: ShiftFeedSection(),
    );
  }
}

/// Settings → Notifications → "Schichten im eigenen Kalender" (HIN-47).
///
/// A private address a calendar app subscribes to, carrying the person's own
/// shifts. It is shown once, when it is made, and never stored by the app;
/// after that the section says only since when it runs and when a calendar
/// last fetched it.
class ShiftFeedSection extends StatelessWidget {
  const ShiftFeedSection({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ShiftFeedCubit(context.read<ShiftRepository>())..load(),
    child: const ShiftFeedView(),
  );
}

/// The section's body, for a cubit provided from outside (and in tests).
class ShiftFeedView extends StatelessWidget {
  const ShiftFeedView({super.key});

  Future<void> _create(BuildContext context, {required bool again}) async {
    final cubit = context.read<ShiftFeedCubit>();
    if (again) {
      final sure = await showGlassConfirm(
        context,
        icon: LucideIcons.refreshCw,
        title: context.t('account.shiftFeed.renewTitle'),
        message: context.t('account.shiftFeed.renewMessage'),
        confirmLabel: context.t('account.shiftFeed.renew'),
        confirmIcon: LucideIcons.refreshCw,
        destructive: true,
      );
      if (sure != true || !context.mounted) return;
    }
    final error = await cubit.create();
    if (error != null && context.mounted) {
      showGlassToast(context, context.t(error), kind: GlassToastKind.error);
    }
  }

  Future<void> _remove(BuildContext context) async {
    final cubit = context.read<ShiftFeedCubit>();
    final sure = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('account.shiftFeed.removeTitle'),
      message: context.t('account.shiftFeed.removeMessage'),
      confirmLabel: context.t('account.shiftFeed.remove'),
      confirmIcon: LucideIcons.trash2,
      destructive: true,
    );
    if (sure != true || !context.mounted) return;
    final error = await cubit.remove();
    if (!context.mounted) return;
    showGlassToast(
      context,
      context.t(error ?? 'account.shiftFeed.removed'),
      kind: error == null ? GlassToastKind.success : GlassToastKind.error,
    );
  }

  Future<void> _open(BuildContext context, String webcal) async {
    final ok = await launchUrl(
      Uri.parse(webcal),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!ok && context.mounted) {
      showGlassToast(
        context,
        context.t('account.shiftFeed.openFailed'),
        kind: GlassToastKind.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ShiftFeedCubit>().state;
    final address = state.address;
    return AccountSection(
      icon: LucideIcons.calendarSync,
      title: context.t('account.shiftFeed.title'),
      subtitle: context.t('account.shiftFeed.subtitle'),
      children: [
        if (state.loading && state.status == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: HiveLoader(size: 28)),
          )
        else if (state.status == null && state.errorKey != null)
          HiveEmptyState(
            title: context.t(state.errorKey!),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
            action: OutlinedButton(
              onPressed: () => unawaited(context.read<ShiftFeedCubit>().load()),
              child: Text(context.t('common.retry')),
            ),
          )
        else if (address != null) ...[
          AccountNote(
            icon: LucideIcons.eyeOff,
            text: context.t('account.shiftFeed.onlyNow'),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: context.t('account.shiftFeed.address'),
            child: CopyField(
              text: address.url,
              onCopied: () => showGlassToast(
                context,
                context.t('account.shiftFeed.copied'),
                kind: GlassToastKind.success,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => unawaited(_open(context, address.webcalUrl)),
                icon: const Icon(LucideIcons.calendarPlus, size: 16),
                label: Text(context.t('account.shiftFeed.openInCalendar')),
              ),
              TextButton(
                onPressed: context.read<ShiftFeedCubit>().hideAddress,
                child: Text(context.t('account.shiftFeed.done')),
              ),
            ],
          ),
        ] else if (state.exists) ...[
          Text(
            _since(context, state.status!.createdAt, state.status!.lastUsedAt),
            style: TextStyle(fontSize: AppType.body, color: AppColors.ink),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: state.busy
                    ? null
                    : () => unawaited(_create(context, again: true)),
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: Text(context.t('account.shiftFeed.renew')),
              ),
              OutlinedButton.icon(
                onPressed: state.busy
                    ? null
                    : () => unawaited(_remove(context)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
                icon: const Icon(LucideIcons.trash2, size: 16),
                label: Text(context.t('account.shiftFeed.remove')),
              ),
            ],
          ),
        ] else
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: state.busy
                  ? null
                  : () => unawaited(_create(context, again: false)),
              icon: const Icon(LucideIcons.link, size: 16),
              label: Text(context.t('account.shiftFeed.create')),
            ),
          ),
      ],
    );
  }

  /// "Abo aktiv seit 20. Okt., zuletzt abgerufen vor 12 Minuten".
  static String _since(
    BuildContext context,
    DateTime? createdAt,
    DateTime? lastUsedAt,
  ) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final since = createdAt == null
        ? context.t('account.shiftFeed.active')
        : context.t(
            'account.shiftFeed.activeSince',
            variables: {'date': DateFormat.yMMMd(locale).format(createdAt)},
          );
    final last = lastUsedAt == null
        ? context.t('account.shiftFeed.neverFetched')
        : context.t(
            'account.shiftFeed.lastFetched',
            variables: {'ago': _ago(context, lastUsedAt)},
          );
    return '$since, $last';
  }

  static String _ago(BuildContext context, DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return context.t('account.shiftFeed.ago.now');
    if (d.inHours < 1) {
      return context.t('account.shiftFeed.ago.minutes', count: d.inMinutes);
    }
    if (d.inDays < 1) {
      return context.t('account.shiftFeed.ago.hours', count: d.inHours);
    }
    return context.t('account.shiftFeed.ago.days', count: d.inDays);
  }
}
