package com.qinghe.qinghe_timetable

import android.app.*
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject

/** Synchronized journal: persist configuration before side effects; only successful registrations are cached. */
class AlarmStore(private val context:Context) {
    companion object { private val journalLock=Any() }
    private val prefs=context.getSharedPreferences("course_alarm_v1",Context.MODE_PRIVATE)
    private val manager=context.getSystemService(AlarmManager::class.java)
    fun read():MutableList<JSONObject> {
        synchronized(journalLock) {
            val values=JSONArray(prefs.getString("events","[]"))
            return (0 until values.length()).map{values.getJSONObject(it)}.toMutableList()
        }
    }
    private fun save(events:List<JSONObject>){check(prefs.edit().putString("events",JSONArray(events).toString()).commit()){"提醒状态保存失败"}}
    private fun saveDiagnostics(newRows:List<JSONObject>) {
        if(newRows.isEmpty())return
        val previous=JSONArray(prefs.getString("diagnosticRows","[]"))
        val combined=(0 until previous.length()).map{previous.getJSONObject(it)}+newRows
        val kept=JSONArray(combined.takeLast(30))
        // Diagnostics are not delivery state. Apply updates memory immediately without blocking UI on fsync.
        prefs.edit().putString("diagnosticRows",kept.toString()).putString("diagnostics",combined.takeLast(30).joinToString("\n"){it.toString()}).apply()
    }
    fun log(outcome:String,e:JSONObject?=null,mode:String="",reason:String="",capabilities:Map<String,Any?>?=null,rows:MutableList<JSONObject>?=null) {
        synchronized(journalLock) {
            val row=JSONObject().put("outcome",outcome).put("actual",System.currentTimeMillis()).put("mode",mode).put("reason",reason)
            if(e!=null) row.put("keyHash",e.optString("key").hashCode()).put("planned",if(outcome in listOf("received","notification_submitted","audio_unavailable","notification_failed")) e.optLong("lastTriggeredAt",e.optLong("at")) else e.optLong("next",e.optLong("at"))).put("version",e.optInt("version",1))
            val status=capabilities?:AlarmBridge.status(context)
            row.put("notifications",status["notificationsAllowed"]).put("channel",status["channelAllowed"]).put("exact",status["exactAlarmsAllowed"])
            if(rows!=null)rows.add(row) else saveDiagnostics(listOf(row))
        }
    }
    fun pending(key:String,action:String="fire",version:Int?=null):PendingIntent {
        synchronized(journalLock) {
            // Explicit fire versions need no journal lookup; actions retain snapshots for retired notifications.
            val event=if(action!="fire" || version==null)read().find{it.optString("key")==key} else null
            return PendingIntent.getBroadcast(context,0,Intent(context,CourseAlarmReceiver::class.java).apply{
                this.action=action;data=Uri.parse("qinghe-alarm://$action/${Uri.encode(key)}");putExtra("key",key)
                event?.let { putExtra("notificationId",it.optInt("id")); if(action=="collapse")putExtra("eventSnapshot",it.toString()) }
                putExtra("version",version?:event?.optInt("version",1)?:1)
            },PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
    }
    // Validate and submit under the same lock as disabling and cancelling.
    fun publishIfCurrent(snapshot:JSONObject,allowRetired:Boolean=false,requireActiveRound:Boolean=true,publish:(JSONObject)->Unit):Boolean {
        synchronized(journalLock) {
            val current=read().find{it.optString("key")==snapshot.optString("key")}
            if(!AlarmJournal.canPublishSnapshot(current,snapshot,allowRetired,requireActiveRound,System.currentTimeMillis(),SystemClock.elapsedRealtime()))return false
            publish(current?:snapshot)
            return true
        }
    }
    fun replace(incoming:List<JSONObject>,force:Boolean=false):Map<String,Any?> {
        synchronized(journalLock) {
            val old=read();val desired=incoming.map{JSONObject(it.toString()).put("audioChannel",AlertChannelRegistry.selected(context).orEmpty())};val merged=AlarmJournal.merge(desired,old,System.currentTimeMillis());save(merged)
            // schedule() owns cancellation of the actually registered (at most 32)
            // alarms. Cancelling every semester entry here reparsed the full journal
            // and made hundreds of binder calls on the UI thread when switching off.
            val notificationManager=context.getSystemService(NotificationManager::class.java)
            val visibleIds=notificationManager.activeNotifications.map{it.id}.toSet()
            val byKey=merged.associateBy{it.optString("key")}
            // A newly submitted card can still be waiting in NotificationManager's
            // posting queue; a triggered round also needs explicit cancellation.
            old.filter{prior->prior.has("id") && (prior.optInt("id") in visibleIds || prior.optInt("rings")>0)}.forEach { prior ->
                val current=byKey[prior.optString("key")]
                if(current==null || !current.optBoolean("enabled",true) || current.optInt("version",1)!=prior.optInt("version",1))
                    notificationManager.cancel(prior.getInt("id"))
            }
            val report=schedule(force)
            CourseAlarmService.refreshIfRunning()
            return report
        }
    }
    fun schedule(force:Boolean=false):Map<String,Any?> {
        synchronized(journalLock) {
            val now=System.currentTimeMillis();val events=read();val capabilities=AlarmBridge.status(context)
            val allowed=capabilities["notificationsAllowed"]==true && capabilities["channelAllowed"]==true
            val exact=capabilities["exactAlarmsAllowed"]==true
            val diagnosticRows=mutableListOf<JSONObject>()
            val mode=if(exact)"exact" else "inexact"
            val cached=JSONObject(prefs.getString("registeredV2","{}")?:"{}")
            // One-time upgrade cancellation of the old list journal.
            val legacy=JSONArray(prefs.getString("registered","[]"));for(i in 0 until legacy.length())manager.cancel(pending(legacy.getString(i),version=1))
            if(prefs.contains("registered"))prefs.edit().remove("registered").commit()
            val ready=if(allowed)events.filter {it.optBoolean("enabled",true) && AlarmPolicy.shouldSchedule(it.optLong("next"),it.getLong("deadline"),it.optInt("rings"),AlarmJournal.limit(it),it.optBoolean("done"),now)}.sortedBy{it.getLong("next")}.take(32) else emptyList()
            val desired=ready.map{it.getString("key")}.toSet()
            cached.keys().asSequence().toList().filter{force || it !in desired}.forEach{manager.cancel(pending(it,version=1));cached.remove(it)}
            val failures=mutableListOf<Map<String,String>>();val ids=mutableListOf<Int>()
            ready.forEach {e->
                val key=e.getString("key");val signature="${e.getLong("next")}|${e.optInt("version",1)}|$mode"
                if(cached.optString(key)==signature){ids.add(e.getInt("id"));return@forEach}
                manager.cancel(pending(key,version=e.optInt("version",1)));cached.remove(key)
                try {
                    val at=maxOf(e.getLong("next"),now+100L);val pi=pending(key,version=e.optInt("version",1))
                    var actualMode=mode
                    try {if(exact)manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,pi) else manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,pi)}
                    catch(_:SecurityException){manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,pi);actualMode="inexact"}
                    cached.put(key,"${e.getLong("next")}|${e.optInt("version",1)}|$actualMode");e.put("mode",actualMode)
                    ids.add(e.getInt("id"));log("registered",e,actualMode,capabilities=capabilities,rows=diagnosticRows)
                } catch(error:Exception){failures.add(mapOf("code" to "register_failed","message" to "注册提醒失败"));log("register_failed",e,mode,error.javaClass.simpleName,capabilities,diagnosticRows)}
            }
            save(events);check(prefs.edit().putString("registeredV2",cached.toString()).commit())
            saveDiagnostics(diagnosticRows)
            val next=ready.firstOrNull{it.getInt("id") in ids}
            return mapOf("ids" to ids,"nextAt" to next?.getLong("next"),"nextId" to next?.getInt("id"),"mode" to mode,"failures" to failures)
        }
    }
    fun fire(key:String,version:Int):JSONObject? {
        synchronized(journalLock) {
            val now=System.currentTimeMillis();val events=read();val e=events.find{it.optString("key")==key}?:return null
            if(!AlarmJournal.acceptsVersion(e,version)){log("skipped",e,reason="stale_config");return null}
            if(!AlarmBridge.canNotify(context)){log("skipped",e,reason="notification_disabled");schedule();return null}
            val planned=e.optLong("next")
            if(!AlarmJournal.startRound(e,now,SystemClock.elapsedRealtime())) {save(events);log("skipped",e,reason=e.optString("skipReason","duplicate_cancelled_or_expired"));schedule();return null}
            e.put("lastTriggeredAt",planned).put("delayed",now-planned>60000L);save(events);log("received",e,e.optString("mode"));schedule();return e
        }
    }
    fun stop(key:String,dismiss:Boolean,version:Int?=null,notificationId:Int?=null) {
        synchronized(journalLock) {
            val events=read();val e=events.find{it.optString("key")==key}?:run {
                if(dismiss && notificationId!=null) context.getSystemService(NotificationManager::class.java).cancel(notificationId)
                return
            }
            if(version!=null && !AlarmJournal.acceptsVersion(e,version))return
            if(!AlarmJournal.stopRound(e,dismiss,System.currentTimeMillis())) {
                if(dismiss) context.getSystemService(NotificationManager::class.java).cancel(e.optInt("id"))
                return
            }
            save(events);context.getSystemService(NotificationManager::class.java).cancel(e.optInt("id"));schedule();CourseAlarmService.refreshIfRunning()
        }
    }
    fun active():List<JSONObject> {
        synchronized(journalLock) {
            val now=System.currentTimeMillis();val elapsed=SystemClock.elapsedRealtime();return read().filter{it.optBoolean("enabled",true) && !it.optBoolean("done") && it.optLong("ringUntil")>now && it.getLong("deadline")>now && elapsed>=it.optLong("ringStarted") && elapsed<it.optLong("realUntil")}
        }
    }
    fun recover(reason:String="recovery") {
        synchronized(journalLock) {
            val events=read();events.forEach{it.put("ringUntil",0L).put("realUntil",0L)};save(events);log("reconcile",reason=reason);schedule(force=true)
        }
    }
    fun addTest(resource:String?,uri:String?,delay:Long,silent:Boolean=false) {
        synchronized(journalLock) {
            val now=System.currentTimeMillis();val at=now+maxOf(delay,1500L)
            val e=JSONObject().put("key","test-$now").put("id",2147483646).put("at",at).put("next",at).put("version",1).put("deadline",at+60000L)
                .put("title","课程提醒测试").put("body","短期定时测试，最长 1 分钟；不代表长期后台效果")
                .put("courseName","测试课程 · 锁屏提醒").put("timeLabel","测试上课时间").put("room","测试教室 A101").put("teacher","测试教师").put("sectionLabel","测试节次")
                .put("resource",resource).put("uri",uri).put("silent",silent).put("snoozeEnabled",false).put("interval",5).put("limit",1).put("rings",0)
            val events=read();events.filter{it.optString("key").startsWith("test-")}.forEach{manager.cancel(pending(it.getString("key")))}
            events.removeAll{it.optString("key").startsWith("test-")};events.add(e);save(events)
            val report=schedule();check((report["failures"] as List<*>).isEmpty()){"定时测试注册失败"}
        }
    }
}
