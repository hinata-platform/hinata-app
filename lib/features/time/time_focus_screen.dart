import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/timer_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/account_models.dart' show TimePreferences;
import '../../core/models/time_models.dart';
import '../../core/repositories/account_repository.dart';
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
  TimePreferences _preferences = const TimePreferences();

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreferences());
  }

  /// The person's own lengths, so the focus screen starts a pomodoro of the
  /// shape they set rather than of the default.
  ///
  /// Read here rather than held app-wide because this is the one screen that
  /// needs them before a timer exists; a failure leaves the defaults, which are
  /// a working rhythm and not a wrong answer.
  Future<void> _loadPreferences() async {
    try {
      final me = await context.read<AccountRepository>().meAccount();
      if (!mounted) return;
      setState(() {
        _preferences = me.timePreferences;
        _mode = _mode;
      });
    } catch (_) {
      // Defaults stand.
    }
  }

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
      shortcuts: [
        AppShortcut(
          id: 'focus.leave',
          key: LogicalKeyboardKey.escape,
          modifier: ShortcutModifier.none,
          labelKey: 'shortcuts.focus.leave',
          groupKey: 'shortcuts.group.time',
          onInvoke: (_) => _leave(),
        ),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(child: AmbientBackground(dark: dark)),
            SafeArea(
              child: BlocBuilder<TimerCubit, TimerState>(
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
                              preferences: _preferences,
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
  const _Body({
    required this.state,
    required this.mode,
    required this.preferences,
    required this.onMode,
  });

  final TimerState state;
  final TimerMode mode;
  final TimePreferences preferences;
  final ValueChanged<TimerMode> onMode;

  @override
  Widget build(BuildContext context) {
    final timer = state.timer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (timer != null) _PhaseLine(timer: timer),
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
        _Actions(state: state, mode: mode, preferences: preferences),
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
    final shown = context.select<TimerCubit, Duration?>((cubit) {
      final state = cubit.state;
      final timer = state.timer;
      if (timer == null) return null;
      // Counting down where there is something to count down to, up where there
      // is not. A countdown that showed how long it had been running would be
      // answering a question nobody asked it.
      final remaining = timer.remaining(DateTime.now());
      return remaining ?? state.elapsed;
    });
    return Text(
      shown == null ? '0:00' : format(shown),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 68,
        height: 1.05,
        fontWeight: FontWeight.w300,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: shown == null ? AppColors.inkSoft : AppColors.ink,
      ),
    );
  }
}

/// Which half of the rhythm is running, and how far through the set.
class _PhaseLine extends StatelessWidget {
  const _PhaseLine({required this.timer});

  final RunningTimer timer;

  @override
  Widget build(BuildContext context) {
    final phase = timer.phase;
    if (phase == null || timer.pomodoro == null) return const SizedBox.shrink();
    final cycles = timer.pomodoro!.cycles;
    // The interval being worked is the one after those already done, and it is
    // counted from one because that is how people count intervals.
    final position = (timer.cyclesDone % cycles) + 1;
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
                  done: index < timer.cyclesDone % cycles,
                  current: !phase.isBreak && index == position - 1,
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
            icon: switch (each) {
              TimerMode.stopwatch => LucideIcons.timer,
              TimerMode.countdown => LucideIcons.hourglass,
              TimerMode.pomodoro => LucideIcons.circleDot,
            },
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
  const _Actions({
    required this.state,
    required this.mode,
    required this.preferences,
  });

  final TimerState state;
  final TimerMode mode;
  final TimePreferences preferences;

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
        // A break is never filed, so ending one is a discard and says so. The
        // server refuses a stop on a break outright; this is what keeps anyone
        // from meeting that refusal.
        _Primary(
          icon: timer.isBreak ? LucideIcons.x : LucideIcons.square,
          label: context.t(
            timer.isBreak ? 'time.focus.endSession' : 'time.timer.stop',
          ),
          busy: state.isBusy,
          color: AppColors.danger,
          onTap: state.isBusy
              ? null
              : () => unawaited(
                  timer.isBreak ? cubit.discard() : _stop(context, cubit),
                ),
        ),
      ],
    );
  }

  Future<void> _start(BuildContext context) => context.read<TimerCubit>().start(
    mode: mode,
    plannedMinutes: preferences.countdownMinutes,
    pomodoro: preferences.pomodoro,
  );

  Future<void> _stop(BuildContext context, TimerCubit cubit) async {
    final saved = await cubit.stop();
    if (saved == null || !context.mounted) return;
    if (saved.hasOverlaps) {
      showGlassToast(
        context,
        context.t(
          'time.overlapWarning',
          variables: {'count': '${saved.overlaps.length}'},
        ),
        kind: GlassToastKind.warning,
      );
    }
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
