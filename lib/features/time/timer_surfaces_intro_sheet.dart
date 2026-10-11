import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../../core/timer_surfaces/surface_platform.dart';
import '../../core/timer_surfaces/timer_surface_prefs.dart';
import '../../core/widgets/hive_widgets.dart';
import '../account/account_widgets.dart' show SettingRow;
import '../sprint/modals/glass_modal.dart';
import 'timer_surface_options.dart';

/// "Timer outside the app": what the device may show, asked once.
///
/// Offered the first time somebody starts a timer that ends by itself, and
/// from the settings at any time. The switches come preset with the
/// suggestion, so one tap is enough, and nothing shows outside the app until
/// that tap. Closing the sheet counts as "Later": the next timer start does
/// not ask again, and the settings keep the way back.
Future<void> showTimerSurfacesIntro(
  BuildContext context, {
  required TimerSurfacePrefsCubit prefs,
  SurfacePlatform? platform,
  TimerSurfacePermissionGate gate = const TimerSurfacePermissionGate(),
}) async {
  await showGlassModal<void>(
    context,
    adaptive: true,
    width: 520,
    builder: (_) => TimerSurfacesIntroBody(
      prefs: prefs,
      platform: platform ?? SurfacePlatform.current,
      gate: gate,
    ),
  );
  // A sign-out while the sheet was open closed this identity's switches.
  if (!prefs.isClosed && !prefs.state.introSeen) prefs.postpone();
}

class TimerSurfacesIntroBody extends StatefulWidget {
  const TimerSurfacesIntroBody({
    super.key,
    required this.prefs,
    required this.platform,
    this.gate = const TimerSurfacePermissionGate(),
  });

  final TimerSurfacePrefsCubit prefs;
  final SurfacePlatform platform;
  final TimerSurfacePermissionGate gate;

  @override
  State<TimerSurfacesIntroBody> createState() => _TimerSurfacesIntroBodyState();
}

class _TimerSurfacesIntroBodyState extends State<TimerSurfacesIntroBody> {
  late final List<TimerSurfaceOption> _options = TimerSurfaceOption.offeredOn(
    widget.platform,
  );

  /// The suggestion, cut to what this platform has.
  late TimerSurfacePrefs _choices = _offered(TimerSurfacePrefs.suggested);

  bool _busy = false;

  TimerSurfacePrefs _offered(TimerSurfacePrefs prefs) {
    var next = const TimerSurfacePrefs();
    for (final option in _options) {
      next = option.write(next, option.read(prefs));
    }
    return next;
  }

  bool get _needsPermission => _options.any(
    (option) =>
        option.needsPermission(widget.platform) && option.read(_choices),
  );

  Future<void> _switchOn() async {
    if (_busy) return;
    setState(() => _busy = true);
    var choices = _choices;
    var refused = false;
    if (_needsPermission) {
      // Asked straight from the tap: a browser only shows its prompt inside
      // the gesture that asked for it.
      final granted = await widget.gate.request(widget.platform);
      if (!granted) {
        refused = true;
        for (final option in _options) {
          if (option.needsPermission(widget.platform)) {
            choices = option.write(choices, false);
          }
        }
      }
    }
    // Signed out while the system asked: the switches belong to a session that
    // is gone.
    if (widget.prefs.isClosed) return;
    widget.prefs.consent(choices);
    if (!mounted) return;
    if (refused) {
      showGlassToast(
        context,
        context.t('time.surface.intro.denied'),
        kind: GlassToastKind.info,
      );
    }
    Navigator.of(context).maybePop();
  }

  void _later() {
    widget.prefs.postpone();
    Navigator.of(context).maybePop();
  }

  List<String> _lines() {
    final caps = capabilitiesForPlatform(widget.platform);
    return [
      if (caps.phaseEndNotification)
        context.t(
          caps.schedulesAhead
              ? 'time.surface.intro.endClosed'
              : 'time.surface.intro.endBackground',
        ),
      if (caps.runningSurface && widget.platform != SurfacePlatform.web)
        context.t(
          caps.lockScreen
              ? 'time.surface.intro.runningLocked'
              : 'time.surface.intro.running',
        ),
      context.t('time.surface.intro.private'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final running = TimerSurfaceOption.running.read(_choices);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.bellRing,
          title: context.t('time.surface.intro.title'),
          subtitle: context.t('time.surface.intro.subtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in _lines())
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: AppType.label,
                        height: 1.45,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                for (final (index, option) in _options.indexed)
                  if (!option.dependsOnRunning || running) ...[
                    if (index > 0)
                      Divider(height: 1, color: AppColors.hairline2),
                    SettingRow(
                      label: context.t(option.labelKey(widget.platform)),
                      description: context.t(option.hintKey(widget.platform)),
                      icon: option.icon,
                      trailing: HiveSwitch(
                        value: option.read(_choices),
                        onChanged: _busy
                            ? null
                            : (on) => setState(
                                () =>
                                    _choices = withOption(_choices, option, on),
                              ),
                      ),
                    ),
                  ],
              ],
            ),
          ),
        ),
        Padding(
          padding:
              const EdgeInsets.fromLTRB(22, 8, 22, 18) +
              EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            children: [
              GhostButton(
                label: context.t('time.surface.intro.later'),
                onPressed: _busy ? null : _later,
              ),
              PrimaryButton(
                icon: LucideIcons.check,
                label: context.t('time.surface.intro.switchOn'),
                onPressed: _busy ? null : () => unawaited(_switchOn()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
