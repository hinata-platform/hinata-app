import 'package:equatable/equatable.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:system_hotkeys/system_hotkeys.dart';

import 'hotkey_rules.dart';
import 'surface_platform.dart';

/// The person's own switches for the timer outside the app, on this device.
///
/// Device-local and never sent anywhere: whether somebody lets a timer show on
/// their lock screen says nothing the employer needs to know.
class TimerSurfacePrefs extends Equatable {
  const TimerSurfacePrefs({
    this.consented = false,
    this.introSeen = false,
    this.phaseEndNotification = false,
    this.runningSurface = false,
    this.surfaceDetails = false,
    this.lockScreenDetails = false,
    this.titleClock = false,
    this.keepInTray = false,
    this.globalHotkeys = false,
    this.backgroundLiveActivity = false,
    this.toggleHotkey,
    this.focusHotkey,
  });

  /// What the introduction card offers, already chosen.
  static const suggested = TimerSurfacePrefs(
    consented: true,
    introSeen: true,
    phaseEndNotification: true,
    runningSurface: true,
  );

  /// [suggested] for [platform]. A Mac keeps a timer in the menu bar when its
  /// window closes, which is what a Mac app does; on Windows and Linux closing
  /// the window still quits unless the person asks otherwise.
  static TimerSurfacePrefs suggestedOn(SurfacePlatform platform) =>
      suggested.copyWith(keepInTray: platform == SurfacePlatform.macos);

  /// The shortcuts a first switch-on offers: the convention of toggl and
  /// Clockify, ⌃⌥⌘S and ⌃⌥⌘F on a Mac, Ctrl+Alt+Shift+S and F elsewhere.
  static HotKey defaultToggleHotkey(SurfacePlatform platform) => HotKey(
    key: PhysicalKeyboardKey.keyS,
    modifiers: _defaultModifiers(platform),
  );

  static HotKey defaultFocusHotkey(SurfacePlatform platform) => HotKey(
    key: PhysicalKeyboardKey.keyF,
    modifiers: _defaultModifiers(platform),
  );

  static Set<HotKeyModifier> _defaultModifiers(SurfacePlatform platform) =>
      platform == SurfacePlatform.macos
      ? const {HotKeyModifier.control, HotKeyModifier.alt, HotKeyModifier.meta}
      : const {
          HotKeyModifier.control,
          HotKeyModifier.alt,
          HotKeyModifier.shift,
        };

  /// Whether the person confirmed the introduction. Until then nothing shows
  /// outside the app, whatever the switches below say.
  final bool consented;

  /// Whether the introduction was offered, so "Later" is not asked again on
  /// every start.
  final bool introSeen;

  /// A system notification when a countdown or a Pomodoro phase ends.
  final bool phaseEndNotification;

  /// The running timer as an ongoing notification (Android).
  final bool runningSurface;

  /// The description in the running timer's notification of an unlocked session.
  final bool surfaceDetails;

  /// The description on surfaces of a locked screen.
  final bool lockScreenDetails;

  /// The running time in the window or tab title.
  final bool titleClock;

  /// Closing the window leaves a running timer in the menu bar or tray.
  final bool keepInTray;

  /// The master switch of the system-wide shortcuts. Off, nothing is bound,
  /// whatever combinations are stored.
  final bool globalHotkeys;

  /// The Live Activity follows the timer while the app sleeps (iOS, HIN-103):
  /// the server sends each change, sealed, through Hinata Connect, Google and
  /// Apple. Off by default and never part of the suggested set; only with it
  /// on does the device register anything for its activities.
  final bool backgroundLiveActivity;

  /// Start or stop the timer from anywhere; null until one is chosen.
  final HotKey? toggleHotkey;

  /// Open the focus view from anywhere.
  final HotKey? focusHotkey;

  TimerSurfacePrefs copyWith({
    bool? consented,
    bool? introSeen,
    bool? phaseEndNotification,
    bool? runningSurface,
    bool? surfaceDetails,
    bool? lockScreenDetails,
    bool? titleClock,
    bool? keepInTray,
    bool? globalHotkeys,
    bool? backgroundLiveActivity,
    HotKey? toggleHotkey,
    HotKey? focusHotkey,
  }) => TimerSurfacePrefs(
    consented: consented ?? this.consented,
    introSeen: introSeen ?? this.introSeen,
    phaseEndNotification: phaseEndNotification ?? this.phaseEndNotification,
    runningSurface: runningSurface ?? this.runningSurface,
    surfaceDetails: surfaceDetails ?? this.surfaceDetails,
    lockScreenDetails: lockScreenDetails ?? this.lockScreenDetails,
    titleClock: titleClock ?? this.titleClock,
    keepInTray: keepInTray ?? this.keepInTray,
    globalHotkeys: globalHotkeys ?? this.globalHotkeys,
    backgroundLiveActivity:
        backgroundLiveActivity ?? this.backgroundLiveActivity,
    toggleHotkey: toggleHotkey ?? this.toggleHotkey,
    focusHotkey: focusHotkey ?? this.focusHotkey,
  );

  Map<String, dynamic> toJson() => {
    'consented': consented,
    'introSeen': introSeen,
    'phaseEndNotification': phaseEndNotification,
    'runningSurface': runningSurface,
    'surfaceDetails': surfaceDetails,
    'lockScreenDetails': lockScreenDetails,
    'titleClock': titleClock,
    'keepInTray': keepInTray,
    'globalHotkeys': globalHotkeys,
    'backgroundLiveActivity': backgroundLiveActivity,
    'toggleHotkey': toggleHotkey?.toMap(),
    'focusHotkey': focusHotkey?.toMap(),
  };

  /// Anything that is not a `true` reads as off: a broken store must never
  /// switch a surface on.
  factory TimerSurfacePrefs.fromJson(Map<String, dynamic> json) {
    bool on(String key) => json[key] == true;
    return TimerSurfacePrefs(
      consented: on('consented'),
      introSeen: on('introSeen'),
      phaseEndNotification: on('phaseEndNotification'),
      runningSurface: on('runningSurface'),
      surfaceDetails: on('surfaceDetails'),
      lockScreenDetails: on('lockScreenDetails'),
      titleClock: on('titleClock'),
      keepInTray: on('keepInTray'),
      globalHotkeys: on('globalHotkeys'),
      backgroundLiveActivity: on('backgroundLiveActivity'),
      toggleHotkey: _hotKey(json['toggleHotkey']),
      focusHotkey: _hotKey(json['focusHotkey']),
    );
  }

  /// A stored combination, or null for anything that does not read as one.
  static HotKey? _hotKey(Object? raw) {
    if (raw is! Map) return null;
    try {
      final key = HotKey.fromMap(raw);
      return isSafeHotkey(key, SurfacePlatform.current) ? key : null;
    } catch (_) {
      return null;
    }
  }

  @override
  List<Object?> get props => [
    consented,
    introSeen,
    phaseEndNotification,
    runningSurface,
    surfaceDetails,
    lockScreenDetails,
    titleClock,
    keepInTray,
    globalHotkeys,
    backgroundLiveActivity,
    toggleHotkey,
    focusHotkey,
  ];
}

/// The switches of one identity (server plus user) on this device.
///
/// Keyed like the timer itself ([storageId]), so two people on one computer
/// keep their own choices. Not cleared on sign-out: these are the person's
/// settings for this device, not data of the session.
class TimerSurfacePrefsCubit extends HydratedCubit<TimerSurfacePrefs> {
  TimerSurfacePrefsCubit({required this.storageId})
    : super(const TimerSurfacePrefs());

  final String storageId;

  @override
  String get id => storageId;

  /// Confirms the introduction with the person's choices.
  void consent(TimerSurfacePrefs choices) =>
      emit(choices.copyWith(consented: true, introSeen: true));

  /// "Later": nothing on, and not asked again on the next start.
  void postpone() => emit(state.copyWith(introSeen: true));

  void update(TimerSurfacePrefs next) => emit(next);

  @override
  TimerSurfacePrefs fromJson(Map<String, dynamic> json) {
    try {
      return TimerSurfacePrefs.fromJson(json);
    } catch (_) {
      return const TimerSurfacePrefs();
    }
  }

  @override
  Map<String, dynamic> toJson(TimerSurfacePrefs state) => state.toJson();
}
