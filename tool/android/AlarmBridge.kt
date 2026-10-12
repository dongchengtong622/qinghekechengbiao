package com.qinghe.qinghe_timetable

import android.app.*
import android.Manifest
import android.content.*
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** Public API capabilities, with unknown OEM presentation settings kept explicit. */
class AlarmBridge(private val activity: MainActivity, messenger: BinaryMessenger) {
    private var reconciled=false
    init {
        MethodChannel(messenger, "com.qinghe.timetable/alarms").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "replaceAll" -> {
                        val arguments=call.arguments as List<*>
                        alarmWorker.execute(Runnable {
                            try {
                                val report=AlarmStore(activity.applicationContext).replace(arguments.map { JSONObject(it as Map<*, *>) },force=!reconciled)
                                reconciled=(report["failures"] as List<*>).isEmpty()
                                activity.runOnUiThread { result.success(report) }
                            } catch(e:Exception) {
                                activity.runOnUiThread { result.error("alarm_failed",e.message?:"提醒设置失败",null) }
                            }
                        })
                    }
                    "legacyMigrationRequired" -> {
                        val prefs=activity.getSharedPreferences("course_alarm_v1",Context.MODE_PRIVATE)
                        result.success(!prefs.getBoolean("legacyRetiredV9",false) && !prefs.contains("events"))
                    }
                    "markLegacyMigrated" -> {check(activity.getSharedPreferences("course_alarm_v1",Context.MODE_PRIVATE).edit().putBoolean("legacyRetiredV9",true).commit());result.success(null)}
                    "configureAlert" -> {result.success(mapOf("soundFallback" to AlertChannelRegistry.choose(activity,JSONObject(call.arguments as Map<*,*>))))}
                    "status" -> result.success(status(activity))
                    "settings" -> {SettingsNavigator.open(activity,call.arguments as String);result.success(null)}
                    "test" -> {
                        check(canNotify(activity)){"请先开启通知和课程提醒渠道"}
                        val delay=call.argument<Number>("delay")!!.toLong()
                        if(delay<=0)CourseAlarmService.publishTest(activity,JSONObject().put("resource",call.argument<String>("resource")).put("uri",call.argument<String>("uri")).put("silent",call.argument<Boolean>("silent")==true))
                        else AlarmStore(activity).addTest(call.argument("resource"),call.argument("uri"),delay,call.argument<Boolean>("silent")==true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch(e:Exception){result.error("alarm_failed",e.message?:"提醒设置失败",null)}
        }
    }
    companion object {
        private val alarmWorker=SerialAlarmExecutor()
        fun status(context:Context):Map<String,Any> {
            CourseAlarmService.ensureChannels(context)
            val manager=context.getSystemService(NotificationManager::class.java)
            val channel=if(Build.VERSION.SDK_INT>=26)manager.getNotificationChannel(CourseAlarmService.CHANNEL) else null
            val selected=if(Build.VERSION.SDK_INT>=26)AlertChannelRegistry.selected(context)?.let{manager.getNotificationChannel(it)} else null
            val audioChanged=AlertChannelRegistry.userChangedSelection(context)
            val notifications=manager.areNotificationsEnabled() && (Build.VERSION.SDK_INT<33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED)
            val prefs=context.getSharedPreferences("course_alarm_v1",Context.MODE_PRIVATE)
            return mapOf(
                "notificationsAllowed" to notifications,
                "channelAllowed" to (Build.VERSION.SDK_INT<26 || channel!=null && channel.importance>NotificationManager.IMPORTANCE_NONE && (selected==null || selected.importance>NotificationManager.IMPORTANCE_NONE)),
                "channelHighImportance" to (Build.VERSION.SDK_INT<26 || channel!=null && channel.importance>=NotificationManager.IMPORTANCE_HIGH && (selected==null || selected.importance>=NotificationManager.IMPORTANCE_HIGH)),
                "channelSilent" to (Build.VERSION.SDK_INT>=26 && (selected?:channel)!=null && (selected?:channel)?.sound==null),
                "cardSilent" to (Build.VERSION.SDK_INT>=26 && channel!=null && channel.sound==null),
                "channelUserSoundSet" to (Build.VERSION.SDK_INT>=30 && channel!=null && channel.hasUserSetSound() || audioChanged || AlertChannelRegistry.migratedMute(context)),
                "channelUserSilenced" to (Build.VERSION.SDK_INT>=30 && channel!=null && channel.hasUserSetSound() && channel.sound==null || audioChanged && selected?.sound==null || AlertChannelRegistry.migratedMute(context)),
                "exactAlarmsAllowed" to (Build.VERSION.SDK_INT<31 || context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()),
                "fullScreenAllowed" to (Build.VERSION.SDK_INT < 34 || manager.canUseFullScreenIntent()),
                "batteryUnrestricted" to context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName),
                "backgroundRestricted" to (Build.VERSION.SDK_INT>=28 && context.getSystemService(ActivityManager::class.java).isBackgroundRestricted),
                "explicitAudioConsent" to AlertChannelRegistry.consent(context),
                "selectedAudioChannel" to AlertChannelRegistry.selected(context).orEmpty(),
                "sdkInt" to Build.VERSION.SDK_INT,
                "device" to "${Build.MANUFACTURER} ${Build.MODEL} / ${Build.VERSION.RELEASE} / ${Build.DISPLAY}",
                "diagnostics" to prefs.getString("diagnostics","").orEmpty()
            )
        }
        fun canNotify(context:Context)=status(context).let{it["notificationsAllowed"]==true && it["channelAllowed"]==true}
        fun canSchedule(context:Context)=canNotify(context)
        fun mayPlayAppAudio(context:Context):Boolean {
            val s=status(context)
            val normal=context.getSystemService(android.media.AudioManager::class.java).ringerMode==android.media.AudioManager.RINGER_MODE_NORMAL
            val dnd=context.getSystemService(NotificationManager::class.java).currentInterruptionFilter==NotificationManager.INTERRUPTION_FILTER_ALL
            return AlarmPolicy.allowsAppAudio(Build.VERSION.SDK_INT,s["notificationsAllowed"]==true,s["channelAllowed"]==true,s["channelHighImportance"]==true,s["cardSilent"]==true,s["channelUserSoundSet"]==true,normal,dnd,AlertChannelRegistry.consent(context)||AlertChannelRegistry.factoryOwned(context))
        }
    }
}
