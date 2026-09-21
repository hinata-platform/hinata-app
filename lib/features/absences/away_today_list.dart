import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/team_absence_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_widgets.dart' show HiveAvatar;
import 'team_absence_calendar.dart' show teamAbsenceLabel;

/// Who is away today, as the dashboard card lists it (HIN-118): the names of
/// the page it is handed, then how many more the day holds.
///
/// The card asks for one page of five, so this never lists more than it was
/// given and never counts anybody itself — the total is the server's.
class AwayTodayList extends StatelessWidget {
  const AwayTodayList({super.key, required this.page});

  final TeamAbsencePage page;

  @override
  Widget build(BuildContext context) {
    final rows = page.rows;
    final more = page.total - rows.length;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          context.t('dashboard.awayNone'),
          style: TextStyle(color: AppColors.inkSoft),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, row) in rows.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: index == rows.length - 1 && more <= 0
                  ? null
                  : Border(bottom: BorderSide(color: AppColors.hairline2)),
            ),
            child: MergeSemantics(
              child: Row(
                children: [
                  HiveAvatar(name: row.name, imageUrl: row.avatarUrl, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (row.entries.isNotEmpty)
                    Flexible(
                      child: Text(
                        _label(context, row.entries.first),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (more > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              context.t('dashboard.awayMore', variables: {'count': '$more'}),
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
          ),
      ],
    );
  }

  static String _label(BuildContext context, TeamAbsenceEntry entry) {
    final label = teamAbsenceLabel(context, entry);
    return entry.requested
        ? '$label · ${context.t('absence.team.legend.requested')}'
        : label;
  }
}
