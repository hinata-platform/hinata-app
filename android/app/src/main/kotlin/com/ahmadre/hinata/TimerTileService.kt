package com.ahmadre.hinata

import android.app.KeyguardManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * The running timer as a Quick Settings tile (HIN-103).
 *
 * Not an active tile: the system asks for the state each time the shade opens
 * ([onStartListening]), and the tile reads the one record the widgets read too, nothing else.
 * Running, it shows the stretch and its time as `mm:ss` (API 29+); idle, the app's idle words.
 *
 * A tap acts without opening the app: a Pomodoro turns to its next phase, every other timer
 * stops, through the same background action as the widget buttons. From a locked screen the
 * system asks for the unlock first ([unlockAndRun]). With nothing running a tap opens the focus
 * screen, and so does a long press ([TimerTilePreferencesActivity]).
 */
class TimerTileService : TileService() {

  override fun onStartListening() {
    super.onStartListening()
    val tile = qsTile ?: return
    val record = record()
    val now = System.currentTimeMillis()
    val running = record != null && record.isRunning(now) && record.stop != null
    tile.icon = Icon.createWithResource(this, R.drawable.ic_qs_timer)
    if (running && record != null) {
      tile.state = Tile.STATE_ACTIVE
      tile.label = clip(record.title.ifEmpty { getString(R.string.timer_widget_name) })
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = clock(record, now)
      tile.contentDescription = record.advance ?: record.stop
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
        tile.setActivityLaunchForClick(null)
      }
    } else {
      tile.state = Tile.STATE_INACTIVE
      tile.label = clip(record?.idle ?: getString(R.string.timer_widget_name))
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = null
      tile.contentDescription = tile.label
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
        tile.setActivityLaunchForClick(focus(this))
      }
    }
    tile.updateTile()
  }

  override fun onClick() {
    super.onClick()
    val record = record()
    val now = System.currentTimeMillis()
    if (record == null || !record.isRunning(now) || record.stop == null) {
      openFocus()
      return
    }
    val command = if (record.advance != null) "advancePhase" else "stop"
    val act = Runnable {
      HomeWidgetBackgroundIntent.getBroadcast(
              this, Uri.parse("${TimerWidgetProvider.COMMAND_URI}$command"))
          .send()
    }
    val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
    if (isLocked || keyguard.isKeyguardLocked) unlockAndRun(act) else act.run()
  }

  /** Android 14 refuses `startActivityAndCollapse(Intent)`; the PendingIntent form only. */
  private fun openFocus() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      startActivityAndCollapse(focus(this))
    } else {
      @Suppress("DEPRECATION") startActivityAndCollapse(focusIntent(this))
    }
  }

  private fun record(): TimerWidgetProvider.Record? =
      TimerWidgetProvider.Record.parse(
          HomeWidgetPlugin.getData(this).getString(TimerWidgetProvider.KEY, null))

  /** The time at the moment the shade opened: what is left of a stretch, or what has passed. */
  private fun clock(record: TimerWidgetProvider.Record, now: Long): String {
    val ends = record.endsAt
    val millis = if (ends != null) (ends - now).coerceAtLeast(0) else now - record.startedAt
    val seconds = millis / 1000
    val hours = seconds / 3600
    val minutes = (seconds % 3600) / 60
    val rest = seconds % 60
    return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, rest)
    else "%02d:%02d".format(minutes, rest)
  }

  /** The system cuts longer labels; cut once, at a word the reader sees whole. */
  private fun clip(label: String): String =
      if (label.length <= LABEL_MAX) label else label.take(LABEL_MAX - 1) + "…"

  companion object {
    private const val LABEL_MAX = 18

    fun focusIntent(context: Context): Intent =
        Intent(
                Intent.ACTION_VIEW,
                Uri.parse(TimerWidgetProvider.FOCUS_URI),
                context,
                MainActivity::class.java)
            .apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP }

    fun focus(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            1,
            focusIntent(context),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    /** Asks the system to draw the tile again, after the record changed. */
    fun refresh(context: Context) {
      try {
        requestListeningState(context, ComponentName(context, TimerTileService::class.java))
      } catch (_: Exception) {
        // Not added to the shade, or the system is not ready: nothing to draw.
      }
    }
  }
}

/** A long press on the tile: the focus screen, through the app's own link. */
class TimerTilePreferencesActivity : android.app.Activity() {
  override fun onCreate(savedInstanceState: android.os.Bundle?) {
    super.onCreate(savedInstanceState)
    startActivity(TimerTileService.focusIntent(this))
    finish()
  }
}
