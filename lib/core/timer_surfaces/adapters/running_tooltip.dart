import '../../widgets/hive_widgets.dart' show fmtClockMinutes;
import '../timer_surface_state.dart';

/// The tooltip of a running timer outside the app: the time to the minute and
/// "running", for work and a break alike. With [withApp] the app's name leads,
/// for the tray icon, which has nothing else to say whose it is.
String runningTooltip(
  TimerSurfaceTexts texts,
  Duration shown, {
  bool withApp = true,
}) => [
  if (withApp) texts.appName,
  fmtClockMinutes(shown),
  texts.running,
].join(' · ');
