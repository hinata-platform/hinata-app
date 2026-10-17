import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../i18n/i18n.dart';
import '../../models/time_usage_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';

/// One line under a budget: when it runs out at the present pace (HIN-156).
/// Always "at the same pace", because it is arithmetic, not a promise; and
/// "too little data" rather than a date drawn from two days.
class ForecastLine extends StatelessWidget {
  const ForecastLine({super.key, required this.forecast});

  final BudgetForecast forecast;

  /// The sentence alone, for places with no room for the glyph (a cell).
  static String? sentence(BuildContext context, BudgetForecast forecast) {
    if (forecast.leftMinutes == null) return null;
    if (forecast.leftMinutes == 0) return context.t('budget.forecast.spent');
    if (forecast.lowConfidence) return context.t('budget.forecast.tooLittle');
    final day = forecast.exhaustedOn;
    if (day == null) return context.t('budget.forecast.noPace');
    final locale = Localizations.localeOf(context).toLanguageTag();
    return context.t(
      'budget.forecast.lastsUntil',
      variables: {'date': DateFormat.MMMd(locale).format(day)},
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = sentence(context, forecast);
    if (text == null) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            LucideIcons.trendingUp,
            size: 14,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: AppType.caption,
              height: 1.4,
              color: AppColors.inkSoft,
            ),
          ),
        ),
      ],
    );
  }
}
