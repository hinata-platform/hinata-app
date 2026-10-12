package com.ahmadre.hinata

import android.app.StatusBarManager
import android.content.ComponentName
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
