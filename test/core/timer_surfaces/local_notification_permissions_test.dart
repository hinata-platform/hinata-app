import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/timer_surfaces/adapters/local_notifications_surface.dart';
import 'package:hinata/core/timer_surfaces/surface_platform.dart';

void main() {
  test(
    'Windows and Linux have nothing to grant, so switching on works',
    () async {
      expect(
        await LocalNotificationPermissions(SurfacePlatform.windows).request(),
        isTrue,
      );
      expect(
        await LocalNotificationPermissions(SurfacePlatform.linux).request(),
        isTrue,
      );
    },
  );
}
