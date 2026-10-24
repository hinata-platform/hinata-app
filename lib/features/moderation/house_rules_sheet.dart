import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/lexical/hinata_markdown_preview.dart';
import '../../core/models/moderation_models.dart';
import '../../core/repositories/account_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart' show GhostButton;
import '../sprint/modals/glass_modal.dart';
import 'house_rules_cubit.dart';

/// The version of [rules] and since when it holds, for a header.
String houseRulesVersionLine(BuildContext context, HouseRules rules) {
  final since = rules.createdAt;
  return since == null
      ? context.t(
          'moderation.rules.version',
          variables: {'version': '${rules.version}'},
        )
      : context.t(
          'moderation.rules.versionSince',
          variables: {
            'version': '${rules.version}',
            'date': recentDay(context, since),
          },
        );
}

/// The house rules in full, "How we moderate" included, as the server wrote
/// them for the reader's language (HIN-175).
///
/// From [cubit] where the caller holds them already, the sign-in gate and the
/// Help section; read anew otherwise, as for a refused text pointing at the
/// rules it broke (HIN-176) or a notice. The sheet says when that read fails
/// and offers it again.
Future<void> showHouseRulesSheet(
  BuildContext context, {
  HouseRulesCubit? cubit,
}) {
  final account = cubit == null ? context.read<AccountRepository>() : null;
  return showGlassModal<void>(
    context,
    width: 620,
    builder: (_) => cubit == null
        ? BlocProvider(
            create: (_) => HouseRulesCubit(account!)..load(),
            child: const _HouseRulesSheet(),
          )
        : BlocProvider.value(value: cubit, child: const _HouseRulesSheet()),
  );
}

class _HouseRulesSheet extends StatelessWidget {
  const _HouseRulesSheet();

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<HouseRulesCubit, HouseRulesState>(
        builder: (context, state) {
          final rules = state.rules;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassModalHeader(
                icon: LucideIcons.bookOpenCheck,
                title: context.t('moderation.rules.title'),
                subtitle: rules == null
                    ? ''
                    : houseRulesVersionLine(context, rules),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
                  child: switch (state.status) {
                    _ when rules != null => HinataMarkdownPreview(
                      markdown: rules.markdown,
                      fontSize: AppType.label,
                    ),
                    HouseRulesStatus.failure => _Failed(
                      errorKey: state.errorKey ?? 'errors.unexpected',
                      onRetry: () =>
                          unawaited(context.read<HouseRulesCubit>().load()),
                    ),
                    _ => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: HiveLoader()),
                    ),
                  },
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(20, 4, 20, 18) +
                    EdgeInsets.only(
                      bottom: MediaQuery.viewPaddingOf(context).bottom,
                    ),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: GhostButton(
                    icon: LucideIcons.x,
                    label: context.t('common.close'),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ],
          );
        },
      );
}

/// Why the rules could not be read, and reading them again.
class _Failed extends StatelessWidget {
  const _Failed({required this.errorKey, required this.onRetry});

  final String errorKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            context.t(errorKey),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppType.label, color: AppColors.inkSoft),
          ),
        ),
        const SizedBox(height: 10),
        GhostButton(
          icon: LucideIcons.refreshCw,
          label: context.t('common.retry'),
          onPressed: onRetry,
        ),
      ],
    ),
  );
}
