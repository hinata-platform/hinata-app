import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../models/time_models.dart';
import '../timer_surface_state.dart';

/// What turns the running timer's notification into a Live Update (Android
/// 16 QPR1 and later): the request to promote it and the style it is drawn
/// with. The same notification, the same id; no second icon.
///
/// The chip in the status bar shows the system's own clock
/// (`usesChronometer`), never a text of ours, so work and a break look the
/// same there. On older versions all of this is ignored and the notification
/// stays an ongoing one.
class AndroidLiveUpdate {
  const AndroidLiveUpdate._({required this.promote, this.style});

  /// The ongoing notification as it was before HIN-104.
  static const none = AndroidLiveUpdate._(promote: false);

  /// Whether the notification asks to be promoted.
  final bool promote;

  /// The style, or null for the default one.
  final StyleInformation? style;

  /// One colour for every segment, work and break alike: a lock screen should
  /// not tell a passer-by which of the two is running.
  static const Color segmentColor = Color(0xFFD9A032);

  /// The Live Update for [state]; [none] when the person switched it off.
  ///
  /// A Pomodoro is drawn as its set, one segment per phase, with a point at
  /// every boundary and the track filled up to the running phase. A countdown
  /// or a stopwatch is one metric on Android 17 ([MetricStyleInformation]);
  /// before that the plugin keeps the default style.
  static AndroidLiveUpdate of(TimerSurfaceState state) {
    if (!state.liveUpdate) return none;
    final set = state.pomodoroSet;
    if (state.mode == TimerMode.pomodoro && set != null) {
      return AndroidLiveUpdate._(promote: true, style: _progress(set));
    }
    final label = state.texts.timeLabel;
    final startedAt = state.startedAt;
    final endsAt = state.endsAt;
    if (label.isEmpty || startedAt == null) {
      return const AndroidLiveUpdate._(promote: true);
    }
    return AndroidLiveUpdate._(
      promote: true,
      style: MetricStyleInformation([
        if (endsAt != null)
          NotificationMetric.timer(endsAt, label: label)
        else
          NotificationMetric.stopwatch(startedAt, label: label),
      ], criticalMetricIndex: 0),
    );
  }

  static ProgressStyleInformation _progress(PomodoroSetPosition set) {
    final points = <ProgressStylePoint>[];
    var at = 0;
    for (final (i, minutes) in set.minutes.indexed) {
      at += minutes;
      if (i < set.minutes.length - 1) {
        points.add(ProgressStylePoint(at, id: i, color: segmentColor));
      }
    }
    return ProgressStyleInformation(
      [
        for (final (i, minutes) in set.minutes.indexed)
          ProgressStyleSegment(minutes, id: i, color: segmentColor),
      ],
      points: points,
      progress: set.minutesBefore,
    );
  }
}
