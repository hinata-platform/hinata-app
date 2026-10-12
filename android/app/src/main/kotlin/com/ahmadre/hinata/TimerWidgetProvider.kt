package com.ahmadre.hinata

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/**
 * The running timer on the home screen (HIN-102).
 *
 * The app writes one record ([KEY]) when the timer changes; nothing else. The time ticks in the
 * launcher by itself (a [android.widget.Chronometer] in the RemoteViews), so there is no periodic
 * update (`updatePeriodMillis = 0`). The two moments the widget changes on its own, the end of the
 * stretch and the expiry of the copy, come from one alarm the provider sets for itself: after
 * `validUntil` the widget shows idle without the app and without the network.
 *
 * Every word comes from the app in the reader's language; the provider has only the gallery's.
 *
 * Since HIN-103 two buttons act on the timer without opening the app: stop, and for a Pomodoro
 * the next phase. They send `hinata://timer/<command>` to home_widget's background receiver,
 * which runs the Dart action (`timerSurfaceBackgroundAction`) in a background engine.
 */
class TimerWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val record = Record.parse(widgetData.getString(KEY, null))
    val now = System.currentTimeMillis()
    val views = render(context, record, now)
    for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    scheduleNext(context, record, now)
  }

  /**
   * The Quick Settings tile reads the same record (HIN-103), and has to be drawn again on every
   * write, also with no widget placed: then the system never calls [onUpdate] for the broadcast
   * home_widget sends, and an open shade would keep showing the stretch that just ended.
   */
  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE) TimerTileService.refresh(context)
  }

  override fun onDisabled(context: Context) {
    super.onDisabled(context)
    alarmManager(context).cancel(selfUpdate(context))
  }

  private fun render(context: Context, record: Record?, now: Long): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.widget_timer)
    views.setOnClickPendingIntent(R.id.widget_root, openFocus(context))
    val running = record != null && record.isRunning(now)
    if (record == null || !running) {
      views.setImageViewResource(R.id.widget_glyph, R.drawable.widget_glyph_timer)
      views.setTextViewText(
          R.id.widget_title, record?.idle ?: context.getString(R.string.timer_widget_name))
      views.setViewVisibility(R.id.widget_clock, View.GONE)
      views.setViewVisibility(R.id.widget_over, View.GONE)
      views.setViewVisibility(R.id.widget_label, View.GONE)
      views.setViewVisibility(R.id.widget_stop, View.GONE)
      views.setViewVisibility(R.id.widget_advance, View.GONE)
      return views
    }
    val ends = record.endsAt
    val over = ends != null && ends <= now
    views.setImageViewResource(
        R.id.widget_glyph,
        when {
          record.isBreak -> R.drawable.widget_glyph_break
          record.countsDown -> R.drawable.widget_glyph_countdown
          else -> R.drawable.widget_glyph_timer
        })
    views.setTextViewText(R.id.widget_title, if (over) record.over ?: record.title else record.title)
    if (over) {
      // A Chronometer counting down goes on below zero; at the end it rests.
      views.setViewVisibility(R.id.widget_clock, View.GONE)
      views.setViewVisibility(R.id.widget_over, View.VISIBLE)
    } else {
      val elapsedNow = SystemClock.elapsedRealtime()
      val base = if (ends != null) elapsedNow + (ends - now) else elapsedNow - (now - record.startedAt)
      views.setChronometer(R.id.widget_clock, base, null, true)
      views.setChronometerCountDown(R.id.widget_clock, ends != null)
      views.setViewVisibility(R.id.widget_clock, View.VISIBLE)
      views.setViewVisibility(R.id.widget_over, View.GONE)
    }
    val label = record.label
    views.setTextViewText(R.id.widget_label, label ?: "")
    views.setViewVisibility(R.id.widget_label, if (label == null) View.GONE else View.VISIBLE)
    renderActions(context, views, record, over)
    return views
  }

  /** The buttons while the stretch runs; over, a tap on the card opens the focus screen. */
  private fun renderActions(context: Context, views: RemoteViews, record: Record, over: Boolean) {
    val stop = record.stop
    if (over || stop == null) {
      views.setViewVisibility(R.id.widget_stop, View.GONE)
      views.setViewVisibility(R.id.widget_advance, View.GONE)
      return
    }
    views.setViewVisibility(R.id.widget_stop, View.VISIBLE)
    views.setContentDescription(R.id.widget_stop, stop)
    views.setOnClickPendingIntent(R.id.widget_stop, command(context, "stop"))
    val advance = record.advance
    if (advance == null) {
      views.setViewVisibility(R.id.widget_advance, View.GONE)
    } else {
      views.setViewVisibility(R.id.widget_advance, View.VISIBLE)
      views.setImageViewResource(
          R.id.widget_advance,
          if (record.isBreak) R.drawable.widget_action_play else R.drawable.widget_action_break)
      views.setContentDescription(R.id.widget_advance, advance)
      views.setOnClickPendingIntent(R.id.widget_advance, command(context, "advancePhase"))
    }
  }

  private fun command(context: Context, command: String): PendingIntent =
      HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("$COMMAND_URI$command"))

  /** The next moment the widget changes by itself: the end, then the expiry. */
  private fun scheduleNext(context: Context, record: Record?, now: Long) {
    val alarms = alarmManager(context)
    val pending = selfUpdate(context)
    alarms.cancel(pending)
    if (record == null || !record.isRunning(now)) return
    val next = listOfNotNull(record.endsAt, record.validUntil).filter { it > now }.minOrNull() ?: return
    // Exact where the person allowed it (the same grant the phase-end notification asks for);
    // otherwise the system may draw the change a few minutes late.
    val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()
    if (exact) {
      alarms.setExactAndAllowWhileIdle(AlarmManager.RTC, next, pending)
    } else {
      alarms.setAndAllowWhileIdle(AlarmManager.RTC, next, pending)
    }
  }

  private fun selfUpdate(context: Context): PendingIntent {
    val manager = AppWidgetManager.getInstance(context)
    val ids = manager.getAppWidgetIds(ComponentName(context, TimerWidgetProvider::class.java))
    val intent =
        Intent(context, TimerWidgetProvider::class.java).apply {
          action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
          putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
    return PendingIntent.getBroadcast(
        context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
  }

  /** A route only: a tap opens the focus screen and never acts on the timer. */
  private fun openFocus(context: Context): PendingIntent {
    val intent =
        Intent(Intent.ACTION_VIEW, Uri.parse(FOCUS_URI), context, MainActivity::class.java).apply {
          flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
    return PendingIntent.getActivity(
        context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
  }

  private fun alarmManager(context: Context) =
      context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

  /** The record of `HomeWidgetSurface` in Dart; no ids. */
  internal data class Record(
      val startedAt: Long,
      val endsAt: Long?,
      val countsDown: Boolean,
      val isBreak: Boolean,
      val validUntil: Long?,
      val label: String?,
      val title: String,
      val over: String?,
      val idle: String?,
      val stop: String? = null,
      val advance: String? = null,
  ) {
    fun isRunning(now: Long) = startedAt > 0 && validUntil != null && validUntil > now

    companion object {
      fun parse(raw: String?): Record? {
        if (raw.isNullOrEmpty()) return null
        return try {
          val json = JSONObject(raw)
          fun long(key: String) = if (json.has(key)) json.getLong(key) else null
          fun text(key: String) = json.optString(key, "").takeIf { it.isNotEmpty() }
          Record(
              startedAt = long("startedAt") ?: 0,
              endsAt = long("endsAt"),
              countsDown = json.optBoolean("countsDown", false),
              isBreak = json.optString("phaseKind") == "break",
              validUntil = long("validUntil"),
              label = text("label"),
              title = text("title") ?: "",
              over = text("over"),
              idle = text("idle"),
              stop = text("stop"),
              advance = text("advance"),
          )
        } catch (_: Exception) {
          null
        }
      }
    }
  }

  companion object {
    const val KEY = "hinata_timer"
    const val FOCUS_URI = "hinata://time/focus"
    /** The background action's link; the command follows (HIN-103). */
    const val COMMAND_URI = "hinata://timer/"
  }
}
