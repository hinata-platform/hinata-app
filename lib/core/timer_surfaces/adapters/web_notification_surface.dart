/// The browser's notification for the end of an interval, and the app badge.
///
/// Split by platform: `package:web` exists only where JavaScript does.
library;

export 'web_notification_surface_stub.dart'
    if (dart.library.js_interop) 'web_notification_surface_web.dart';
