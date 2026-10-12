package com.qinghe.qinghe_timetable
import android.app.*
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.provider.Settings
import org.json.JSONObject
import java.security.MessageDigest

/** Two roles: silent heads-up card for bounded app audio, user-chosen channel for ordinary delivery. */
object AlertChannelRegistry {
    private const val PREFIX="qinghe_user_audio_"
    private fun prefs(c:Context)=c.getSharedPreferences("course_alarm_v1",Context.MODE_PRIVATE)
    fun consent(c:Context)=prefs(c).getBoolean("explicitAudioConsent",false)
    fun factoryOwned(c:Context)=prefs(c).getBoolean("cardFactorySilent",false)
    fun migratedMute(c:Context):Boolean {
        if(Build.VERSION.SDK_INT<26 || !prefs(c).getBoolean("migratedUserMute",false))return false
        return c.getSystemService(NotificationManager::class.java).getNotificationChannel(CourseAlarmService.CHANNEL)?.sound==null
    }
    fun selected(c:Context):String?=prefs(c).getString("selectedAudioChannel",null)
    private fun edited(c:Context,ch:NotificationChannel,spec:JSONObject):Boolean {
        if(Build.VERSION.SDK_INT>=30 && ch.hasUserSetSound())return true
        val pattern=AlarmPolicy.vibrationPattern(spec.optString("vibration","standard"))
        return ch.importance!=NotificationManager.IMPORTANCE_HIGH || ch.sound?.toString()!=soundUri(c,spec)?.toString() || ch.shouldVibrate()!=pattern.isNotEmpty() || pattern.isNotEmpty() && !(ch.vibrationPattern?:longArrayOf()).contentEquals(pattern)
    }
    fun userChangedSelection(c:Context):Boolean {
        if(Build.VERSION.SDK_INT<26)return false
        val ch=selected(c)?.let{c.getSystemService(NotificationManager::class.java).getNotificationChannel(it)}?:return false
        val spec=prefs(c).getString("audioSpec_${ch.id}",null)?.let{JSONObject(it)}?:return true
        return edited(c,ch,spec)
    }
    fun soundUri(c:Context,e:JSONObject):Uri? {
        if(e.optBoolean("silent"))return null
        val imported=e.optString("uri").takeIf{it.isNotBlank()&&it!="null"}
        if(imported!=null)return Uri.parse(imported)
        val name=e.optString("resource")
        val id=if(name.isNotBlank())c.resources.getIdentifier(name,"raw",c.packageName) else 0
        return if(id!=0)Uri.parse("android.resource://${c.packageName}/$id") else Settings.System.DEFAULT_ALARM_ALERT_URI
    }
    fun choose(c:Context,config:JSONObject):Boolean {
        var fallback=false
        if(!config.optBoolean("silent")) {
            try{soundUri(c,config)?.let{uri->c.contentResolver.openAssetFileDescriptor(uri,"r").use{require(it!=null)}}}
            catch(_:Exception){config.put("resource",JSONObject.NULL).put("uri",JSONObject.NULL).put("name","系统默认");fallback=true;AlarmStore(c).log("sound_fallback",reason="selected_uri_unreadable")}
        }
        if(Build.VERSION.SDK_INT<26){check(prefs(c).edit().putBoolean("explicitAudioConsent",true).commit());return fallback}
        CourseAlarmService.ensureChannels(c)
        val manager=c.getSystemService(NotificationManager::class.java)
        val base=manager.getNotificationChannel(CourseAlarmService.CHANNEL)
        // A new selected channel cannot circumvent a blocked or lowered main course channel.
        check(base!=null && base.importance>=NotificationManager.IMPORTANCE_HIGH){"请先在系统中开启课程提醒渠道和横幅级别"}
        val signature=listOf(config.optBoolean("silent"),config.optString("resource"),config.optString("uri"),config.optString("vibration","standard")).joinToString("|")
        val digest=MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).take(8).joinToString(""){"%02x".format(it)}
        val id=PREFIX+digest
        val previous=selected(c)
        if(previous!=null && previous!=id) {
            val prior=manager.getNotificationChannel(previous)
            val spec=prefs(c).getString("audioSpec_$previous",null)?.let{JSONObject(it)}
            check(prior==null || spec!=null && !edited(c,prior,spec)){"当前提醒声音类别已被系统修改或关闭，请先在通知声音设置中恢复；应用不会通过新类别绕过"}
        }
        if(manager.getNotificationChannel(id)==null) {
            val existing=manager.notificationChannels.filter{it.id.startsWith(PREFIX)}
            val current=selected(c)
            if(existing.size>=6) {
                val removable=existing.filter{it.id!=current && prefs(c).getString("audioSpec_${it.id}",null)?.let{raw->!edited(c,it,JSONObject(raw))}==true}.sortedBy{it.id}
                check(removable.size>=existing.size-5){"已有六组受用户控制的通知类别，请在系统设置中删除不用的类别后重试"}
                removable.take(existing.size-5).forEach{manager.deleteNotificationChannel(it.id);prefs(c).edit().remove("audioSpec_${it.id}").commit()}
            }
            manager.createNotificationChannel(NotificationChannel(id,"课程提醒 · ${config.optString("name","所选铃声")}",NotificationManager.IMPORTANCE_HIGH).apply{
                description="用户主动选择的铃声与振动，用于普通定时通知；系统修改优先"
                setSound(soundUri(c,config),AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build())
                val pattern=AlarmPolicy.vibrationPattern(config.optString("vibration","standard"))
                enableVibration(pattern.isNotEmpty());if(pattern.isNotEmpty())vibrationPattern=pattern
                lockscreenVisibility=Notification.VISIBILITY_PRIVATE
            })
        }
        check(prefs(c).edit().putBoolean("explicitAudioConsent",true).putString("selectedAudioChannel",id).putString("selectedAudioConfig",config.toString()).putString("audioSpec_$id",config.toString()).commit())
        return fallback
    }
    fun deliveryChannel(c:Context,e:JSONObject):String {
        if(Build.VERSION.SDK_INT<26)return CourseAlarmService.CHANNEL
        val manager=c.getSystemService(NotificationManager::class.java)
        val base=manager.getNotificationChannel(CourseAlarmService.CHANNEL)
        // Explicit main-channel sound choices remain authoritative, including mute.
        if(base==null || base.importance<NotificationManager.IMPORTANCE_HIGH || migratedMute(c) || Build.VERSION.SDK_INT>=30 && base.hasUserSetSound())return CourseAlarmService.CHANNEL
        return selected(c)?.takeIf{manager.getNotificationChannel(it)!=null}?:CourseAlarmService.CHANNEL
    }
}
