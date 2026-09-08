import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/timer_cubit.dart';
import '../../core/shortcuts/app_shortcuts.dart';
import 'time_entry_sheet.dart';

/// The time module's keyboard shortcuts, and the widget that owns them.
///
/// Registered app-wide rather than by a screen, because that is what they are
/// for: starting a timer without reaching for the mouse is worth least on the
/// page that already has a start button. They come and go with the module's
/// feature flag, so a server that does not offer it does not list keys that do
/// nothing.
///
/// All three are ⇧ combinations on purpose — see [AppShortcut.allowInTextField].
/// Nothing types them, no editor claims them, and they therefore keep working
/// while somebody is writing a description, which is exactly when "stop the
/// timer" is most likely to be wanted.
final List<AppShortcut> kTimeShortcuts = [
  const AppShortcut(
    id: 'time.toggle',
    key: LogicalKeyboardKey.keyS,
    shift: true,
    allowInTextField: true,
    labelKey: 'shortcuts.time.toggle',
    groupKey: 'shortcuts.group.time',
    onInvoke: toggleTimer,
  ),
  AppShortcut(
    id: 'time.newEntry',
    key: LogicalKeyboardKey.keyE,
    shift: true,
    allowInTextField: true,
    labelKey: 'shortcuts.time.newEntry',
    groupKey: 'shortcuts.group.time',
    onInvoke: (context) => unawaited(showTimeEntrySheet(context)),
  ),
  AppShortcut(
    id: 'time.focus',
    key: LogicalKeyboardKey.keyF,
    shift: true,
    allowInTextField: true,
    labelKey: 'shortcuts.time.focus',
    groupKey: 'shortcuts.group.time',
    onInvoke: (context) => context.go('/time/focus'),
  ),
];

/// Starts a timer, or stops the one that is running.
///
/// Public because the ⌘K palette offers the same thing by name — one behaviour
/// with two ways in, not two implementations of it.
///
/// One key for both, because it is one question — "am I working on this right
/// now" — and because a key that only starts is a key that leaves timers
/// running. A pomodoro break is ended rather than stopped: a break is never
/// filed, and the server refuses a stop on one outright.
void toggleTimer(BuildContext context) {
  final cubit = context.read<TimerCubit>();
  final timer = cubit.state.timer;
  if (timer == null) {
    unawaited(cubit.start());
  } else if (timer.isBreak) {
    unawaited(cubit.discard());
  } else {
    unawaited(cubit.stop());
  }
}

/// Registers [kTimeShortcuts] for as long as the module is switched on.
///
/// Watching the flag rather than reading it once: an administrator can switch
/// the module on while the app is running, and the keys have to start working
/// without a restart — the same rule the navigation already follows.
class TimeShortcuts extends StatelessWidget {
  const TimeShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final enabled = context.select<AppConfigBloc, bool>(
      (bloc) => bloc.state.meta?.advancedTimeTracking ?? false,
    );
    if (!enabled) return child;
    return ScopedShortcuts(shortcuts: kTimeShortcuts, child: child);
  }
}
