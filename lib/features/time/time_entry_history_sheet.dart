import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_policy_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/time_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../sprint/modals/glass_modal.dart';

/// Who changed this entry, and what they changed.
///
/// The audit trail exists so that a correction to somebody's record of their own
/// working time is findable afterwards. A trail only an administrator can read
/// would be a covert one — so the person it is about reads it here, on the entry
/// itself, and the same rule that decides whether a lead may see the entry
/// decides whether they may see this.
///
/// Deliberately narrower than the admin audit screen: the action, when, who, and
/// the fields that moved. No client address and no user-agent — those belong to a
/// security investigation, and on a screen every colleague can open they would
/// answer a question nobody asked about where somebody works from.
Future<void> showTimeEntryHistorySheet(
  BuildContext context, {
  required WorkItem entry,
}) {
  final time = context.read<TimeRepository>();
  return showGlassModal<void>(
    context,
    adaptive: true,
    width: 480,
    builder: (_) => RepositoryProvider<TimeRepository>.value(
      value: time,
      child: BlocProvider(
        create: (_) => PagedCubit<TimeEntryHistoryEntry>(
          (page, size) => time.history(entry.id, page: page, size: size),
          pageSize: 25,
          keyOf: (row) => row.id,
        )..load(),
        child: _HistoryBody(entry: entry),
      ),
    ),
  );
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({required this.entry});

  final WorkItem entry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.history,
          title: context.t('time.history.title'),
          subtitle: context.t('time.history.subtitle'),
        ),
        // What the entry itself knows, always: an instance that has not switched
        // the creation event on still has a first line, because the entry
        // carries its own creation date and the way it was filed.
        _Created(entry: entry),
        // Only the *list* is flexible. Everything else here sizes to what it
        // says, which is the difference between a panel that fits its content
        // and one that is nearly always mostly empty: `HiveEmptyState(card:
        // false)` ends in a `Center`, and a `Center` handed a bounded height
        // takes all of it. Under a `Flexible` on a desktop that is the whole
        // modal — a two-line "nobody else changed it" floating in eight hundred
        // points of nothing.
        BlocBuilder<
          PagedCubit<TimeEntryHistoryEntry>,
          PagedState<TimeEntryHistoryEntry>
        >(
          builder: (context, state) {
            if (state.isLoading && state.items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: HiveLoader(size: 34),
              );
            }
            if (state.items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: HiveEmptyState(
                  title: context.t('time.history.emptyTitle'),
                  message: context.t('time.history.emptyMessage'),
                  card: false,
                ),
              );
            }
            // A `Flexible` reaches the Column's render object through the
            // builder above it — parent data walks up past widgets that are not
            // render objects — so the rows still get to fill the space they have
            // and scroll inside it once there are more than fit.
            return Flexible(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.pixels >=
                      notification.metrics.maxScrollExtent - 200) {
                    context
                        .read<PagedCubit<TimeEntryHistoryEntry>>()
                        .loadMore();
                  }
                  return false;
                },
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                  itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= state.items.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: HiveLoader(size: 24)),
                      );
                    }
                    return _HistoryRow(row: state.items[index]);
                  },
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Created extends StatelessWidget {
  const _Created({required this.entry});

  final WorkItem entry;

  @override
  Widget build(BuildContext context) {
    final created = entry.createdAt;
    if (created == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          Icon(LucideIcons.plus, size: 14, color: AppColors.inkFaint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.t(
                'time.history.created',
                variables: {
                  'when': _when(context, created),
                  'source': context.t('time.source.${entry.source}'),
                },
              ),
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

/// A moment, in the reader's language — the same shape the audit screen uses,
/// so one record read in two places does not look like two.
String _when(BuildContext context, DateTime moment) => DateFormat.yMMMd(
  Localizations.localeOf(context).toString(),
).add_Hm().format(moment.toLocal());

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.row});

  final TimeEntryHistoryEntry row;

  /// The metadata keys this row renders.
  ///
  /// The server allow-lists what it sends; this is the narrower question of what
  /// reads as a sentence. `project` and `issue` are in the record as ObjectId
  /// hex, and "Projekt: 66f0a1b2c3d4e5f60718293a" tells a reader nothing they
  /// could act on — they come back when the response can name them.
  static const _shown = ['minutes', 'date'];

  @override
  Widget build(BuildContext context) {
    final when = row.timestamp;
    final details = [
      for (final key in _shown)
        if (row.metadata[key] != null)
          '${context.t('time.history.field.$key')}: ${row.metadata[key]}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t('audit.action.${row.action}'),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (when != null)
                Text(
                  _when(context, when),
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            row.actorLabel ?? context.t('audit.actor.system'),
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              details.join(' · '),
              style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
            ),
          ],
        ],
      ),
    );
  }
}
