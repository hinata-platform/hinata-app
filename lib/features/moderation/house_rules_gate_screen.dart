import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/repositories/account_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_type.dart';
import '../../core/widgets/hex_mark.dart';
import '../../core/widgets/hive_loader.dart';
import '../auth/auth_shell.dart';
import '../legal/legal_links.dart';
import '../sprint/modals/glass_modal.dart' show showGlassErrorToast;
import 'house_rules_cubit.dart';
import 'house_rules_sheet.dart';

/// The instance's house rules, after signing in and before anything else,
/// whenever a version waits for this person (HIN-175). Agreeing is the only
/// way on; the other way is signing out.
class HouseRulesGateScreen extends StatelessWidget {
  const HouseRulesGateScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        HouseRulesCubit(context.read<AccountRepository>())..load(),
    child: const _HouseRulesGateView(),
  );
}

class _HouseRulesGateView extends StatelessWidget {
  const _HouseRulesGateView();

  Future<void> _accept(BuildContext context) async {
    final auth = context.read<AuthBloc>();
    if (await context.read<HouseRulesCubit>().accept()) {
      // The session learns from the server that nothing waits any more, and
      // the router moves on from there.
      auth.add(const AuthChecked());
    }
  }

  @override
  Widget build(BuildContext context) => AuthShell(
    maxContentWidth: 460,
    child: BlocConsumer<HouseRulesCubit, HouseRulesState>(
      listenWhen: (before, now) =>
          now.errorKey != null &&
          now.errorKey != before.errorKey &&
          now.status != HouseRulesStatus.failure,
      listener: (context, state) =>
          showGlassErrorToast(context, context.t(state.errorKey!)),
      builder: (context, state) => AuthGlassCard(
        child: switch (state.status) {
          HouseRulesStatus.loading => const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: HiveLoader(size: 34)),
          ),
          HouseRulesStatus.failure => _Failure(errorKey: state.errorKey),
          HouseRulesStatus.ready || HouseRulesStatus.accepting => _Rules(
            state: state,
            onAccept: () => unawaited(_accept(context)),
          ),
        },
      ),
    ),
  );
}

class _Rules extends StatelessWidget {
  const _Rules({required this.state, required this.onAccept});

  final HouseRulesState state;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final rules = state.rules!;
    final busy = state.status == HouseRulesStatus.accepting;
    final organization = context.select<AppConfigBloc, String?>(
      (bloc) => bloc.state.meta?.organizationName,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: HexMark(size: 46)),
        const SizedBox(height: 14),
        Semantics(
          header: true,
          child: Text(
            organization == null || organization.isEmpty
                ? context.t('moderation.rules.title')
                : context.t(
                    'moderation.rules.gateTitle',
                    variables: {'name': organization},
                  ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: AppType.display,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.t(
            rules.acceptedVersion == null
                ? 'moderation.rules.gateLead'
                : 'moderation.rules.gateChanged',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppType.body,
            height: 1.4,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 14),
        _RuleLine(
          icon: LucideIcons.handshake,
          title: context.t('moderation.rules.respect'),
          text: context.t('moderation.rules.respectText'),
        ),
        _RuleLine(
          icon: LucideIcons.scale,
          title: context.t('moderation.rules.lawful'),
          text: context.t('moderation.rules.lawfulText'),
        ),
        _RuleLine(
          icon: LucideIcons.flag,
          title: context.t('moderation.rules.report'),
          text: context.t('moderation.rules.reportText'),
        ),
        _RuleLine(
          icon: LucideIcons.gavel,
          title: context.t('moderation.rules.consequences'),
          text: context.t('moderation.rules.consequencesText'),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            TextButton(
              onPressed: () => unawaited(
                showHouseRulesSheet(
                  context,
                  cubit: context.read<HouseRulesCubit>(),
                ),
              ),
              child: Text(context.t('moderation.rules.readAll')),
            ),
            TextButton(
              onPressed: () => unawaited(openTermsOfService(context)),
              child: Text(context.t('moderation.rules.appTerms')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: busy ? null : onAccept,
          child: busy
              ? const SizedBox.square(
                  dimension: 22,
                  child: HiveLoader(size: 22, strokeWidth: 2),
                )
              : Text(context.t('moderation.rules.accept')),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: busy
              ? null
              : () => context.read<AuthBloc>().add(const LogoutRequested()),
          child: Text(context.t('account.signOut')),
        ),
      ],
    );
  }
}

/// One of the four lines that sum the rules up; the whole text is a tap away.
class _RuleLine extends StatelessWidget {
  const _RuleLine({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: AppColors.accentInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: AppType.label,
                    height: 1.4,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// The rules could not be read. Trying again and signing out stay open: the
/// gate must never be a dead end.
class _Failure extends StatelessWidget {
  const _Failure({required this.errorKey});

  final String? errorKey;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Icon(LucideIcons.cloudOff, size: 30, color: AppColors.inkSoft),
      const SizedBox(height: 12),
      Text(
        context.t('moderation.rules.loadFailed'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: AppType.body,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      if (errorKey != null) ...[
        const SizedBox(height: 6),
        Text(
          context.t(errorKey!),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppType.label,
            height: 1.4,
            color: AppColors.inkSoft,
          ),
        ),
      ],
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => unawaited(context.read<HouseRulesCubit>().load()),
        icon: const Icon(LucideIcons.refreshCw, size: 16),
        label: Text(context.t('common.retry')),
      ),
      const SizedBox(height: 6),
      TextButton(
        onPressed: () => context.read<AuthBloc>().add(const LogoutRequested()),
        child: Text(context.t('account.signOut')),
      ),
    ],
  );
}
