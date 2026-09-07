import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/timer_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_panel.dart';
import '../sprint/modals/glass_modal.dart' show GlassToastKind, showGlassToast;
import 'placement_picker.dart';

/// How much room the compact bar takes above the floating nav when a timer is
/// running.
///
/// A constant because the shell reserves this space in the page's bottom gutter
/// before the bar has laid itself out, and a measured height would arrive a
/// frame late — as a list whose last row is under the bar for one frame, every
/// time a timer starts.
const double kCompactTimerBarHeight = 64;

/// The timer, wherever it is.
///
/// One widget for both places it appears — docked at the top of the Time page
/// on a wide window, floating above the bottom nav on a phone — because the
/// alternative is two of them and they drift. What differs between the two is
/// the surface underneath, which is the caller's business, not this one's.
///
/// The elapsed time is counted by [TimerCubit] against the device clock from
/// the server's `startedAt`, so it moves once a second whether or not anything
/// is being requested.
class TimerBar extends StatelessWidget {
  const TimerBar({super.key, this.onStopped, this.compact = false});

  /// Fires after a stop has produced an entry, so the list behind can reload.
  final void Function()? onStopped;

  /// The floating form used over the bottom nav: tighter, and it renders its
  /// own glass. On the page it sits inside the page's own card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TimerCubit, TimerState>(
      listenWhen: (previous, current) =>
          current.errorMessage != null &&
          previous.errorMessage != current.errorMessage,
      listener: (context, state) => showGlassToast(
        context,
        // Already a sentence in the reader's language — the server localizes
        // its own messages. t() is idempotent for anything that is not a key.
        context.t(state.errorMessage!),
        kind: GlassToastKind.error,
      ),
      // Not on every tick. The elapsed reading changes once a second and reads
      // itself off the cubit; everything else in the bar — the glass surface,
      // the description, the buttons — changes only when the timer does. The
      // compact shell makes the same distinction one level up.
      buildWhen: (previous, current) =>
          previous.timer != current.timer || previous.isBusy != current.isBusy,
      builder: (context, state) {
        final body = _TimerBarBody(
          state: state,
          compact: compact,
          onStopped: onStopped,
        );
        if (!compact) return body;
        // Nothing running and nothing to say: on a phone the bar would be a
        // permanent strip of chrome offering one button. It appears when there
        // is a timer and gets out of the way when there is not — the page has
        // its own way to start one.
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: state.isRunning
              ? SizedBox(
                  height: kCompactTimerBarHeight,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassFloatingSurface(radius: 22, child: body),
                  ),
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }
}

class _TimerBarBody extends StatelessWidget {
  const _TimerBarBody({
    required this.state,
    required this.compact,
    this.onStopped,
  });

  final TimerState state;
  final bool compact;
  final void Function()? onStopped;

  @override
  Widget build(BuildContext context) {
    final timer = state.timer;
    final running = timer != null;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 8 : 12,
      ),
      child: Row(
        children: [
          _ElapsedReadout(running: running),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _label(context, timer),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: running ? AppColors.ink : AppColors.inkSoft,
                  ),
                ),
                // Where it is filed, and a way to change that without stopping.
                // Wide only: on a phone this bar is one row floating over the
                // navigation, and a second line of secondary text is what
                // squeezed the description into an ellipsis.
                if (running && !compact) _PlacementLine(timer: timer),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (running) ...[
            _RoundAction(
              icon: LucideIcons.trash2,
              tooltip: context.t('time.timer.discard'),
              onTap: state.isBusy
                  ? null
                  : () => context.read<TimerCubit>().discard(),
            ),
            const SizedBox(width: 8),
            _PrimaryAction(
              icon: LucideIcons.square,
              label: context.t('time.timer.stop'),
              // On a phone the label is what the description loses its room to,
              // and a red square is not ambiguous.
              iconOnly: compact,
              busy: state.isBusy,
              color: AppColors.danger,
              onTap: state.isBusy ? null : () => _stop(context),
            ),
          ] else
            _PrimaryAction(
              icon: LucideIcons.play,
              label: context.t('time.timer.start'),
              iconOnly: compact,
              busy: state.isBusy,
              color: AppColors.navy,
              onTap: state.isBusy
                  ? null
                  : () => unawaited(context.read<TimerCubit>().start()),
            ),
        ],
      ),
    );
  }

  /// What the bar calls the timer.
  ///
  /// The person's own description when there is one. When there is not, the
  /// wide bar can afford a sentence and the compact one cannot — "Timer" is the
  /// whole of what a one-line bar over the navigation needs to say.
  String _label(BuildContext context, RunningTimer? timer) {
    if (timer == null) {
      return context.t(compact ? 'time.timer.title' : 'time.timer.idle');
    }
    final description = timer.description?.trim();
    if (description != null && description.isNotEmpty) return description;
    return context.t(compact ? 'time.timer.title' : 'time.timer.noDescription');
  }

  Future<void> _stop(BuildContext context) async {
    final cubit = context.read<TimerCubit>();
    final saved = await cubit.stop();
    if (saved == null || !context.mounted) return;
    onStopped?.call();
    // The overlap advice, said once, where the decision was made. It is not a
    // failure and nothing is undone: two entries may legitimately share time,
    // and the person is the one who knows.
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

/// The project or issue a running timer is filed under, tappable to change it
/// without stopping.
class _PlacementLine extends StatelessWidget {
  const _PlacementLine({required this.timer});

  final RunningTimer timer;

  @override
  Widget build(BuildContext context) {
    final unfiled = timer.projectId == null && timer.issueId == null;
    return _InlineTap(
      onTap: () async {
        final box = context.findRenderObject() as RenderBox?;
        final origin = box?.localToGlobal(Offset.zero);
        final picked = await showTimePlacementPicker(
          context,
          anchorRect: origin == null || box == null ? null : origin & box.size,
          current: TimePlacement(
            projectId: timer.projectId,
            issueId: timer.issueId,
          ),
        );
        if (picked == null || !context.mounted) return;
        await context.read<TimerCubit>().patch(
          projectId: picked.projectId,
          issueId: picked.issueId,
          // "No project" is a choice, not an omission — without this the
          // fallback below would put the timer straight back where it was.
          clearPlacement: picked.isUnfiled,
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            unfiled ? LucideIcons.circleSlash : LucideIcons.folder,
            size: 11,
            color: AppColors.inkFaint,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              unfiled
                  ? context.t('time.placement.none')
                  : context.t('time.placement.assigned'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineTap extends StatelessWidget {
  const _InlineTap({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: child,
      ),
    ),
  );
}

/// The running count, in tabular figures so the digits do not shuffle sideways
/// once a second.
/// The running count.
///
/// It reads the elapsed time off the cubit itself rather than taking it as a
/// parameter, so the once-a-second change rebuilds this box and nothing else.
class _ElapsedReadout extends StatelessWidget {
  const _ElapsedReadout({required this.running});

  final bool running;

  /// `m:ss` under an hour, `h:mm:ss` above it — the way a stopwatch reads.
  ///
  /// A leading `0:` for the first hour is three characters that say nothing,
  /// and on the compact bar those characters come straight out of the room the
  /// description has to say what the timer is for.
  static String format(Duration d) {
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours == 0) return '${d.inMinutes}:$seconds';
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours}:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = context.select<TimerCubit, Duration>(
      (cubit) => cubit.state.elapsed,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        // The app's "this is live" wash: an amber tint that is opaque cream in
        // light and translucent amber over dark. Deliberately not navy — navy is
        // a brand fill for a filled button, constant across themes, and a navy
        // wash on the dark canvas is a dark blot on a dark card.
        color: running
            ? AppColors.accentSoft
            : AppColors.hairline.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Text(
        format(elapsed),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
          // The one number on this page that moves, so it gets the primary ink:
          // near-black on paper, near-white on the dark canvas. Navy was legible
          // in light and almost invisible in dark, which is exactly the failure
          // a colour that does not resolve against the theme produces.
          color: running ? AppColors.ink : AppColors.inkSoft,
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, size: 16, color: AppColors.inkSoft),
        ),
      ),
    ),
  );
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.busy = false,
    this.iconOnly = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool busy;

  /// Drops the label and keeps it as the tooltip and the semantic name, so the
  /// button shrinks without becoming unreadable to a screen reader.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    if (!iconOnly) return _labelled();
    return Tooltip(
      message: label,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Semantics(label: label, child: Icon(icon, size: 16)),
      ),
    );
  }

  Widget _labelled() => FilledButton.icon(
    onPressed: onTap,
    style: FilledButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
    ),
    icon: busy
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Icon(icon, size: 15),
    label: Text(label),
  );
}
