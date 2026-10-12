package com.ahmadre.hinata.devicelock

import android.app.KeyguardManager
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** `hinata/device_lock`: whether the keyguard is up, in every engine of the app. */
class HinataDeviceLockPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private var channel: MethodChannel? = null
  private var context: Context? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, "hinata/device_lock").also {
      it.setMethodCallHandler(this)
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel?.setMethodCallHandler(null)
    channel = null
    context = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "isLocked" -> {
        val keyguard = context?.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        result.success(keyguard?.isKeyguardLocked ?: true)
      }
      else -> result.notImplemented()
    }
  }
}
