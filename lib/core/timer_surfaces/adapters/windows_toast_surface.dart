import '../../notifications/wns_channel.dart';
import '../phase_end_schedule.dart';
import '../surface_platform.dart';
import '../timer_surface.dart';
import '../timer_surface_state.dart';
import 'local_notifications_surface.dart' show TimerNotificationAction;

/// The end of an interval as a scheduled Windows toast, through windows_push.
///
/// Not flutter_local_notifications: the MSIX registers exactly one
/// `ToastActivatorCLSID`, the one windows_push patches in, and a second
/// activator would be a second app as far as Windows is concerned. A tap
/// arrives through the same deep-link path as a push.
class WindowsToastSurface extends TimerSurface {
  WindowsToastSurface({
    WnsChannel channel = const WnsChannel(),
    DateTime Function()? clock,
  }) : _channel = channel,
       _clock = clock ?? DateTime.now;

  final WnsChannel _channel;
  final DateTime Function() _clock;
  final PhaseEndPlanner _planner = PhaseEndPlanner();

  static const String tag = 'timer-end';

  bool _cleaned = false;

  @override
  String get id => 'windows-toast';

  @override
  TimerSurfaceCapabilities get capabilities =>
      capabilitiesForPlatform(SurfacePlatform.windows);

  @override
  Future<void> init(TimerSurfaceHost host) async {}

  Future<void> _cleanOnce() async {
    if (_cleaned) return;
    _cleaned = true;
    await _channel.cancelToast(tag);
  }

  @override
  Future<void> apply(TimerSurfaceState state) async {
    await _cleanOnce();
    switch (_planner.next(state, _clock())) {
      case PhaseEndKeep():
        return;
      case PhaseEndCancel():
        await _channel.cancelToast(tag);
      case PhaseEndPlan(:final at):
        await _channel.scheduleToast(
          tag: tag,
          at: at,
          title: state.texts.appName,
          body: state.endText,
          launch: TimerNotificationAction.route,
          expireMinutes: PhaseEndSchedule.expiry.inMinutes,
        );
    }
  }

  @override
  Future<void> phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) async {
    if (!foreground) return;
    await _channel.cancelToast(tag);
    _planner.reset();
  }

  @override
  Future<void> clear() async {
    _cleaned = true;
    _planner.reset();
    await _channel.cancelToast(tag);
  }

  @override
  Future<void> dispose() async {}
}
