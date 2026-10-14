package com.ahmadre.hinata

import android.app.NotificationManager
import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import android.graphics.drawable.Icon
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // HIN-103: offers the Quick Settings tile once, from the app in front (the system refuses
    // the request from the background and stops asking after repeated refusals).
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hinata/quick_settings")
        .setMethodCallHandler { call, result ->
          when (call.method) {
            "offerTile" -> offerTile(result)
            else -> result.notImplemented()
          }
        }
    // HIN-104: the system page where the person allows Live Updates for this app again.
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hinata/live_update")
        .setMethodCallHandler { call, result ->
          when (call.method) {
            "promotion" -> result.success(promotion())
            "openPromotionSettings" -> openPromotionSettings(result)
            else -> result.notImplemented()
          }
        }
  }

  /**
   * Whether this Android has Live Updates at all, and whether the person lets this app's
   * notifications be promoted. Read again whenever the app comes back to the front.
   */
  private fun promotion(): Map<String, Boolean> {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.BAKLAVA) {
      return mapOf("supported" to false, "allowed" to false)
    }
    val manager = getSystemService(NotificationManager::class.java)
    return mapOf(
        "supported" to true, "allowed" to (manager?.canPostPromotedNotifications() ?: false))
  }

  private fun openPromotionSettings(result: MethodChannel.Result) {
    val action =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
          Settings.ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS
        } else {
          Settings.ACTION_APP_NOTIFICATION_SETTINGS
        }
    try {
      startActivity(Intent(action).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
      result.success(true)
    } catch (_: Exception) {
      // Some manufacturers leave the page out; the app's notification page is the next best.
      try {
        startActivity(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
        result.success(true)
      } catch (_: Exception) {
        result.success(false)
      }
    }
  }

  private fun offerTile(result: MethodChannel.Result) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
      result.success(false)
      return
    }
    val manager = getSystemService(StatusBarManager::class.java)
    if (manager == null) {
      result.success(false)
      return
    }
    manager.requestAddTileService(
        ComponentName(this, TimerTileService::class.java),
        getString(R.string.timer_widget_name),
        Icon.createWithResource(this, R.drawable.ic_qs_timer),
        mainExecutor) { _ -> }
    result.success(true)
  }
}
