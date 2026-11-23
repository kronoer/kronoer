package app.kronoer

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * The daily Writing reminder: one inexact alarm, which posts the notification and sets the next.
 *
 * Dart schedules it whenever the app opens or its settings change; this keeps what it needs to
 * schedule it again by itself after a restart, a time zone change, or a reminder. It never reads
 * the store: the notification's text is fixed, and the day to skip comes from Dart.
 */
object WritingReminder {
    const val EXTRA_OPENED = "app.kronoer.extra.REMINDER_OPENED"
    const val ACTION_REMIND = "app.kronoer.action.REMIND"

    private const val CHANNEL_ID = "writing_reminder"

    /** In English whatever the app language, as the device settings list it. */
    private const val CHANNEL_NAME = "Writing reminder"
    private const val NOTIFICATION_ID = 1

    private const val KEY_ON = "on"
    private const val KEY_HOUR = "hour"
    private const val KEY_MINUTE = "minute"
    private const val KEY_TEXT = "text"
    private const val KEY_SKIPPED = "skipped"
    private const val KEY_REMINDED = "reminded"

    /**
     * Schedules the reminder at [first], then daily at [hour]:[minute] local time, except on
     * [skipped] (yyyy-MM-dd). Replaces any reminder scheduled before.
     */
    fun schedule(
        context: Context,
        first: Long,
        hour: Int,
        minute: Int,
        skipped: String?,
        text: String,
    ) {
        createChannel(context)
        prefs(context).edit()
            .putBoolean(KEY_ON, true)
            .putInt(KEY_HOUR, hour)
            .putInt(KEY_MINUTE, minute)
            .putString(KEY_SKIPPED, skipped)
            .putString(KEY_TEXT, text)
            .apply()
        val zone = ZoneId.systemDefault()
        val firstDay = Instant.ofEpochMilli(first).atZone(zone).toLocalDate()
        // Once a day: a day already reminded waits for the next.
        if (firstDay == reminded(context)) reschedule(context) else setAlarm(context, first)
    }

    fun cancel(context: Context) {
        prefs(context).edit().putBoolean(KEY_ON, false).apply()
        alarmManager(context).cancel(alarm(context))
    }

    /** Sets the next alarm from what was scheduled last, as after a restart. */
    fun reschedule(context: Context) {
        val prefs = prefs(context)
        if (!prefs.getBoolean(KEY_ON, false)) return
        val next = next(
            now = ZonedDateTime.now(),
            hour = prefs.getInt(KEY_HOUR, 20),
            minute = prefs.getInt(KEY_MINUTE, 0),
            skipped = prefs.getString(KEY_SKIPPED, null)?.let(LocalDate::parse),
            reminded = reminded(context),
        )
        setAlarm(context, next.toInstant().toEpochMilli())
    }

    /** Posts the notification and sets tomorrow's. */
    fun remind(context: Context) {
        val prefs = prefs(context)
        if (!prefs.getBoolean(KEY_ON, false)) return
        prefs.edit().putString(KEY_REMINDED, LocalDate.now().toString()).apply()
        val text = prefs.getString(KEY_TEXT, null)
        if (text != null) post(context, text)
        reschedule(context)
    }

    /**
     * The first [hour]:[minute] after [now] in [now]'s zone, on a day that is neither [skipped] nor
     * [reminded].
     */
    fun next(
        now: ZonedDateTime,
        hour: Int,
        minute: Int,
        skipped: LocalDate?,
        reminded: LocalDate?,
    ): ZonedDateTime {
        var day = now.toLocalDate()
        while (true) {
            // A time that a daylight saving change skips moves past the gap.
            val at = day.atTime(hour, minute).atZone(now.zone)
            if (at.isAfter(now) && day != skipped && day != reminded) return at
            day = day.plusDays(1)
        }
    }

    /** Whether Kronoer may notify, its Writing reminder channel included. */
    fun notificationsAllowed(context: Context): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return false
        val channel = manager.getNotificationChannel(CHANNEL_ID) ?: return true
        return channel.importance != NotificationManager.IMPORTANCE_NONE
    }

    private fun post(context: Context, text: String) {
        createChannel(context)
        // Opens the app as a tap on its icon does; MainActivity then shows the Book tab.
        val open = Intent(context, MainActivity::class.java)
            .putExtra(EXTRA_OPENED, true)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(context.getColor(R.color.ic_launcher_background))
            .setContentTitle("Kronoer")
            .setContentText(text)
            .setCategory(Notification.CATEGORY_REMINDER)
            // Nothing from any Entry or Book: safe in full on the lock screen.
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(
                PendingIntent.getActivity(
                    context,
                    0,
                    open,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, notification)
    }

    private fun createChannel(context: Context) {
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply { setShowBadge(false) }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    /** Inexact: no exact alarm permission, so it may come a few minutes late, more so in Doze. */
    private fun setAlarm(context: Context, at: Long) {
        alarmManager(context).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, alarm(context))
    }

    private fun alarm(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, WritingReminderReceiver::class.java).setAction(ACTION_REMIND),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun reminded(context: Context): LocalDate? =
        prefs(context).getString(KEY_REMINDED, null)?.let(LocalDate::parse)

    private fun alarmManager(context: Context) =
        context.getSystemService(AlarmManager::class.java)

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences("writing_reminder", Context.MODE_PRIVATE)
}

/** The reminder's alarm, and the device events that clear or move alarms. */
class WritingReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            WritingReminder.ACTION_REMIND -> WritingReminder.remind(context)
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            -> WritingReminder.reschedule(context)
        }
    }
}
