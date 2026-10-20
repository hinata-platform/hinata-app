import 'dart:async';

import '../../../core/blocs/paged_cubit.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/shift_repository.dart';
import 'shift_changes.dart';

/// The events list (HIN-44): every visible project's, or one project's,
/// from today over the next two months, paged.
///
/// A change made anywhere in the module moves an event's totals, which only
/// the server counts: the rows held are read again in one request, keeping
/// the scroll position, and only while the list is on screen.
class ShiftEventsCubit extends PagedCubit<ShiftEventSummary>
    with ShiftStaleWhileHidden {
  ShiftEventsCubit(
    ShiftRepository shifts, {
    DateTime Function()? now,
    Stream<ShiftChange>? changes,
    int pageSize = 25,
  }) : this._(shifts, _Filter(), now ?? DateTime.now, changes, pageSize);

  ShiftEventsCubit._(
    ShiftRepository shifts,
    _Filter filter,
    DateTime Function() now,
    Stream<ShiftChange>? changes,
    int pageSize,
  ) : _filter = filter,
      super(
        (page, size) {
          final today = now();
          final from = DateTime(today.year, today.month, today.day);
          return shifts.events(
            from: from,
            // The server reads at most 62 days at once.
            to: DateTime(from.year, from.month, from.day + window),
            projectId: filter.projectId,
            page: page,
            size: size,
          );
        },
        pageSize: pageSize,
        keyOf: (event) => event.id,
      ) {
    _changes = ShiftChangeDebouncer((_) => markStale(), changes: changes);
  }

  /// How many days ahead the list reads.
  static const window = 61;

  final _Filter _filter;
  late final ShiftChangeDebouncer _changes;

  /// The project the list is narrowed to, null for all.
  String? get projectId => _filter.projectId;

  @override
  void refreshStale() => unawaited(refreshLoaded());

  /// Narrows the list to [projectId] (null: all projects) and reads it again.
  Future<void> filter(String? projectId) {
    _filter.projectId = projectId;
    return load();
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}

class _Filter {
  String? projectId;
}
