package com.qinghe.qinghe_timetable

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.*
import android.provider.Settings
import android.widget.RemoteViews
import org.json.JSONObject

class CourseAlarmService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var playing: String? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var vibrator: Vibrator? = null
    private val published = mutableMapOf<String, Int>()
    private val tick = object : Runnable {
        override fun run() { refresh(); if (instance != null) handler.postDelayed(this, 200) }
    }
    override fun onBind(intent: Intent?) = null
    override fun onCreate() { super.onCreate(); instance = this; ensureChannels(this) }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, SERVICE_CHANNEL) else Notification.Builder(this)
        // Separate low-importance foreground ownership from the alerting course card.
        try { startForeground(SERVICE_NOTIFICATION, builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("课程提醒正在响铃").setContentText("每次最长 60 秒，上课时停止")
            .setOngoing(true).setOnlyAlertOnce(true).setPriority(Notification.PRIORITY_LOW).build()) }
        catch(error:Exception) {
            val store=AlarmStore(this)
            store.active().forEach {store.log("audio_unavailable",it,reason=error.javaClass.simpleName);publishDirect(this,it)}
            stopSelf();return START_NOT_STICKY
        }
        MainActivity.stopPreviewForAlarm()
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "qinghe:course-alarm").apply { acquire(65000) }
        handler.removeCallbacks(tick); tick.run()
        return START_NOT_STICKY
    }
    private fun notification(e:JSONObject)=buildNotification(this,e,true)
    private fun refresh() {
        val events = AlarmStore(this).active()
        val manager = getSystemService(NotificationManager::class.java)
        val rounds = events.associateBy { "${it.getString("key")}:${it.optInt("rings")}" }
        // Audio expiry does not dismiss the course card; user actions own dismissal.
        if (events.isEmpty() || !AlarmBridge.canSchedule(this)) {
            stopAudio(); stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); return
        }
        rounds.forEach { (round, event) ->
            if (round !in published) {
                AlarmStore(this).publishIfCurrent(event) { current ->
                    val id = current.getInt("id")
                    try { manager.notify(id, notification(current)); published[round] = id; AlarmStore(this).log("notification_submitted",current,current.optString("mode")) } catch(error:Exception) { AlarmStore(this).log("notification_failed",current,reason=error.javaClass.simpleName) }
                }
            }
        }
        val event = events.first()
        val key = event.getString("key")
        if (!AlarmBridge.mayPlayAppAudio(this)) { stopAudio(); return }
        if (playing == key) return
        stopAudio(); playing = key
        if (!event.optBoolean("silent") && AlarmBridge.mayPlayAppAudio(this)) {
            val resource = event.optString("resource")
            val imported = event.optString("uri")
            val resourceId = if (resource.isNotEmpty()) resources.getIdentifier(resource, "raw", packageName) else 0
            val uri = when {
                imported.isNotEmpty() && imported != "null" -> Uri.parse(imported)
                resourceId != 0 -> Uri.parse("android.resource://$packageName/$resourceId")
                else -> Settings.System.DEFAULT_ALARM_ALERT_URI
            }
            if (!play(uri)) { AlarmStore(this).log("sound_fallback",event,reason="selected_uri_unreadable");play(Settings.System.DEFAULT_ALARM_ALERT_URI) }
        }
        val pattern = AlarmPolicy.vibrationPattern(event.optString("vibration", "standard"))
        @Suppress("DEPRECATION")
        val deviceVibrator = getSystemService(VIBRATOR_SERVICE) as Vibrator
        if (pattern.isNotEmpty() && deviceVibrator.hasVibrator() && AlarmBridge.mayPlayAppAudio(this)) {
            vibrator = deviceVibrator
            val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build()
            if (Build.VERSION.SDK_INT >= 26) deviceVibrator.vibrate(VibrationEffect.createWaveform(pattern,0),attributes)
            else deviceVibrator.vibrate(pattern,0,attributes)
        }
    }
    private fun play(uri: Uri): Boolean = try {
        val ownedPlayer=MediaPlayer()
        player=ownedPlayer
        ownedPlayer.apply {
            setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            setDataSource(this@CourseAlarmService, uri); isLooping = true
            setOnErrorListener { _, _, _ -> player?.release(); player = null; true }
            prepare(); start()
        }; true
    } catch (_: Exception) { player?.release(); player = null; false }
    private fun stopAudio() { player?.runCatching { stop() }; player?.release(); player = null; vibrator?.cancel(); vibrator = null; playing = null }
    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null); stopAudio()
        published.clear() // The course notification outlives the bounded audio service.
        if (wakeLock?.isHeld == true) wakeLock?.release()
        instance = null; super.onDestroy()
    }
    companion object {
        fun publishDirect(context:Context,e:JSONObject,collapsed:Boolean=false) {
            ensureChannels(context)
            if(!AlarmBridge.canNotify(context))return
            AlarmStore(context).publishIfCurrent(e,allowRetired=collapsed,requireActiveRound=!collapsed) { current ->
                try{context.getSystemService(NotificationManager::class.java).notify(current.getInt("id"),buildNotification(context,current,collapsed=collapsed));AlarmStore(context).log("notification_submitted",current,current.optString("mode"),"direct_without_background_audio")}
                catch(error:Exception){AlarmStore(context).log("notification_failed",current,reason=error.javaClass.simpleName)}
            }
        }
        fun publishTest(context:Context) = publishTest(context,JSONObject())
        fun publishTest(context:Context,config:JSONObject) {
            ensureChannels(context)
            val builder=if(Build.VERSION.SDK_INT>=26)Notification.Builder(context,AlertChannelRegistry.deliveryChannel(context,config.put("mode","inexact"))) else Notification.Builder(context)
            val activity=PendingIntent.getActivity(context,2147483647,Intent(context,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm).setContentTitle("青禾课表测试通知")
                .setContentText("通知已提交系统；请检查横幅、声音与锁屏展示").setCategory(Notification.CATEGORY_REMINDER).setVisibility(Notification.VISIBILITY_PRIVATE)
                .setPriority(Notification.PRIORITY_HIGH).setContentIntent(activity).setAutoCancel(true).build()
            if(Build.VERSION.SDK_INT<26){
                builder.setSound(if(config.optBoolean("silent")) null else AlertChannelRegistry.soundUri(context,config))
                builder.setVibrate(AlarmPolicy.vibrationPattern(config.optString("vibration","standard")))
            }
            context.getSystemService(NotificationManager::class.java).notify(2147483647,builder.build())
            AlarmStore(context).log("notification_submitted",reason="immediate_test")
        }
        fun buildNotification(context: Context,e: JSONObject,appAudio:Boolean=false,collapsed:Boolean=false): Notification {
        val key = e.getString("key")
        val activity = PendingIntent.getActivity(context, 0, Intent(context, CourseAlarmActivity::class.java).apply {
            data = Uri.parse("qinghe-alarm://view/${Uri.encode(key)}"); putExtra("key", key); putExtra("eventSnapshot", e.toString())
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, if(appAudio || collapsed) CHANNEL else AlertChannelRegistry.deliveryChannel(context,e)) else Notification.Builder(context)
        val name = e.optString("courseName").ifBlank { e.optString("title", "课程提醒") }
        val summary = listOf(if(e.optBoolean("delayed")) "延迟提醒" else "", e.optString("timeLabel"), e.optString("sectionLabel"), e.optString("room"),e.optString("teacher")).filter { it.isNotBlank() }.joinToString(" · ")
        val detail = listOf(e.optString("dateLabel"), summary, e.optString("teacher").takeIf { it.isNotBlank() }?.let { "教师：$it" }, e.optString("weekLabel"), e.optString("body")).filterNotNull().filter { it.isNotBlank() }.joinToString("\n")
        builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm).setContentTitle(name).setContentText(summary.ifBlank { e.optString("body") })
            .setCategory(Notification.CATEGORY_ALARM).setVisibility(Notification.VISIBILITY_PUBLIC).setOngoing(appAudio)
            .setContentIntent(activity).setPriority(Notification.PRIORITY_MAX).setOnlyAlertOnce(false)

            .setStyle(Notification.BigTextStyle().bigText(detail).setBigContentTitle(name))
        // Alarm full-screen intents make the system heads-up sticky. Use a separate
        // automatic route so an OEM cannot take over an unlocked interactive phone.
        val automaticActivity = PendingIntent.getActivity(context, 0, Intent(context, CourseAlarmActivity::class.java).apply {
            data = Uri.parse("qinghe-alarm://automatic/${Uri.encode(key)}")
            putExtra("key", key); putExtra("eventSnapshot", e.toString()); putExtra("automaticDelivery", true)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        if (!collapsed) builder.setFullScreenIntent(automaticActivity, true)
        if(Build.VERSION.SDK_INT<26) {
            builder.setSound(if(AlarmPolicy.legacyNotificationSound(e.optBoolean("silent"),appAudio))AlertChannelRegistry.soundUri(context,e) else null)
            builder.setVibrate(AlarmPolicy.legacyNotificationVibration(e.optString("vibration","standard"),appAudio))
        }
        // Compact and expanded shade cards both carry course fields; opening the app is optional.
        if (Build.VERSION.SDK_INT >= 24) {
            fun shadeCard(layout: Int): RemoteViews = RemoteViews(context.packageName, layout).apply {
                setTextViewText(R.id.reminder_compact_name, name)
                setTextViewText(R.id.reminder_compact_time, e.optString("timeLabel").ifBlank { e.optString("body") })
                setTextViewText(R.id.reminder_compact_room, "教室：${e.optString("room")}")
                setTextViewText(R.id.reminder_compact_teacher, "教师：${e.optString("teacher")}")
                setViewVisibility(R.id.reminder_compact_room, if(e.optString("room").isBlank()) android.view.View.GONE else android.view.View.VISIBLE)
                setViewVisibility(R.id.reminder_compact_teacher, if(e.optString("teacher").isBlank()) android.view.View.GONE else android.view.View.VISIBLE)
                if (layout == R.layout.course_reminder_expanded) {
                    val extra = listOf(e.optString("dateLabel"), e.optString("sectionLabel"), e.optString("weekLabel")).filter { it.isNotBlank() }.joinToString(" · ")
                    setTextViewText(R.id.reminder_expanded_extra, extra)
                    setViewVisibility(R.id.reminder_expanded_extra, if(extra.isBlank()) android.view.View.GONE else android.view.View.VISIBLE)
                }
            }
            builder.setStyle(Notification.DecoratedCustomViewStyle())
                .setCustomContentView(shadeCard(R.layout.course_reminder_compact))
                .setCustomBigContentView(shadeCard(R.layout.course_reminder_expanded))
            // Android's frame retains expand/accessibility controls and action buttons.
            val card = RemoteViews(context.packageName, R.layout.course_reminder_card).apply {
                setTextViewText(R.id.reminder_card_name, name)
                setTextViewText(R.id.reminder_card_summary, summary.ifBlank { e.optString("body") })
                setOnClickPendingIntent(R.id.reminder_card_dismiss, AlarmStore(context).pending(key,"dismiss"))
                setOnClickPendingIntent(R.id.reminder_card_snooze, AlarmStore(context).pending(key,"snooze"))
                setViewVisibility(R.id.reminder_card_snooze, if(AlarmJournal.canSnooze(e)) android.view.View.VISIBLE else android.view.View.GONE)
            }
            builder.setCustomHeadsUpContentView(card)
        }
        val store = AlarmStore(context)
        if (!collapsed) builder.setDeleteIntent(store.pending(key,"collapse"))
        else {
            // A lateral heads-up swipe may dismiss its underlying notification on OEMs.
            // Restore only a silent shade card, never a new banner or another sound.
            builder.setOnlyAlertOnce(true).setPriority(Notification.PRIORITY_LOW)
            if (Build.VERSION.SDK_INT >= 26) builder.setGroup("qinghe_collapsed_courses")
                .setGroupAlertBehavior(Notification.GROUP_ALERT_SUMMARY)
            else { builder.setSound(null); builder.setVibrate(null) }
        }
        if (AlarmJournal.canSnooze(e)) builder.addAction(Notification.Action.Builder(null, "稍后（${e.getInt("interval")}分钟）", store.pending(key,"snooze")).build())
        builder.addAction(Notification.Action.Builder(null, "关闭本节课", store.pending(key,"dismiss")).build())
        // No notification timeout: swiping the heads-up only collapses it; Close cancels it.
        return builder.build()
    }
        const val CHANNEL = "qinghe_course_card_v9"
        const val SERVICE_CHANNEL = "qinghe_course_audio_v9"
        private const val SERVICE_NOTIFICATION = -900
        private var instance: CourseAlarmService? = null
        fun isRinging() = instance != null
        fun refreshIfRunning() {
            if(Looper.myLooper()==Looper.getMainLooper()) instance?.refresh()
            else Handler(Looper.getMainLooper()).post { instance?.refresh() }
        }
        fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < 26) return
            val manager = context.getSystemService(NotificationManager::class.java)
            val old = manager.getNotificationChannel("qinghe_course_alarm_v6")
            // Upgrade once; preserve an explicitly blocked or lowered older channel.
            val importance = old?.importance ?: NotificationManager.IMPORTANCE_HIGH
            if(manager.getNotificationChannel(CHANNEL)==null) {
                context.getSharedPreferences("course_alarm_v1",Context.MODE_PRIVATE).edit().putBoolean("cardFactorySilent",old==null).putBoolean("migratedUserMute",Build.VERSION.SDK_INT>=30 && old!=null && old.hasUserSetSound() && old.sound==null).commit()
                manager.createNotificationChannel(NotificationChannel(CHANNEL,"课程提醒顶部卡片",importance).apply {
                description = "课前课程卡片；请按需开启横幅和锁屏显示"
                setSound(if(old!=null) old.sound else null,AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build()); enableVibration(old?.shouldVibrate()?:false); lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            })
            }
            if(manager.getNotificationChannel(SERVICE_CHANNEL)==null)manager.createNotificationChannel(NotificationChannel(SERVICE_CHANNEL,"课程响铃运行状态",NotificationManager.IMPORTANCE_LOW).apply { setSound(null,null); enableVibration(false) })
        }
    }
}
