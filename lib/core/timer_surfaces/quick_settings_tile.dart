import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Offers the Quick Settings tile once (Android 13 and later, HIN-103).
///
/// After the first timer someone starts, from the app in front: the system
/// refuses the request from the background and, after a few refusals, stops
/// asking for good. So the app asks exactly once, whatever the answer was.
class QuickSettingsTileOffer {
  const QuickSettingsTileOffer([
    this._channel = const MethodChannel('hinata/quick_settings'),
  ]);

  static const String offeredKey = 'quick_settings_tile_offered';

  final MethodChannel _channel;

  Future<void> offerOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(offeredKey) ?? false) return;
    await prefs.setBool(offeredKey, true);
    try {
      await _channel.invokeMethod<bool>('offerTile');
    } on PlatformException {
      // The system said no before asking; it is not asked again.
    } on MissingPluginException {
      // Not Android.
    }
  }
}
