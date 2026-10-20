import 'package:equatable/equatable.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../../../core/models/shift_models.dart';

/// What "Meine Schichten" can show without a connection.
///
/// Small on purpose: the next shift and the first rows as ids, times, titles
/// and counts. No names of other people and no ids of them either, not even
/// who assigned the shift; the snapshot sits on a device somebody else may
/// pick up.
class MyShiftsSnapshot extends Equatable {
  const MyShiftsSnapshot({this.next, this.rows = const [], this.savedAt});

  final MyShift? next;
  final List<MyShift> rows;
  final DateTime? savedAt;

  bool get isEmpty => next == null && rows.isEmpty;

  /// How many rows are kept at most.
  static const maxRows = 50;

  @override
  List<Object?> get props => [next, rows, savedAt];
}

/// Holds [MyShiftsSnapshot] across launches, per server and account
/// ([storageId], the same identity the timer uses).
///
/// Written only after a fresh first page ([recordRows]) and a fresh next
/// shift ([recordNext]), never while scrolling. Cleared on sign-out, when the
/// session is revoked (both arrive as the account going away) and when the
/// module is switched off.
class MyShiftsSnapshotCubit extends HydratedCubit<MyShiftsSnapshot> {
  MyShiftsSnapshotCubit({required this.storageId, DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(const MyShiftsSnapshot());

  final String storageId;
  final DateTime Function() _now;

  @override
  String get id => storageId;

  void recordRows(List<MyShift> rows) => emit(
    MyShiftsSnapshot(
      next: state.next,
      rows: rows.take(MyShiftsSnapshot.maxRows).toList(growable: false),
      savedAt: _now(),
    ),
  );

  void recordNext(MyShift? next) =>
      emit(MyShiftsSnapshot(next: next, rows: state.rows, savedAt: _now()));

  /// Forgets everything, in memory and on disk.
  Future<void> forget() async {
    emit(const MyShiftsSnapshot());
    await clear();
  }

  @override
  MyShiftsSnapshot? fromJson(Map<String, dynamic> json) {
    try {
      final next = json['next'];
      return MyShiftsSnapshot(
        next: next is Map<String, dynamic> ? MyShift.fromJson(next) : null,
        rows: [
          for (final row in (json['rows'] as List?) ?? const [])
            if (row is Map<String, dynamic>) MyShift.fromJson(row),
        ],
        savedAt: DateTime.tryParse(json['savedAt'] as String? ?? ''),
      );
    } catch (_) {
      return const MyShiftsSnapshot();
    }
  }

  @override
  Map<String, dynamic>? toJson(MyShiftsSnapshot state) => {
    'next': state.next?.toSnapshotJson(),
    'rows': [for (final row in state.rows) row.toSnapshotJson()],
    'savedAt': state.savedAt?.toUtc().toIso8601String(),
  };
}
