package com.qinghe.qinghe_timetable
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
class CourseAlarmReceiver:BroadcastReceiver(){
    override fun onReceive(context:Context,intent:Intent){
        val store=AlarmStore(context)
        try{
            val key=intent.getStringExtra("key").orEmpty()
            when(intent.action){
                "fire" -> {
                    val e=store.fire(key,intent.getIntExtra("version",-1)) ?: return
                    // Unlocked reminders use the user's audible system channel so OEMs can
                    // show a heads-up. Do not also start app audio (which would ring twice).
                    val fullScreen = AlarmPolicy.shouldShowFullScreen(
                        context.getSystemService(android.app.KeyguardManager::class.java).isKeyguardLocked,
                        context.getSystemService(android.os.PowerManager::class.java).isInteractive)
                    // Only exact, user-requested alarms can rely on the background FGS exception.
                    if(fullScreen && e.optString("mode")=="exact" && AlarmBridge.mayPlayAppAudio(context)) {
                        try{val service=Intent(context,CourseAlarmService::class.java);if(Build.VERSION.SDK_INT>=26)context.startForegroundService(service) else context.startService(service)}
                        catch(error:Exception){store.log("audio_unavailable",e,reason=error.javaClass.simpleName);CourseAlarmService.publishDirect(context,e)}
                    }else CourseAlarmService.publishDirect(context,e)
                }
                "dismiss" -> store.stop(key,true,intent.getIntExtra("version",-1),intent.takeIf{it.hasExtra("notificationId")}?.getIntExtra("notificationId",0))
                "collapse" -> {
                    val event = store.read().find { it.optString("key")==key }
                        ?: intent.getStringExtra("eventSnapshot")?.let { org.json.JSONObject(it) } ?: return
                    if (!event.optBoolean("done") && event.optBoolean("enabled",true) && AlarmJournal.acceptsVersion(event,intent.getIntExtra("version",-1)))
                        CourseAlarmService.publishDirect(context,event,collapsed = true)
                }
                "snooze" -> store.stop(key,false,intent.getIntExtra("version",-1))
                Intent.ACTION_BOOT_COMPLETED,Intent.ACTION_MY_PACKAGE_REPLACED,Intent.ACTION_TIME_CHANGED,Intent.ACTION_TIMEZONE_CHANGED -> store.recover(intent.action.orEmpty())
                else -> {store.schedule();CourseAlarmService.refreshIfRunning()}
            }
        }catch(e:Exception){store.log("receiver_failed",reason=e.javaClass.simpleName)}
    }
}
