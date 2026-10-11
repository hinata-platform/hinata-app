import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/timer_surfaces/adapters/local_notifications_surface.dart';
import 'package:hinata/core/timer_surfaces/surface_platform.dart';
import 'package:hinata/core/timer_surfaces/timer_surface.dart';

/// On Android another app can hand the main activity the intent of a
/// notification button. Only a response that carries this installation's
/// secret may act on the timer; anything else opens the focus screen.
void main() {
  late _Host host;
  late LocalNotificationsSurface surface;

  setUp(() async {
    host = _Host();
    surface = LocalNotificationsSurface(
      SurfacePlatform.android,
      actionToken: () async => 'secret-of-this-install',
    );
    await surface.init(host);
  });

  NotificationResponse response(String? actionId, String? payload) =>
      NotificationResponse(
        notificationResponseType: actionId == null
            ? NotificationResponseType.selectedNotification
            : NotificationResponseType.selectedNotificationAction,
        id: 7101,
        actionId: actionId,
        payload: payload,
      );

  test('our own Stop and Take a break act', () {
    surface.respond(
      response(
        TimerNotificationAction.stop,
        '/time/focus#secret-of-this-install',
      ),
    );
    surface.respond(
      response(
        TimerNotificationAction.advance,
        '/time/focus#secret-of-this-install',
      ),
    );

    expect(host.calls, ['end', 'advance']);
  });

  test('a forged or bare action only opens the focus screen', () {
    surface.respond(
      response(TimerNotificationAction.stop, '/time/focus#guess'),
    );
    surface.respond(response(TimerNotificationAction.stop, '/time/focus'));
    surface.respond(response(TimerNotificationAction.advance, null));

    expect(host.calls, ['focus', 'focus', 'focus']);
  });

  test('a plain tap opens the focus screen', () {
    surface.respond(response(null, '/time/focus#secret-of-this-install'));

    expect(host.calls, ['focus']);
  });
}

class _Host implements TimerSurfaceHost {
  final List<String> calls = [];

  @override
  bool get isForeground => true;

  @override
  Future<void> end() async => calls.add('end');

  @override
  Future<void> advancePhase() async => calls.add('advance');

  @override
  void openFocus() => calls.add('focus');

  @override
  void openRoute(String route) => calls.add('route $route');
}
