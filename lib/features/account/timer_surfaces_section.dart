import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/timer_surfaces/surface_platform.dart';
import '../../core/timer_surfaces/timer_surface_clear_signal.dart';
import '../../core/timer_surfaces/timer_surface_prefs.dart';
import '../../core/widgets/hive_widgets.dart' show HiveSwitch;
import '../sprint/modals/glass_modal.dart' show GlassToastKind, showGlassToast;
import '../time/timer_surface_options.dart';
import '../time/timer_surfaces_intro_sheet.dart';
import 'account_widgets.dart';
import 'timer_hotkeys_rows.dart';

/// Settings → Time tracking → "Timer outside the app": the switches of this
/// device.
///
/// Until the person said yes there is one row and a way to set it up; after
/// that one row per switch the platform has, and two ways back: deleting what
/// lies on the device now, and switching everything off.
///
/// Draws nothing where the platform has no surface, or where nobody provided
/// the switches (a section pumped on its own in a test).
class TimerSurfacesSection extends StatelessWidget {
  const TimerSurfacesSection({
    super.key,
    this.stack = false,
    this.platform,
    this.gate = const TimerSurfacePermissionGate(),
  });

  final bool stack;

  /// The platform whose switches are shown; this device's when null.
  final SurfacePlatform? platform;
  final TimerSurfacePermissionGate gate;

  @override
  Widget build(BuildContext context) {
    final platform = this.platform ?? SurfacePlatform.current;
    final prefs = maybeTimerSurfacePrefs(context);
    if (prefs == null || !hasTimerSurfaces(platform)) {
      return const SizedBox.shrink();
    }
    return BlocBuilder<TimerSurfacePrefsCubit, TimerSurfacePrefs>(
      bloc: prefs,
      builder: (context, state) => state.consented
          ? _Switches(
              prefs: prefs,
              state: state,
              platform: platform,
              gate: gate,
              stack: stack,
            )
          : SettingRow(
              label: context.t('account.timerSurfaces.off'),
              description: context.t('account.timerSurfaces.offHint'),
              icon: LucideIcons.bellOff,
              stack: stack,
              trailing: AccountActionButton(
                label: context.t('account.timerSurfaces.setUp'),
                icon: LucideIcons.bellPlus,
                onPressed: () => unawaited(
                  showTimerSurfacesIntro(
                    context,
                    prefs: prefs,
                    platform: platform,
                    gate: gate,
                  ),
                ),
              ),
            ),
    );
  }
}

class _Switches extends StatefulWidget {
  const _Switches({
    required this.prefs,
    required this.state,
    required this.platform,
    required this.gate,
    required this.stack,
  });

  final TimerSurfacePrefsCubit prefs;
  final TimerSurfacePrefs state;
  final SurfacePlatform platform;
  final TimerSurfacePermissionGate gate;
  final bool stack;

  @override
  State<_Switches> createState() => _SwitchesState();
}

class _SwitchesState extends State<_Switches> {
  /// The switch whose permission the system just refused; its note shows
  /// below it until the person tries again.
  TimerSurfaceOption? _refused;

  /// Whether the system allows Live Activities (iOS). Read again when the app
  /// is back in front, because the answer changes on a system page.
  bool _activities = true;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_readActivities()),
    );
    unawaited(_readActivities());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _readActivities() async {
    final enabled = await widget.gate.activitiesEnabled(widget.platform);
    if (mounted && enabled != _activities) {
      setState(() => _activities = enabled);
    }
  }

  Future<void> _toggle(TimerSurfaceOption option, bool on) async {
    if (on && option.needsPermission(widget.platform)) {
      final granted = await widget.gate.request(widget.platform);
      if (!mounted) return;
      if (!granted) {
        setState(() => _refused = option);
        return;
      }
    }
    if (_refused == option) setState(() => _refused = null);
    final current = widget.prefs.state;
    widget.prefs.update(
      option == TimerSurfaceOption.hotkeys && on
          ? withHotkeysOn(current, widget.platform)
          : withOption(current, option, on),
    );
  }

  bool _blocked(TimerSurfaceOption option) =>
      option == TimerSurfaceOption.running && !_activities;

  void _clearCopies() {
    context.read<TimerSurfaceClearSignal>().request();
    showGlassToast(
      context,
      context.t('account.timerSurfaces.cleared'),
      kind: GlassToastKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final platform = widget.platform;
    final running = TimerSurfaceOption.running.read(state);
    final settings = widget.gate.settingsUri(platform);
    final divider = Divider(height: 1, color: AppColors.hairline2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in TimerSurfaceOption.offeredOn(platform))
          if (!option.dependsOnRunning || running) ...[
            SettingRow(
              label: context.t(option.labelKey(platform)),
              description: context.t(option.hintKey(platform)),
              icon: option.icon,
              trailing: HiveSwitch(
                value: option.read(state),
                // Switched off in the system, it can still be switched off
                // here, never on.
                onChanged: _blocked(option) && !option.read(state)
                    ? null
                    : (on) => unawaited(_toggle(option, on)),
              ),
            ),
            if (_blocked(option)) ...[
              AccountNote(
                text: context.t('account.timerSurfaces.activitiesOff'),
                icon: LucideIcons.circleSlash,
                tone: AccountNoteTone.info,
              ),
              if (settings != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AccountActionButton(
                      label: context.t('account.timerSurfaces.openSettings'),
                      icon: LucideIcons.settings,
                      onPressed: () =>
                          unawaited(widget.gate.openSettings(settings)),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
            ],
            if (_refused == option) ...[
              AccountNote(
                text: context.t('account.timerSurfaces.denied'),
                icon: LucideIcons.bellOff,
                tone: AccountNoteTone.info,
              ),
              if (settings != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AccountActionButton(
                      label: context.t('account.timerSurfaces.openSettings'),
                      icon: LucideIcons.settings,
                      onPressed: () =>
                          unawaited(widget.gate.openSettings(settings)),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
            ],
            if (option == TimerSurfaceOption.hotkeys &&
                state.globalHotkeys) ...[
              divider,
              TimerHotkeysRows(
                prefs: widget.prefs,
                platform: platform,
                stack: widget.stack,
              ),
            ],
            if (option == TimerSurfaceOption.phaseEnd &&
                state.phaseEndNotification &&
                capabilitiesForPlatform(platform).exactAlarms) ...[
              divider,
              _ExactRow(
                platform: platform,
                gate: widget.gate,
                stack: widget.stack,
              ),
            ],
            divider,
          ],
        SettingRow(
          label: context.t('account.timerSurfaces.clear'),
          description: context.t('account.timerSurfaces.clearHint'),
          icon: LucideIcons.eraser,
          stack: widget.stack,
          trailing: AccountActionButton(
            label: context.t('account.timerSurfaces.clearButton'),
            icon: LucideIcons.trash2,
            onPressed: _clearCopies,
          ),
        ),
        divider,
        SettingRow(
          label: context.t('account.timerSurfaces.turnOff'),
          description: context.t('account.timerSurfaces.turnOffHint'),
          icon: LucideIcons.power,
          stack: widget.stack,
          trailing: AccountActionButton(
            label: context.t('account.timerSurfaces.turnOffButton'),
            icon: LucideIcons.bellOff,
            onPressed: () =>
                widget.prefs.update(const TimerSurfacePrefs(introSeen: true)),
          ),
        ),
      ],
    );
  }
}

/// Android 12 and later deliver a planned notification within a few minutes
/// unless the person allows exact alarms. The answer comes from a system
/// page, so it is read again when the app is back in front.
class _ExactRow extends StatefulWidget {
  const _ExactRow({
    required this.platform,
    required this.gate,
    required this.stack,
  });

  final SurfacePlatform platform;
  final TimerSurfacePermissionGate gate;
  final bool stack;

  @override
  State<_ExactRow> createState() => _ExactRowState();
}

class _ExactRowState extends State<_ExactRow> {
  late final AppLifecycleListener _lifecycle;

  /// Null until the first answer.
  bool? _exact;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_read()));
    unawaited(_read());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final exact = await widget.gate.canScheduleExact(widget.platform);
    if (mounted && exact != _exact) setState(() => _exact = exact);
  }

  Future<void> _allow() async {
    await widget.gate.requestExact(widget.platform);
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final exact = _exact;
    return SettingRow(
      label: context.t('account.timerSurfaces.exact'),
      description: exact == null
          ? null
          : context.t(
              exact
                  ? 'account.timerSurfaces.exactOn'
                  : 'account.timerSurfaces.exactOff',
            ),
      icon: LucideIcons.clock,
      stack: widget.stack,
      trailing: exact == false
          ? AccountActionButton(
              label: context.t('account.timerSurfaces.exactAllow'),
              icon: LucideIcons.check,
              onPressed: () => unawaited(_allow()),
            )
          : null,
    );
  }
}
