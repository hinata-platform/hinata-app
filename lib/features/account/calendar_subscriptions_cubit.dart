import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/models/time_models.dart';
import '../../core/repositories/time_repository.dart';

/// What the settings section shows of the reader's calendar subscriptions.
class CalendarSubscriptionsState extends Equatable {
  const CalendarSubscriptionsState({
    this.items = const [],
    this.loading = true,
    this.errorKey,
    this.busy = const {},
  });

  final List<CalendarSubscription> items;
  final bool loading;

  /// Why the list could not be read, as a message key; null once it was.
  final String? errorKey;

  /// Subscriptions with a change of their own in the air, so their row can say
  /// so and not be acted on twice.
  final Set<String> busy;

  bool get atLimit => items.length >= CalendarSubscriptionsCubit.limit;

  CalendarSubscriptionsState copyWith({
    List<CalendarSubscription>? items,
    bool? loading,
    String? errorKey,
    bool clearError = false,
    Set<String>? busy,
  }) => CalendarSubscriptionsState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    errorKey: clearError ? null : errorKey ?? this.errorKey,
    busy: busy ?? this.busy,
  );

  @override
  List<Object?> get props => [items, loading, errorKey, busy];
}

/// The reader's calendar subscriptions (HIN-94): the list, adding, editing,
/// switching one off, removing, and reading one again now.
///
/// A read runs on the server after the answer, so a subscription comes back
/// [CalendarSubscriptionStatus.running]. While any is, the cubit asks again
/// every few seconds, for a bounded while, so the row settles on its outcome
/// without the reader having to leave and come back.
///
/// Writes throw the repository's [ApiFailure] for the view to show; the list
/// itself only ever changes from what the server answered.
class CalendarSubscriptionsCubit extends Cubit<CalendarSubscriptionsState> {
  CalendarSubscriptionsCubit(
    this._time, {
    this.pollEvery = const Duration(seconds: 2),
    this.pollFor = const Duration(seconds: 30),
  }) : super(const CalendarSubscriptionsState());

  /// Subscriptions one person may keep; the server refuses an eleventh.
  static const int limit = 10;

  final TimeRepository _time;
  final Duration pollEvery;
  final Duration pollFor;

  Timer? _poll;
  DateTime? _pollUntil;

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final items = await _time.calendarSubscriptions();
      if (isClosed) return;
      emit(state.copyWith(items: items, loading: false));
      _watchRunning();
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      emit(state.copyWith(loading: false, errorKey: failure.message));
    }
  }

  Future<CalendarSubscription> create(CalendarSubscriptionDraft draft) async {
    final saved = await _time.createCalendarSubscription(draft);
    _put(saved);
    return saved;
  }

  Future<CalendarSubscription> update(
    String id,
    CalendarSubscriptionDraft draft,
  ) => _busyWith(id, () => _time.updateCalendarSubscription(id, draft));

  Future<CalendarSubscription> setEnabled(String id, {required bool enabled}) =>
      _busyWith(
        id,
        () => _time.setCalendarSubscriptionEnabled(id, enabled: enabled),
      );

  Future<CalendarSubscription> refresh(String id) =>
      _busyWith(id, () => _time.refreshCalendarSubscription(id));

  Future<void> delete(String id) async {
    _mark(id, busy: true);
    try {
      await _time.deleteCalendarSubscription(id);
      if (isClosed) return;
      emit(
        state.copyWith(
          items: [
            for (final item in state.items)
              if (item.id != id) item,
          ],
        ),
      );
    } finally {
      _mark(id, busy: false);
    }
  }

  Future<CalendarSubscription> _busyWith(
    String id,
    Future<CalendarSubscription> Function() call,
  ) async {
    _mark(id, busy: true);
    try {
      final saved = await call();
      _put(saved);
      return saved;
    } finally {
      _mark(id, busy: false);
    }
  }

  void _mark(String id, {required bool busy}) {
    if (isClosed) return;
    emit(
      state.copyWith(
        busy: {
          for (final held in state.busy)
            if (held != id) held,
          if (busy) id,
        },
      ),
    );
  }

  /// Puts [saved] in place of the row with its id, or at the end.
  void _put(CalendarSubscription saved) {
    if (isClosed) return;
    final items = [...state.items];
    final at = items.indexWhere((item) => item.id == saved.id);
    if (at < 0) {
      items.add(saved);
    } else {
      items[at] = saved;
    }
    emit(state.copyWith(items: items));
    _watchRunning(restart: true);
  }

  /// Asks again while a read is running, at most [pollFor] after the last
  /// change that started one.
  void _watchRunning({bool restart = false}) {
    final running = state.items.any(
      (item) => item.status == CalendarSubscriptionStatus.running,
    );
    if (!running) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    if (restart || _pollUntil == null) {
      _pollUntil = DateTime.now().add(pollFor);
    }
    _poll ??= Timer.periodic(pollEvery, (_) => unawaited(_tick()));
  }

  Future<void> _tick() async {
    final until = _pollUntil;
    if (until == null || DateTime.now().isAfter(until)) {
      _poll?.cancel();
      _poll = null;
      _pollUntil = null;
      return;
    }
    try {
      final items = await _time.calendarSubscriptions();
      if (isClosed) return;
      emit(state.copyWith(items: items));
      _watchRunning();
    } on ApiFailure {
      // The next tick asks again; the rows keep what they last said.
    }
  }

  @override
  Future<void> close() {
    _poll?.cancel();
    return super.close();
  }
}
