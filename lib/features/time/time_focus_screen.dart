import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/time_preferences_cubit.dart';
import '../../core/blocs/timer_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_models.dart';
import '../../core/shortcuts/app_shortcuts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/glass_switch_chip.dart';
import '../sprint/modals/glass_modal.dart'
    show GlassToastKind, anchorRectOfContext, showGlassToast;
import 'placement_picker.dart';

/// The one thing on the screen is the timer.
///
/// A route of its own, outside the shell, on every width — not an "immersive"
/// mode of the shell, which is a compact-only affordance. That is the whole
/// point of the screen: a rail down the left and a search bar across the top
/// are exactly what somebody asking for a focus mode is asking to be rid of.
///
/// Everything here is the person's own doing. The mode is theirs to choose, the
/// lengths are theirs to set, and nothing counts anything they did not start —
/// HIN-60 R2/R7. The screen has no idea whether anyone is at the keyboard and
/// no way to find out.
class TimeFocusScreen extends StatefulWidget {
  const TimeFocusScreen({super.key});

  @override
  State<TimeFocusScreen> createState() => _TimeFocusScreenState();
}

class _TimeFocusScreenState extends State<TimeFocusScreen> {
  /// The mode the next timer starts in. Only meaningful while none runs — a
  /// running timer's mode is the server's and cannot be changed under it.
  TimerMode _mode = TimerMode.stopwatch;

  /// Escape, registered while this screen is mounted and gone with it.
  ///
  /// Built once rather than in `build`: [ScopedShortcuts] compares the list it
  /// was handed with the one before it, and a fresh literal would unregister
  /// and re-register on every rebuild — leaving a window each time in which
  /// Escape does nothing.
  late final List<AppShortcut> _shortcuts = [
    AppShortcut(
      id: 'focus.leave',
      key: LogicalKeyboardKey.escape,
      modifier: ShortcutModifier.none,
      labelKey: 'shortcuts.focus.leave',
      groupKey: 'shortcuts.group.time',
      onInvoke: (_) => _leave(),
    ),
  ];

  void _leave() {
    // Back to wherever this was opened from. A focus screen reached by a deep
    // link has nothing behind it, and the module's own page is the honest
    // destination — not the dashboard, which is not where they were going.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/time');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ScopedShortcuts(
      shortcuts: _shortcuts,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(child: AmbientBackground(dark: dark)),
            SafeArea(
              child: BlocBuilder<TimerCubit, TimerState>(
                // Not on every tick. The readout counts itself off the cubit;
                // everything else here — the phase, the description, the mode,
                // the buttons — changes only when the timer does. Without this
                // the whole body, two filled buttons and every pip rebuilt once
                // a second, on the one screen designed to sit open for
                // twenty-five minutes at a time.
                buildWhen: (previous, current) =>
                    previous.timer != current.timer ||
                    previous.isBusy != current.isBusy,
                builder: (context, state) => Column(
                  children: [
                    _TopBar(onLeave: _leave),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: _Body(
                              state: state,
                              mode: _mode,
                              onMode: (mode) => setState(() => _mode = mode),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onLeave});

  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Row(
      children: [
        Text(
          context.t('time.focus.title'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: AppColors.inkFaint,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: onLeave,
          icon: const Icon(LucideIcons.minimize2, size: 15),
          label: Text(context.t('time.focus.leave')),
          style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft),
        ),
      ],
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.mode, required this.onMode});

  final TimerState state;
  final TimerMode mode;
  final ValueChanged<TimerMode> onMode;

  @override
  Widget build(BuildContext context) {
    final timer = state.timer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (timer != null) _PhaseHeader(timer: timer),
        const SizedBox(height: 10),
        const _Readout(),
        const SizedBox(height: 18),
        _Description(timer: timer),
        const SizedBox(height: 22),
        // The mode is chosen before a timer runs and read afterwards: what a
        // running timer counts by is the server's, and changing it underneath
        // would rewrite an interval already half over.
        if (timer == null)
          _ModeChoice(mode: mode, onMode: onMode)
        else
          _RunningModeLine(timer: timer),
        const SizedBox(height: 22),
        _Actions(state: state, mode: mode),
      ],
    );
  }
}

/// The big number, and the only thing on this screen that moves.
///
/// It reads the cubit itself so the once-a-second change rebuilds this and
/// nothing else — the same split the timer bar makes.
class _Readout extends StatelessWidget {
  const _Readout();

  /// `h:mm:ss` above an hour, `m:ss` below it.
  static String format(Duration d) {
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours == 0) return '${d.inMinutes}:$seconds';
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours}:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    // Down where there is a target, up where there is not — decided by the
    // state, not by the wall clock, so the selector can actually report
    // "unchanged" and the countdown reads whole seconds.
    final shown = context.select<TimerCubit, Duration>(
      (cubit) => cubit.state.shown,
    );
    final running = context.select<TimerCubit, bool>(
      (cubit) => cubit.state.isRunning,
    );
    return Text(
      running ? format(shown) : '0:00',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 68,
        height: 1.05,
        fontWeight: FontWeight.w300,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: running ? AppColors.ink : AppColors.inkSoft,
      ),
    );
  }
}

/// Which half of the rhythm is running, and how far through the set.
///
/// The tall form, for the focus screen: the phase named on its own line with a
/// row of pips under it. The timer bar draws the same fact as one inline row
/// (`_PhaseLine` there) — a shared widget switching between the two layouts
/// would be one widget doing two unrelated things.
class _PhaseHeader extends StatelessWidget {
  const _PhaseHeader({required this.timer});

  final RunningTimer timer;

  @override
  Widget build(BuildContext context) {
    final phase = timer.phase;
    final cycles = timer.pomodoro?.cycles ?? 0;
    // A configuration with no cycles is not one this app writes, but it is one
    // the document could hold — `PomodoroConfig.breakAfter` guards for it, so
    // this must too rather than dividing by zero.
    if (phase == null || cycles <= 0) return const SizedBox.shrink();
    final done = timer.cyclesDone % cycles;
    return Column(
      children: [
        Text(
          context.t(phase.labelKey),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: phase.isBreak ? AppColors.inkSoft : AppColors.accentStrong,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < cycles; index++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _Pip(
                  done: index < done,
                  current: !phase.isBreak && index == done,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Pip extends StatelessWidget {
  const _Pip({required this.done, required this.current});

  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) => Container(
    width: current ? 9 : 7,
    height: current ? 9 : 7,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: done || current
          ? AppColors.accentStrong
          : AppColors.hairline.withValues(alpha: 0.8),
    ),
  );
}

/// What the timer is for, and where it is filed. Both editable without leaving.
class _Description extends StatelessWidget {
  const _Description({required this.timer});

  final RunningTimer? timer;

  @override
  Widget build(BuildContext context) {
    final description = timer?.description?.trim();
    final unfiled =
        timer == null || (timer!.projectId == null && timer!.issueId == null);
    return Column(
      children: [
        _Tappable(
          onTap: timer == null ? null : () => _rename(context),
          child: Text(
            description == null || description.isEmpty
                ? context.t(
                    timer == null
                        ? 'time.focus.idle'
                        : 'time.timer.noDescription',
                  )
                : description,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: description == null || description.isEmpty
                  ? AppColors.inkFaint
                  : AppColors.ink,
            ),
          ),
        ),
        if (timer != null) ...[
          const SizedBox(height: 4),
          _Tappable(
            onTap: () => _refile(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  unfiled ? LucideIcons.circleSlash : LucideIcons.folder,
                  size: 12,
                  color: AppColors.inkFaint,
                ),
                const SizedBox(width: 5),
                Text(
                  context.t(
                    unfiled ? 'time.placement.none' : 'time.placement.assigned',
                  ),
                  style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _rename(BuildContext context) async {
    final cubit = context.read<TimerCubit>();
    final controller = TextEditingController(text: timer?.description ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(context.t('time.entry.description')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 2000,
          decoration: const InputDecoration(counterText: ''),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(context.t('common.save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null) return;
    await cubit.patch(description: saved.trim().isEmpty ? null : saved.trim());
  }

  Future<void> _refile(BuildContext context) async {
    final cubit = context.read<TimerCubit>();
    final picked = await showTimePlacementPicker(
      context,
      anchorRect: anchorRectOfContext(context),
      current: TimePlacement(
        projectId: timer!.projectId,
        issueId: timer!.issueId,
      ),
    );
    if (picked == null) return;
    await cubit.patch(
      projectId: picked.projectId,
      issueId: picked.issueId,
      clearPlacement: picked.isUnfiled,
    );
  }
}

class _Tappable extends StatelessWidget {
  const _Tappable({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: child,
      ),
    ),
  );
}

class _ModeChoice extends StatelessWidget {
  const _ModeChoice({required this.mode, required this.onMode});

  final TimerMode mode;
  final ValueChanged<TimerMode> onMode;

  @override
  Widget build(BuildContext context) => Center(
    child: GlassSwitchBar(
      maxWidth: 380,
      chips: [
        for (final each in TimerMode.values) ...[
          if (each != TimerMode.values.first) const SizedBox(width: 2),
          GlassSwitchChip(
            label: context.t(each.labelKey),
            icon: each.icon,
            active: each == mode,
            onTap: each == mode ? null : () => onMode(each),
          ),
        ],
      ],
    ),
  );
}

/// What a running timer counts by, said rather than offered.
class _RunningModeLine extends StatelessWidget {
  const _RunningModeLine({required this.timer});

  final RunningTimer timer;

  @override
  Widget build(BuildContext context) => Text(
    context.t(timer.mode.labelKey),
    textAlign: TextAlign.center,
    style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
  );
}

class _Actions extends StatelessWidget {
  const _Actions({required this.state, required this.mode});

  final TimerState state;
  final TimerMode mode;

  @override
  Widget build(BuildContext context) {
    final timer = state.timer;
    if (timer == null) {
      return _Primary(
        icon: LucideIcons.play,
        label: context.t('time.timer.start'),
        busy: state.isBusy,
        color: AppColors.navy,
        onTap: state.isBusy ? null : () => _start(context),
      );
    }
    final cubit = context.read<TimerCubit>();
    return Column(
      children: [
        if (timer.mode == TimerMode.pomodoro)
          _Primary(
            icon: LucideIcons.skipForward,
            label: context.t(
              timer.isBreak ? 'time.focus.resume' : 'time.focus.takeBreak',
            ),
            busy: state.isBusy,
            color: AppColors.accentStrong,
            onTap: state.isBusy ? null : () => unawaited(cubit.advancePhase()),
          ),
        if (timer.mode == TimerMode.pomodoro) const SizedBox(height: 10),
        _Primary(
          icon: timer.isBreak ? LucideIcons.x : LucideIcons.square,
          label: context.t(
            timer.isBreak ? 'time.focus.endSession' : 'time.timer.stop',
          ),
          busy: state.isBusy,
          color: AppColors.danger,
          // `end`, not `stop`: a break is never filed, and the server refuses a
          // stop on one outright. The cubit owns that branch so that no screen
          // has to know it.
          onTap: state.isBusy ? null : () => unawaited(_end(context)),
        ),
      ],
    );
  }

  /// Ends the timer and passes on what the server noticed while saving.
  ///
  /// The overlap advice belongs wherever the decision was made. Without this the
  /// focus screen and the timer bar answered the same action differently — which
  /// is the divergence [TimerCubit.end] exists to prevent.
  Future<void> _end(BuildContext context) async {
    final saved = await context.read<TimerCubit>().end();
    if (saved == null || !saved.hasOverlaps || !context.mounted) return;
    showGlassToast(
      context,
      context.t(
        'time.overlapWarning',
        variables: {'count': '${saved.overlaps.length}'},
      ),
      kind: GlassToastKind.warning,
    );
  }

  Future<void> _start(BuildContext context) {
    final preferences = context.read<TimePreferencesCubit>().state;
    return context.read<TimerCubit>().start(
      mode: mode,
      plannedMinutes: preferences.countdownMinutes,
      pomodoro: preferences.pomodoro,
    );
  }
}

class _Primary extends StatelessWidget {
  const _Primary({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onTap,
    style: FilledButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
    ),
    icon: busy
        ? const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Icon(icon, size: 16),
    label: Text(label),
  );
}
