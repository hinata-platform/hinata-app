import 'package:equatable/equatable.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

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
  });

  /// What the introduction card offers, already chosen.
  static const suggested = TimerSurfacePrefs(
    consented: true,
    introSeen: true,
    phaseEndNotification: true,
    runningSurface: true,
  );

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

  /// The description in menus and tooltips of an unlocked session.
  final bool surfaceDetails;

  /// The description on surfaces of a locked screen.
  final bool lockScreenDetails;

  /// The running time in the window or tab title.
  final bool titleClock;

  TimerSurfacePrefs copyWith({
    bool? consented,
    bool? introSeen,
    bool? phaseEndNotification,
    bool? runningSurface,
    bool? surfaceDetails,
    bool? lockScreenDetails,
    bool? titleClock,
  }) => TimerSurfacePrefs(
    consented: consented ?? this.consented,
    introSeen: introSeen ?? this.introSeen,
    phaseEndNotification: phaseEndNotification ?? this.phaseEndNotification,
    runningSurface: runningSurface ?? this.runningSurface,
    surfaceDetails: surfaceDetails ?? this.surfaceDetails,
    lockScreenDetails: lockScreenDetails ?? this.lockScreenDetails,
    titleClock: titleClock ?? this.titleClock,
  );

  Map<String, dynamic> toJson() => {
    'consented': consented,
    'introSeen': introSeen,
    'phaseEndNotification': phaseEndNotification,
    'runningSurface': runningSurface,
    'surfaceDetails': surfaceDetails,
    'lockScreenDetails': lockScreenDetails,
    'titleClock': titleClock,
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
    );
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
