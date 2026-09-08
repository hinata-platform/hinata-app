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
import '../sprint/modals/glass_modal.dart' show GlassToastKind, showGlassToast;

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

  @override
  void dispose() {
    _titleReset?.cancel();
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocListener<TimerCubit, TimerState>(
    listenWhen: (previous, current) => current.signal != null,
    listener: (context, state) => _announce(context, state.signal!),
    child: widget.child,
  );

  void _announce(BuildContext context, TimerSignal signal) {
    final message = _message(context, signal);
    final cubit = context.read<TimerCubit>();
    showGlassToast(
      context,
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
    if (context.read<TimePreferencesCubit>().state.sound) {
      unawaited(_chimeOnce());
    }
    _flashTitle(message);
  }

  /// What the person is told. It names the interval that *ended*, and for a
  /// pomodoro it says which one — "your fourth interval" is the sentence
  /// somebody keeping a rhythm actually wants.
  String _message(BuildContext context, TimerSignal signal) {
    if (signal.mode == TimerMode.countdown) {
      return context.t('time.signal.countdown');
    }
    if (signal.endedABreak) return context.t('time.signal.breakOver');
    return context.t(
      'time.signal.workOver',
      variables: {'count': '${signal.cyclesDone}'},
    );
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
    try {
      final player = _player ??= AudioPlayer();
      if (player.audioSource == null) await player.setAsset(_chime);
      await player.seek(Duration.zero);
      unawaited(player.play());
    } catch (_) {
      // Silence is an acceptable outcome; the toast already said it.
    }
  }

  /// Puts the message in the window title for a moment.
  ///
  /// For the person who alt-tabbed away: the browser tab and the task switcher
  /// are the only place the app can reach without a notification permission.
  /// It reverts on its own, because a title that stayed would be lying by the
  /// time they came back.
  ///
  /// Platform-dependent by nature — the web sets the document title, Android the
  /// task-switcher label, and the desktop embedders ignore it. That is why it is
  /// an *addition* to the toast rather than a replacement for it.
  void _flashTitle(String message) {
    if (defaultTargetPlatform == TargetPlatform.iOS) return;
    _titleReset?.cancel();
    _setTitle(message);
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
