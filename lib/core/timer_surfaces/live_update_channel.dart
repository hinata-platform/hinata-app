import 'package:flutter/services.dart';

/// Whether this device shows Live Updates (Android 16 and later), and whether
/// the person lets Hinata's notifications be promoted to one.
enum LiveUpdateSupport {
  /// An older Android: the running timer stays an ongoing notification.
  unsupported,

  /// Switched off for this app in the system settings.
  blocked,

  /// Promoted when the notification asks for it.
  allowed,
}

/// The Android side of the Live Update (HIN-104), in `MainActivity`.
class LiveUpdateChannel {
  const LiveUpdateChannel();

  static const _channel = MethodChannel('hinata/live_update');

  Future<LiveUpdateSupport> support() async {
    try {
      final answer = await _channel.invokeMapMethod<String, bool>('promotion');
      if (answer?['supported'] != true) return LiveUpdateSupport.unsupported;
      return answer?['allowed'] == true
          ? LiveUpdateSupport.allowed
          : LiveUpdateSupport.blocked;
    } on MissingPluginException {
      return LiveUpdateSupport.unsupported;
    } on PlatformException {
      return LiveUpdateSupport.unsupported;
    }
  }

  /// Opens the system page where Live Updates are allowed for this app.
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<bool>('openPromotionSettings');
    } on MissingPluginException {
      // Nothing to open here; the note says where to look.
    } on PlatformException {
      // Same.
    }
  }
}
