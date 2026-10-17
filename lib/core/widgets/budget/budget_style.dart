import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../i18n/i18n.dart';
import '../../models/time_usage_models.dart';
import '../../theme/app_colors.dart';
import '../hive_widgets.dart' show fmtDuration;

/// Turns a raw amount into words: minutes into "96 h", later cents into
/// "4.800 €". Every budget widget takes one so the same shapes serve both.
typedef BudgetAmountFormat = String Function(BuildContext context, int amount);

/// The default: minutes as the time module writes them everywhere else.
String budgetMinutes(BuildContext context, int minutes) =>
    fmtDuration(context, minutes);

/// What a level looks like. One place, so a bar, a capsule and a notice that
/// show the same gauge never disagree about its colour.
///
/// Colour never carries the level alone (WCAG 1.4.1): every surface writes the
/// percent, and [icon] changes once the limit is passed.
abstract final class BudgetStyle {
  /// The fill of a bar or ring. Each clears 3:1 against the track it sits on
  /// except honey below the warning share, whose track has its own rim.
  static Color fill(BudgetLevel level) => switch (level) {
    BudgetLevel.within => AppColors.accent,
    BudgetLevel.near => AppColors.warningBar,
    BudgetLevel.over => AppColors.danger,
  };

  /// Small text in the level's colour; every one clears 4.5:1.
  static Color ink(BudgetLevel level) => switch (level) {
    BudgetLevel.within => AppColors.inkSoft,
    BudgetLevel.near => AppColors.warningInk,
    BudgetLevel.over => AppColors.dangerInk,
  };

  static IconData icon(BudgetLevel level) => switch (level) {
    BudgetLevel.over => LucideIcons.triangleAlert,
    _ => LucideIcons.gauge,
  };

  /// "80 %", "80%" or "٨٠٪", as the reader's locale writes a percent.
  static String percent(BuildContext context, BudgetGauge gauge) {
    final locale = Localizations.maybeLocaleOf(context)?.toLanguageTag();
    return NumberFormat.percentPattern(locale).format(gauge.percent / 100);
  }

  /// "96 h of 120 h".
  static String usedOfLimit(
    BuildContext context,
    BudgetGauge gauge,
    BudgetAmountFormat format,
  ) => context.t(
    'budget.usedOfLimit',
    variables: {
      'used': format(context, gauge.used),
      'limit': format(context, gauge.limit),
    },
  );

  /// "24 h left" while under the limit, "used up" at it, "5 h over" past it.
  static String remainder(
    BuildContext context,
    BudgetGauge gauge,
    BudgetAmountFormat format,
  ) => gauge.reached
      ? context.t('budget.reached')
      : gauge.level == BudgetLevel.over
      ? context.t(
          'budget.overBy',
          variables: {'amount': format(context, gauge.overBy)},
        )
      : context.t(
          'budget.left',
          variables: {'amount': format(context, gauge.left)},
        );

  /// What a screen reader says for any of the shapes: label, percent, sums and
  /// what is left, in one sentence.
  static String semantics(
    BuildContext context,
    String label,
    BudgetGauge gauge,
    BudgetAmountFormat format,
  ) => context.t(
    'budget.semantics',
    variables: {
      'label': label,
      'percent': percent(context, gauge),
      'sums': usedOfLimit(context, gauge, format),
      'remainder': remainder(context, gauge, format),
    },
  );
}
