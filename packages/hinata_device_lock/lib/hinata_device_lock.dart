import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether the device is locked right now (Android).
///
/// Elsewhere always false: iOS asks for the unlock itself before it runs an
/// action that requires it, and the desktops have no lock screen actions.
class HinataDeviceLock {
  const HinataDeviceLock();

  static const MethodChannel _channel = MethodChannel('hinata/device_lock');

  Future<bool> isLocked() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('isLocked') ?? true;
    } on MissingPluginException {
      // Unknown means locked: an action that cannot prove the unlock waits.
      return true;
    } on PlatformException {
      return true;
    }
  }
}
