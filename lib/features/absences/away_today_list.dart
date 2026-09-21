import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/team_absence_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart' show HiveAvatar;
import 'team_absence_style.dart';

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
                        teamAbsenceLabelWithState(context, row.entries.first),
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
}

/// Reads who is away today and shows it: one page of [shown], and the server's
/// total for the rest. The dashboard card is this inside its glass.
class AwayToday extends StatefulWidget {
  const AwayToday({super.key});

  /// How many names a card has room for; the rest is a count.
  static const shown = 5;

  @override
  State<AwayToday> createState() => _AwayTodayState();
}

class _AwayTodayState extends State<AwayToday> {
  late final FetchCubit<TeamAbsencePage> _today;

  @override
  void initState() {
    super.initState();
    final day = DateUtils.dateOnly(DateTime.now());
    final repository = context.read<AbsenceRepository>();
    _today = FetchCubit<TeamAbsencePage>(
      () => repository.teamCalendar(
        from: day,
        to: day,
        awayOnly: true,
        size: AwayToday.shown,
      ),
    );
    unawaited(_today.load());
  }

  @override
  void dispose() {
    unawaited(_today.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<FetchCubit<TeamAbsencePage>, FetchState<TeamAbsencePage>>(
        bloc: _today,
        builder: (context, state) {
          final page = state.data;
          if (page != null) return AwayTodayList(page: page);
          if (state.errorKey != null) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                context.t(state.errorKey!),
                style: TextStyle(color: AppColors.inkSoft),
              ),
            );
          }
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(child: HiveLoader(size: 24)),
          );
        },
      );
}
