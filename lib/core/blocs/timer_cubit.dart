import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../api/api_client.dart';
import '../models/time_models.dart';
import '../repositories/time_repository.dart';

/// What a timer just reached, said once.
///
/// A one-shot on the state rather than a stream, for the same reason
/// [TimerState.errorMessage] is one: it belongs to the moment it happened, the
/// next state clears it, and whoever is listening app-wide sees it exactly
/// once. It names the interval that *ended*, because that is what the person is
/// being told about — "your work interval is over", not "a break is running".
class TimerSignal extends Equatable {
  const TimerSignal({
    required this.timerId,
    required this.mode,
    this.phase,
    this.cyclesDone = 0,
  });

  /// Which timer reached its target. Also what keeps it from being said twice.
  final String timerId;
  final TimerMode mode;

  /// The pomodoro half that ended, or null for a countdown.
  final TimerPhase? phase;

  /// Work intervals done *including* the one that just ended.
  final int cyclesDone;

  /// Whether what ended was a break — so the offer is "carry on", not "rest".
  bool get endedABreak => phase?.isBreak ?? false;

  @override
  List<Object?> get props => [timerId, mode, phase, cyclesDone];
}

/// The running timer, as the app knows it.
///
/// Two clocks meet here and only one of them is the truth. The **server** owns
/// whether a timer runs, what it is called and when it started — a timer begun
/// on a phone has to read the same on a laptop, and only the server can settle
/// that. The **device** owns the number on screen, ticking once a second from
/// [RunningTimer.startedAt], because a duration that only moved when a request
/// came back would sit still for a minute at a time.
///
/// It is hydrated so the bar is already there on the next launch instead of
/// appearing a round trip later — a first paint that says "no timer" and then
/// corrects itself reads as a bug. What is persisted is a cache, never an
/// authority: [refresh] runs on start, on resume and on every stream reconnect,
/// and its answer replaces whatever was restored.
class TimerState extends Equatable {
  const TimerState({
    this.timer,
    this.elapsed = Duration.zero,
    this.isBusy = false,
    this.errorMessage,
    this.signal,
  });

  /// The timer the server last told us about, or null when none runs.
  final RunningTimer? timer;

  /// How long it has been running, recomputed once a second while it runs.
  final Duration elapsed;

  /// A start/stop/discard is in flight — the buttons that would double it are
  /// disabled meanwhile.
  final bool isBusy;

  /// Why the last action failed, so the screen can toast it; cleared on the
  /// next state.
  ///
  /// A sentence, not a key: the server localizes its own error messages, so
  /// what arrives here is already in the reader's language.
  final String? errorMessage;

  /// The interval that just ran out, for one state only.
  final TimerSignal? signal;

  bool get isRunning => timer != null;

  /// What is left of the current interval, or null when nothing is counting
  /// towards anything.
  Duration? get remaining => timer == null
      ? null
      : (timer!.target == null ? null : timer!.target! - elapsed);

  TimerState copyWith({
    RunningTimer? timer,
    Duration? elapsed,
    bool? isBusy,
    String? errorMessage,
    TimerSignal? signal,
  }) => TimerState(
    timer: timer ?? this.timer,
    elapsed: elapsed ?? this.elapsed,
    isBusy: isBusy ?? this.isBusy,
    // Always replaced: an error belongs to the action that produced it.
    errorMessage: errorMessage,
    // And so does a signal — it is said once, by the state that carries it.
    signal: signal,
  );

  @override
  List<Object?> get props => [timer, elapsed, isBusy, errorMessage, signal];
}

class TimerCubit extends HydratedCubit<TimerState> {
  TimerCubit(this._repository, {required this.storageId})
    : super(const TimerState()) {
    // Restoring a running timer restores a stale elapsed time with it; tick it
    // forward at once so the first frame is right rather than a second old.
    if (state.isRunning) {
      _tick();
      _startTicking();
    }
  }

  final TimeRepository _repository;

  /// What separates one account's persisted timer from another's.
  ///
  /// Server URL plus user id, because [HydratedBloc] keeps one blob per
  /// [id] per device: without it, signing out and back in as somebody else
  /// would restore *their* timer under your name — on a shared machine, on the
  /// same server, showing what the other person is working on. Sign-out clears
  /// the storage as well; this is the guard for the case where it did not run.
  final String storageId;

  @override
  String get id => storageId;

  Timer? _ticker;

  /// Re-reads the timer from the server. The answer wins over anything held.
  ///
  /// Called on start, on app resume and on every SSE reconnect. A failure keeps
  /// what we have — a dropped network must not make a running timer vanish from
  /// the bar — except when the server says the module is gone, which the API
  /// layer turns into a `/meta` re-read of its own.
  Future<void> refresh() async {
    try {
      _apply(await _repository.timer());
    } on ApiFailure catch (_) {
      // Keep the last known state; the ticker keeps counting.
    }
  }

  /// Starts one. How it counts is decided here and cannot be changed by a
  /// later [patch] — see [TimeRepository.startTimer].
  Future<void> start({
    String? projectId,
    String? issueId,
    String? description,
    String? activityType,
    List<String> tags = const [],
    bool? billable,
    TimerMode mode = TimerMode.stopwatch,
    int? plannedMinutes,
    PomodoroConfig? pomodoro,
  }) => _act(
    () => _repository.startTimer(
      projectId: projectId,
      issueId: issueId,
      description: description,
      activityType: activityType,
      tags: tags,
      billable: billable,
      mode: mode,
      plannedMinutes: plannedMinutes,
      pomodoro: pomodoro,
    ),
  );

  /// Ends the running pomodoro phase and begins the next.
  ///
  /// A work interval becomes an entry on the way; a break becomes nothing. The
  /// running timer's id goes with it, so a retry after a timeout answers with
  /// the phase that is running instead of skipping the next one.
  Future<void> advancePhase() {
    final running = state.timer;
    if (running == null) return Future.value();
    return _act(() => _repository.advancePhase(timerId: running.id));
  }

  /// Changes one or two things about the running timer, keeping the rest.
  ///
  /// The endpoint takes the timer's whole editable state — a field it does not
  /// receive is cleared — so the parts this call does not mention are read back
  /// off the timer we hold. That is what lets a caller say "file it under this
  /// project" without also having to restate the description, the tags and the
  /// billable flag, and without those quietly disappearing if it forgets.
  Future<void> patch({
    String? projectId,
    String? issueId,
    String? description,
    String? activityType,
    List<String>? tags,
    bool? billable,
    bool clearPlacement = false,
  }) {
    final current = state.timer;
    if (current == null) return Future.value();
    return _act(
      () => _repository.patchTimer(
        projectId: clearPlacement ? null : (projectId ?? current.projectId),
        issueId: clearPlacement ? null : (issueId ?? current.issueId),
        description: description ?? current.description,
        activityType: activityType ?? current.activityType,
        tags: tags ?? current.tags,
        billable: billable ?? current.billable,
      ),
    );
  }

  Future<void> continueEntry(String entryId) =>
      _act(() => _repository.continueEntry(entryId));

  /// Stops the timer and returns the entry it became, or null if it failed.
  Future<SavedTimeEntry?> stop({
    String? projectId,
    String? issueId,
    String? description,
    String? activityType,
    List<String>? tags,
    bool? billable,
  }) async {
    final running = state.timer;
    if (state.isBusy || running == null) return null;
    emit(state.copyWith(isBusy: true));
    try {
      final saved = await _repository.stopTimer(
        // Name the timer we mean, so a retry after a timeout cannot end a
        // different one that was started in the meantime.
        timerId: running.id,
        projectId: projectId,
        issueId: issueId,
        description: description,
        activityType: activityType,
        tags: tags,
        billable: billable,
      );
      _apply(null);
      return saved;
    } on ApiFailure catch (failure) {
      emit(state.copyWith(isBusy: false, errorMessage: failure.message));
      return null;
    }
  }

  Future<void> discard() async {
    if (state.isBusy) return;
    emit(state.copyWith(isBusy: true));
    try {
      await _repository.discardTimer();
      _apply(null);
    } on ApiFailure catch (failure) {
      emit(state.copyWith(isBusy: false, errorMessage: failure.message));
    }
  }

  /// Applies what the server said, and starts or stops the local ticker to
  /// match. The one place the timer field changes.
  void _apply(RunningTimer? timer) {
    // A different timer is a different interval, so whatever was announced
    // about the last one does not carry. Kept when the id is the same, because
    // a plain refresh must not make the app say the same thing twice.
    if (timer?.id != _signalled) _signalled = null;
    emit(
      timer == null
          ? const TimerState()
          : TimerState(timer: timer, elapsed: timer.elapsed(DateTime.now())),
    );
    if (timer == null) {
      _stopTicking();
    } else {
      _startTicking();
    }
  }

  Future<void> _act(Future<RunningTimer> Function() action) async {
    if (state.isBusy) return;
    emit(state.copyWith(isBusy: true));
    try {
      _apply(await action());
    } on ApiFailure catch (failure) {
      emit(state.copyWith(isBusy: false, errorMessage: failure.message));
    }
  }

  void _startTicking() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _stopTicking() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// The timer this cubit has already announced the end of.
  ///
  /// Every phase is a new document with a new id, so one id per announcement is
  /// exactly one announcement per interval — and it survives the app being
  /// backgrounded past the end and coming back to find the target long gone.
  String? _signalled;

  void _tick() {
    final timer = state.timer;
    if (timer == null) {
      _stopTicking();
      return;
    }
    final now = DateTime.now();
    final elapsed = timer.elapsed(now);
    final reached = timer.hasReachedTarget(now) && _signalled != timer.id;
    // Only whole seconds move the state: the bar renders to the second, and
    // emitting an identical duration would rebuild it for nothing. An interval
    // running out is worth a state of its own whatever the second says.
    if (!reached && elapsed.inSeconds == state.elapsed.inSeconds) return;
    if (!reached) {
      emit(state.copyWith(elapsed: elapsed));
      return;
    }
    _signalled = timer.id;
    emit(
      state.copyWith(
        elapsed: elapsed,
        signal: TimerSignal(
          timerId: timer.id,
          mode: timer.mode,
          phase: timer.phase,
          // The interval that just ended counts, so a work phase reports the
          // number it completes rather than the number it started after.
          cyclesDone: timer.phase == TimerPhase.work
              ? timer.cyclesDone + 1
              : timer.cyclesDone,
        ),
      ),
    );
    if (timer.mode == TimerMode.countdown) {
      // A countdown ends itself. The person asked for twenty-five minutes and
      // is not necessarily at the screen when they are up; the server decides
      // the entry's length against its own clock, so what arrives late is still
      // worth exactly what was asked for. A pomodoro deliberately does *not*
      // do this — the next phase is the person's decision, and the toast is
      // where they make it.
      //
      // A stop that fails is not retried: the timer keeps running, the person
      // ends it when they see it, and the entry is still exactly the target
      // because the server caps it there. Retrying on the next tick would mean
      // a request a second for as long as the network is down.
      unawaited(stop());
    }
  }

  @override
  Future<void> close() {
    _stopTicking();
    return super.close();
  }

  /// What is currently on disk, so an unchanged state is not rewritten.
  ///
  /// The ticker emits once a second while a timer runs, and a hydrated bloc
  /// persists on *every* emit with no equality check of its own — so without
  /// this the app would append a byte-identical blob to the store once a
  /// second, on the UI isolate, and trip the box's compaction threshold about
  /// once a minute for as long as the timer is running. The elapsed time is not
  /// persisted at all; it is recomputed from the start.
  String? _persisted;

  /// Only the timer itself is persisted. [TimerState.elapsed] is derived from
  /// its start, [isBusy] belongs to a request that is long over by the next
  /// launch, and an error nobody saw is not worth restoring.
  @override
  TimerState? fromJson(Map<String, dynamic> json) {
    final timer = json['timer'];
    if (timer is! Map<String, dynamic>) return const TimerState();
    try {
      final restored = RunningTimer.fromJson(timer);
      // What was read is what is on disk, so restoring and then ticking does
      // not immediately write the same thing back.
      _persisted = _tokenOf(restored);
      return TimerState(
        timer: restored,
        elapsed: restored.elapsed(DateTime.now()),
      );
    } catch (_) {
      // A blob written by an older shape is not worth crashing the app over;
      // the refresh a moment later replaces it anyway.
      return const TimerState();
    }
  }

  @override
  Map<String, dynamic>? toJson(TimerState state) {
    final token = _tokenOf(state.timer);
    // Null means "nothing to write" to hydrated_bloc, which is exactly right
    // for a tick: the second changed, and nothing that is persisted did.
    if (token == _persisted) return null;
    _persisted = token;
    final timer = state.timer;
    if (timer == null) return {};
    return {
      'timer': {
        'id': timer.id,
        'startedAt': timer.startedAt.toUtc().toIso8601String(),
        'projectId': timer.projectId,
        'issueId': timer.issueId,
        'description': timer.description,
        'activityType': timer.activityType,
        'tags': timer.tags,
        'billable': timer.billable,
        'mode': timer.mode.wire,
        'plannedMinutes': timer.plannedMinutes,
        'pomodoro': timer.pomodoro?.toJson(),
        'phase': switch (timer.phase) {
          null => null,
          TimerPhase.work => 'WORK',
          TimerPhase.shortBreak => 'BREAK',
          TimerPhase.longBreak => 'LONG_BREAK',
        },
        'phaseStartedAt': timer.phaseStartedAt?.toUtc().toIso8601String(),
        'cyclesDone': timer.cyclesDone,
      },
    };
  }

  /// Everything [toJson] would write, as one comparable string. Cheaper than
  /// building the map twice and comparing it deeply, and it changes whenever
  /// any persisted field does.
  static String _tokenOf(RunningTimer? timer) => timer == null
      ? '-'
      : [
          timer.id,
          timer.startedAt.microsecondsSinceEpoch,
          timer.projectId,
          timer.issueId,
          timer.description,
          timer.activityType,
          timer.tags.join(','),
          timer.billable,
          timer.mode.name,
          timer.plannedMinutes,
          timer.pomodoro,
          timer.phase?.name,
          timer.phaseStartedAt?.microsecondsSinceEpoch,
          timer.cyclesDone,
        ].join('|');
}
