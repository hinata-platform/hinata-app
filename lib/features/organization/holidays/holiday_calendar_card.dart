import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/availability_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/soft_card.dart';
import '../../../core/theme/app_type.dart';

/// One holiday calendar on the admin page: its name and region, where its
/// holidays come from, how the last import went, and what can be done with it.
class HolidayCalendarCard extends StatelessWidget {
  const HolidayCalendarCard({
    super.key,
    required this.calendar,
    required this.year,
    required this.selected,
    required this.onSelect,
    required this.onImport,
    required this.onEdit,
    required this.onDelete,
  });

  final HolidayCalendar calendar;
  final int year;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onImport;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final status = _status(context);
    return SoftCard(
      onTap: onSelect,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Container(
        decoration: BoxDecoration(
          border: BorderDirectional(
            start: BorderSide(
              color: selected ? AppColors.accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsetsDirectional.only(start: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        calendar.name,
                        style: TextStyle(
                          fontSize: AppType.body,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      if (calendar.defaultCalendar)
                        _Badge(context.t('availability.admin.defaultBadge')),
                      if (calendar.platformDefault)
                        _Badge(
                          context.t('availability.admin.platformBadge'),
                          quiet: true,
                        ),
                    ],
                  ),
                  if (calendar.region != null)
                    Text(
                      calendar.region!,
                      style: TextStyle(
                        fontSize: AppType.caption,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    calendar.hasRules
                        ? context.t(
                            'availability.admin.rulesFrom',
                            variables: {
                              'region': calendar.rulesName ?? calendar.rules!,
                            },
                          )
                        : calendar.feedHost == null
                        ? context.t('availability.admin.byHand')
                        : context.t(
                            'availability.admin.feedFrom',
                            variables: {'host': calendar.feedHost!},
                          ),
                    style: TextStyle(
                      fontSize: AppType.caption,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: AppType.caption,
                        height: 1.35,
                        color: calendar.importFailed
                            ? AppColors.dangerInk
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (calendar.hasFeed == true || calendar.hasRules)
              calendar.importing
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: HiveLoader(size: 18),
                      ),
                    )
                  : IconButton(
                      tooltip: context.t(
                        calendar.hasRules
                            ? 'availability.admin.refillYear'
                            : 'availability.admin.importYear',
                        variables: {'year': '$year'},
                      ),
                      onPressed: onImport,
                      icon: Icon(
                        calendar.hasRules
                            ? LucideIcons.refreshCw
                            : LucideIcons.download,
                        size: 18,
                        color: AppColors.inkSoft,
                      ),
                    ),
            IconButton(
              tooltip: context.t('availability.admin.editCalendar'),
              onPressed: onEdit,
              icon: Icon(
                LucideIcons.pencil,
                size: 17,
                color: AppColors.inkSoft,
              ),
            ),
            IconButton(
              tooltip: context.t('availability.admin.deleteCalendar'),
              onPressed: onDelete,
              icon: Icon(
                LucideIcons.trash2,
                size: 17,
                color: AppColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _status(BuildContext context) {
    if (calendar.importing) return context.t('availability.admin.importing');
    if (calendar.importFailed) {
      // The server's sentence is whole and already in the reader's language,
      // so it stands on its own rather than inside one of ours.
      return calendar.lastImportError ??
          context.t('availability.admin.importFailed');
    }
    // The rules fill each year on their own; the numbers of the last fill
    // would only say that again.
    if (calendar.hasRules) return context.t('availability.admin.rulesAuto');
    final summary = calendar.lastImport;
    final at = calendar.lastImportedAt;
    if (summary == null || at == null) return null;
    final variables = {
      'year': '${summary.year}',
      'date': MaterialLocalizations.of(context).formatMediumDate(at),
      'added': '${summary.added}',
      'updated': '${summary.updated}',
      'unchanged': '${summary.unchanged}',
    };
    if (summary.capped == 0) {
      return context.t('availability.admin.importDone', variables: variables);
    }
    // One sentence with both halves: how two sentences are joined is the
    // language's business, not a space in the code.
    return context.t(
      'availability.admin.importDoneCapped',
      count: summary.capped,
      variables: {...variables, 'max': '${Holiday.perYearMax}'},
    );
  }
}

/// A small pill beside the calendar's name.
class _Badge extends StatelessWidget {
  const _Badge(this.label, {this.quiet = false});

  final String label;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: quiet ? Colors.transparent : AppColors.accentSoft,
        borderRadius: BorderRadius.circular(999),
        border: quiet ? Border.all(color: AppColors.hairline) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppType.caption,
          fontWeight: FontWeight.w700,
          color: quiet ? AppColors.textSecondary : AppColors.accentInk,
        ),
      ),
    );
  }
}
