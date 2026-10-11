import 'dart:async';

import 'package:flutter/services.dart';

import '../../widgets/hive_widgets.dart' show fmtClock;
import '../surface_platform.dart';
import '../timer_surface.dart';
import '../timer_surface_state.dart';

/// The one writer of the window or tab title.
///
/// It owns the short flash when an interval ends (which used to live in
/// `TimerSignals`) and, where the person asked for it, the running time in the
/// title. Only the time: a title shows in the task switcher, in screen shares
/// and in the browser history, so the description never goes there.
class WindowTitleSurface extends TimerSurface {
  WindowTitleSurface(
    this.platform, {
    required this.appTitle,
    required this.flashText,
    void Function(String label)? write,
  }) : _write = write ?? _systemWrite;

  final SurfacePlatform platform;

  /// The neutral title, read at each write so a renamed organisation shows.
  final String Function() appTitle;

  /// The word the flash shows, in the reader's language.
  final String Function() flashText;

  final void Function(String label) _write;

  static const Duration flashLength = Duration(seconds: 20);

  bool _clock = false;
  Timer? _flash;
  String? _shown;

  @override
  String get id => 'window-title';

  @override
  TimerSurfaceCapabilities get capabilities =>
      capabilitiesForPlatform(platform);

  @override
  Future<void> init(TimerSurfaceHost host) async {}

  @override
  Future<void> apply(TimerSurfaceState state) async {
    _clock = state.running && state.titleClock;
    if (!_clock && _flash == null) _set(appTitle());
  }

  @override
  void tick(Duration shown) {
    if (!_clock || _flash != null) return;
    _set('${fmtClock(shown)} · ${appTitle()}');
  }

  @override
  Future<void> phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) async {
    // iOS has no title anybody sees.
    if (platform == SurfacePlatform.ios) return;
    _flash?.cancel();
    _set('${flashText()} · ${appTitle()}');
    _flash = Timer(flashLength, () {
      _flash = null;
      _set(appTitle());
    });
  }

  @override
  Future<void> clear() async {
    _clock = false;
    _flash?.cancel();
    _flash = null;
    _set(appTitle());
  }

  @override
  Future<void> dispose() async {
    _flash?.cancel();
  }

  void _set(String label) {
    if (label == _shown) return;
    _shown = label;
    _write(label);
  }

  static void _systemWrite(String label) {
    try {
      SystemChrome.setApplicationSwitcherDescription(
        ApplicationSwitcherDescription(label: label, primaryColor: 0xFF1B1A33),
      );
    } catch (_) {
      // A platform without a switcher description: nothing to show.
    }
  }
}
