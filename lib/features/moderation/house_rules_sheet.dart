import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/lexical/hinata_markdown_preview.dart';
import '../../core/models/moderation_models.dart';
import '../../core/repositories/account_repository.dart';
import '../../core/theme/app_type.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/hive_widgets.dart' show GhostButton;
import '../sprint/modals/glass_modal.dart';

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

/// Reads the house rules and shows them, for a place that has none loaded: a
/// refused text pointing at the rules it broke (HIN-176).
Future<void> openHouseRules(BuildContext context) async {
  final account = context.read<AccountRepository>();
  try {
    final rules = await account.houseRules();
    if (context.mounted) await showHouseRulesSheet(context, rules);
  } on ApiFailure catch (failure) {
    if (context.mounted) {
      showGlassErrorToast(context, context.t(failure.message));
    }
  } catch (_) {
    if (context.mounted) {
      showGlassErrorToast(context, context.t('errors.unexpected'));
    }
  }
}

/// The house rules in full, "How we moderate" included, as the server wrote
/// them for the reader's language (HIN-175).
Future<void> showHouseRulesSheet(BuildContext context, HouseRules rules) =>
    showGlassModal<void>(
      context,
      width: 620,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassModalHeader(
            icon: LucideIcons.bookOpenCheck,
            title: context.t('moderation.rules.title'),
            subtitle: houseRulesVersionLine(context, rules),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
              child: HinataMarkdownPreview(
                markdown: rules.markdown,
                fontSize: AppType.label,
              ),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.fromLTRB(20, 4, 20, 18) +
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
