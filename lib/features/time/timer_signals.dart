import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/blocs/time_preferences_cubit.dart';
import '../../core/blocs/timer_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_models.dart';
import '../../core/router/app_router.dart' show rootNavigatorKey;
import '../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassToastIn;

/// Says, once, that an interval has ended.
///
/// Three ways, because one is not enough and none of them is a notification:
/// a toast where the app is, a short chime if the person asked for one, and the
/// window title on the platforms that have one. Deliberately *not* a system
/// notification — that needs a plugin the project does not carry, and a
/// scheduler that would keep telling somebody about a timer after they closed
/// the app is a different feature with a different consent question (stage 11).
///
/// Mounted above the router rather than in the shell, because the focus screen
/// is a route outside the shell and the whole point of it is being the place
/// where intervals end.
class TimerSignals extends StatefulWidget {
  const TimerSignals({super.key, required this.appTitle, required this.child});

  /// What the window title goes back to after a flash. Handed in rather than
  /// hard-coded: a self-hosted instance names itself, and that name must
  /// survive.
  final String appTitle;

  final Widget child;

  @override
  State<TimerSignals> createState() => _TimerSignalsState();
}

class _TimerSignalsState extends State<TimerSignals> {
  /// The sample, in the asset bundle. Forty kilobytes of two-tone bell.
  static const String _chime = 'assets/sounds/interval_end.wav';

  AudioPlayer? _player;
  Timer? _titleReset;

  /// How many times playing the chime has failed.
  ///
  /// Two strikes, then silence for the rest of the session. One is not enough:
  /// a browser that has not been interacted with, or an output device unplugged
  /// mid-session, is a failure that may not repeat, and latching on the first
  /// would silence somebody's chime for the day over a transient. Unbounded is
  /// not right either — a platform with no audio stack will not grow one, and
  /// asking it again at the end of every interval is a decoder it cannot build,
  /// for ever.
  int _chimeFailures = 0;

  @override
  void dispose() {
    _titleReset?.cancel();
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocListener<TimerCubit, TimerState>(
    listenWhen: (previous, current) =>
        current.signal != null ||
        (current.errorMessage != null &&
            previous.errorMessage != current.errorMessage),
    listener: (context, state) {
      final failure = state.errorMessage;
      if (failure != null) _complain(failure);
      final signal = state.signal;
      if (signal != null) _announce(context, signal);
    },
    child: widget.child,
  );

  /// A start, stop, discard or phase change that failed.
  ///
  /// Said here rather than in the timer bar, which is where it used to be said.
  /// The bar is mounted on three screens; the buttons that can produce these
  /// failures are now everywhere — the focus route, which is outside the shell,
  /// three keyboard shortcuts and a command. Pressing ⌘⇧S on the dashboard and
  /// watching a button do nothing was the alternative, with the server's
  /// explanation translated into nine languages and unreadable in all of them.
  void _complain(String message) {
    final overlay = rootNavigatorKey.currentState?.overlay;
    final context = rootNavigatorKey.currentContext;
    if (overlay == null || context == null || !context.mounted) return;
    showGlassToastIn(
      overlay,
      // Already a sentence in the reader's language — the server localizes its
      // own messages. t() is idempotent for anything that is not a key.
      context.t(message),
      kind: GlassToastKind.error,
    );
  }

  void _announce(BuildContext context, TimerSignal signal) {
    // The root navigator's own overlay, not `Overlay.of(context)`. This widget
    // is mounted in `MaterialApp.router`'s builder — above the navigator, which
    // is the only place it can be if the focus route is to be covered — and
    // `Overlay.of` looks *upwards*, so from here it finds nothing at all.
    // `showGlassToastIn` carries the reason; `app.dart` already does this for
    // its own app-level notice.
    final overlay = rootNavigatorKey.currentState?.overlay;
    final message = _message(context, signal);
    // The chime does not need a navigator, so it is not skipped when there is
    // none: an interval ending is not a moment to lose the sound as well as the
    // message. The title needs one only to localize itself, and it is handed
    // this context rather than looking one up again.
    if (overlay == null) {
      _sound(context);
      return;
    }
    final cubit = context.read<TimerCubit>();
    showGlassToastIn(
      overlay,
      message,
      kind: GlassToastKind.info,
      // The offer, not the decision. A pomodoro does not turn its own phase —
      // whether the break starts now is the person's to say, and a toast that
      // acted by itself would be the app keeping their rhythm for them.
      actionLabel: signal.mode == TimerMode.pomodoro
          ? context.t(
              signal.endedABreak ? 'time.focus.resume' : 'time.focus.takeBreak',
            )
          : null,
      onAction: signal.mode == TimerMode.pomodoro
          ? () => unawaited(cubit.advancePhase())
          : null,
    );
    _sound(context);
  }

  /// The two halves that are not the toast.
  void _sound(BuildContext context) {
    if (context.read<TimePreferencesCubit>().state.sound) {
      unawaited(_chimeOnce());
    }
    _flashTitle(context);
  }

  /// What the person is told. It names the interval that *ended*, and for a
  /// pomodoro it says which one — "your fourth interval" is the sentence
  /// somebody keeping a rhythm actually wants.
  String _message(BuildContext context, TimerSignal signal) {
    if (signal.mode == TimerMode.countdown) {
      return context.t('time.signal.countdown');
    }
    if (signal.endedABreak) return context.t('time.signal.breakOver');
    return context.t('time.signal.workOver', count: signal.cyclesDone);
  }

  /// Plays the chime, and never lets a failure reach anybody.
  ///
  /// A single player, kept: creating one per interval leaks a platform decoder
  /// on every phase change, and on Linux the GStreamer pipeline behind it is not
  /// free to build. Sound is the one of the three signals that can simply be
  /// unavailable — no output device, a browser that has not been interacted
  /// with yet, a platform with no audio at all — and that must not turn "your
  /// break is over" into a crash.
  Future<void> _chimeOnce() async {
    if (_chimeFailures >= 2) return;
    try {
      final player = _player ??= AudioPlayer();
      if (player.audioSource == null) await player.setAsset(_chime);
      await player.seek(Duration.zero);
      unawaited(player.play());
    } catch (_) {
      // Silence is an acceptable outcome; the toast already said it.
      _chimeFailures++;
    }
  }

  /// Marks the window title for a moment.
  ///
  /// For the person who alt-tabbed away: the browser tab and the task switcher
  /// are the only place the app can reach without a notification permission.
  /// It reverts on its own, because a title that stayed would be lying by the
  /// time they came back.
  ///
  /// Deliberately *neutral* — "an interval ended", never which one. A browser
  /// tab is read by whoever is looking at the screen, and during a screen share
  /// "your break is over" tells a room full of colleagues that this person is
  /// on a break. That is the one thing the module is built not to publish
  /// (HIN-60 R7). What ended is in the toast, on their own screen.
  ///
  /// Platform-dependent by nature — the web sets the document title, Android the
  /// task-switcher label, and the desktop embedders ignore it. That is why it is
  /// an *addition* to the toast rather than a replacement for it.
  void _flashTitle(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS) return;
    _titleReset?.cancel();
    _setTitle('${context.t('time.signal.titleFlash')} · ${widget.appTitle}');
    _titleReset = Timer(const Duration(seconds: 20), () => _setTitle(null));
  }

  void _setTitle(String? label) {
    try {
      SystemChrome.setApplicationSwitcherDescription(
        ApplicationSwitcherDescription(
          label: label ?? widget.appTitle,
          primaryColor: 0xFF1B1A33,
        ),
      );
    } catch (_) {
      // A platform that does not implement the channel; nothing is lost.
    }
  }
}
