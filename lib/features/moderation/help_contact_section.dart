import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/blocs/app_config_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart' show ModerationMeta;
import '../../core/repositories/account_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../../core/widgets/hive_widgets.dart' show GhostButton;
import '../../core/util/dates.dart';
import '../../core/util/published_link.dart';
import '../account/account_widgets.dart' show AccountSection;
import '../legal/legal_links.dart';
import '../sprint/modals/glass_modal.dart';
import 'house_rules_cubit.dart';
import 'house_rules_sheet.dart';
import 'report/report_sheet.dart' show showReportElsewhereSheet;

/// Settings › Help and contact (HIN-175): who moderates this instance and how
/// to reach them, its house rules, a report of something without a menu of
/// its own, the operator's imprint, and who provides the app. On a server
/// without moderation only the app's own part is left.
class HelpContactSection extends StatelessWidget {
  const HelpContactSection({super.key});

  @override
  Widget build(BuildContext context) {
    final meta = context
        .select<AppConfigBloc, ({String? name, ModerationMeta? moderation})>(
          (bloc) => (
            name: bloc.state.meta?.organizationName,
            moderation: (bloc.state.meta?.supportsModeration ?? false)
                ? bloc.state.meta?.moderation
                : null,
          ),
        );
    final moderation = meta.moderation;
    final section = AccountSection(
      icon: LucideIcons.lifeBuoy,
      title: context.t('account.help.title'),
      subtitle: context.t('account.help.subtitle'),
      children: [
        if (moderation != null) ...[
          if (moderation.contactEmail case final email?)
            _LinkRow(
              icon: LucideIcons.shieldCheck,
              label: _named(context, 'moderation.help.moderation', meta.name),
              detail: email,
              onTap: () => unawaited(
                launchUrl(
                  Uri(scheme: 'mailto', path: email),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ),
          const _RulesRow(),
          _LinkRow(
            icon: LucideIcons.flag,
            label: context.t('moderation.help.reportElsewhere'),
            detail: context.t('moderation.help.reportElsewhereDetail'),
            onTap: () => unawaited(showReportElsewhereSheet(context)),
          ),
          if (publishedLink(moderation.imprintUrl) case final imprint?)
            _LinkRow(
              icon: LucideIcons.landmark,
              label: _named(context, 'moderation.help.imprint', meta.name),
              external: true,
              onTap: () => unawaited(
                launchUrl(imprint, mode: LaunchMode.externalApplication),
              ),
            ),
        ],
        _LinkRow(
          icon: LucideIcons.smartphone,
          label: context.t('moderation.help.aboutApp'),
          detail: context.t('moderation.help.aboutAppDetail'),
          onTap: () => unawaited(_showAboutApp(context)),
        ),
      ],
    );
    if (moderation == null) return section;
    return BlocProvider(
      create: (context) =>
          HouseRulesCubit(context.read<AccountRepository>())..load(),
      child: section,
    );
  }

  /// [key] with the organisation's name, or its words without one.
  static String _named(BuildContext context, String key, String? name) =>
      name == null || name.isEmpty
      ? context.t('${key}Plain')
      : context.t(key, variables: {'name': name});
}

/// The house rules, with the version that holds and when this person agreed.
class _RulesRow extends StatelessWidget {
  const _RulesRow();

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<HouseRulesCubit, HouseRulesState>(
    builder: (context, state) {
      final rules = state.rules;
      final accepted = rules?.acceptedAt;
      return _LinkRow(
        icon: LucideIcons.bookOpenCheck,
        label: context.t('moderation.rules.title'),
        detail: switch (state.status) {
          HouseRulesStatus.failure => context.t('moderation.rules.loadFailed'),
          _ when rules == null => null,
          _ when accepted != null && rules.acceptedVersion == rules.version =>
            context.t(
              'moderation.help.rulesAccepted',
              variables: {
                'version': '${rules.version}',
                'date': recentDay(context, accepted),
              },
            ),
          _ => houseRulesVersionLine(context, rules),
        },
        onTap: () {
          if (rules != null) {
            unawaited(
              showHouseRulesSheet(
                context,
                cubit: context.read<HouseRulesCubit>(),
              ),
            );
          } else {
            unawaited(context.read<HouseRulesCubit>().load());
          }
        },
      );
    },
  );
}

/// One row: what it is, a line of detail, and where a tap goes.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.external = false,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback onTap;

  /// Leaves the app, as the glyph after it says.
  final bool external;

  @override
  Widget build(BuildContext context) => Semantics(
    button: !external,
    link: external,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.inkSoft),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    if (detail case final detail?)
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: AppType.caption,
                          color: AppColors.inkSoft,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                external ? LucideIcons.externalLink : LucideIcons.chevronRight,
                size: 16,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Who provides the app, its terms and its privacy policy; every server is
/// run by its own operator.
Future<void> _showAboutApp(BuildContext context) {
  final version = context.read<AppConfigBloc>().state.appVersion;
  return showGlassModal<void>(
    context,
    width: 480,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.smartphone,
          title: context.t('moderation.help.aboutApp'),
          subtitle: context.t(
            'moderation.help.aboutVersion',
            variables: {'version': version},
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LinkRow(
                icon: LucideIcons.userRound,
                label: context.t('moderation.help.provider'),
                detail: '$appProviderName · $appProviderEmail',
                onTap: () => unawaited(
                  launchUrl(
                    Uri(scheme: 'mailto', path: appProviderEmail),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
              _LinkRow(
                icon: LucideIcons.fileText,
                label: context.t('auth.termsOfService'),
                external: true,
                onTap: () => unawaited(openTermsOfService(context)),
              ),
              _LinkRow(
                icon: LucideIcons.shield,
                label: context.t('auth.privacyPolicy'),
                external: true,
                onTap: () => unawaited(openPrivacyPolicy(context)),
              ),
              _LinkRow(
                icon: LucideIcons.landmark,
                label: context.t('moderation.help.appImprint'),
                external: true,
                onTap: () => unawaited(openImprint(context)),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  context.t('moderation.help.operatorNote'),
                  style: TextStyle(
                    fontSize: AppType.label,
                    height: 1.45,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding:
              const EdgeInsets.fromLTRB(20, 8, 20, 18) +
              EdgeInsets.only(
                bottom: MediaQuery.viewPaddingOf(sheetContext).bottom,
              ),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: GhostButton(
              icon: LucideIcons.x,
              label: context.t('common.close'),
              onPressed: () => Navigator.of(sheetContext).maybePop(),
            ),
          ),
        ),
      ],
    ),
  );
}
