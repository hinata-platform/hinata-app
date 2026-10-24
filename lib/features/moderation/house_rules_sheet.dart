import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/lexical/hinata_markdown_preview.dart';
import '../../core/models/moderation_models.dart';
import '../../core/theme/app_type.dart';
import '../../core/widgets/hive_widgets.dart' show GhostButton;
import '../sprint/modals/glass_modal.dart';

/// The day of [at] as the rest of the app tells a recent date: without the
/// year within this one, with it once it is older.
String moderationDay(BuildContext context, DateTime at) {
  final locale = Localizations.localeOf(context).toString();
  final local = at.toLocal();
  final format = local.year == DateTime.now().year
      ? DateFormat.MMMd(locale)
      : DateFormat.yMMMd(locale);
  return format.format(local);
}

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
            'date': moderationDay(context, since),
          },
        );
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
