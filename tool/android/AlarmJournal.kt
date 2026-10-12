package com.qinghe.qinghe_timetable

import org.json.JSONObject

/** Pure journal transitions; persisted by AlarmStore before Android side effects. */
object AlarmJournal {
    fun canPublishSnapshot(current:JSONObject?,snapshot:JSONObject,allowRetired:Boolean,requireActiveRound:Boolean,now:Long,elapsed:Long):Boolean {
        val event=current ?: if(allowRetired && !requireActiveRound) snapshot else return false
        if(!event.optBoolean("enabled",true) || event.optBoolean("done") ||
            event.optString("key")!=snapshot.optString("key") ||
            event.optInt("version",1)!=snapshot.optInt("version",1) ||
            event.optInt("rings")!=snapshot.optInt("rings"))return false
        return !requireActiveRound || (event.optLong("ringUntil")>now && event.optLong("deadline")>now &&
            elapsed>=event.optLong("ringStarted") && elapsed<event.optLong("realUntil"))
    }
    private val configurationFields=listOf("at","deadline","title","body","resource","uri","interval","limit","snoozeEnabled","silent","vibration","courseName","teacher","room","dateLabel","timeLabel","sectionLabel","weekLabel","audioChannel")
    fun sameConfiguration(a: JSONObject,b: JSONObject)=configurationFields.all { a.opt(it)?.toString()==b.opt(it)?.toString() }
    fun acceptsVersion(event: JSONObject,version:Int)=event.optInt("version",1)==version

    fun limit(event: JSONObject) = if (event.optBoolean("snoozeEnabled", true)) event.optInt("limit", 2).coerceAtLeast(1) else 1
    fun canSnooze(event: JSONObject) = event.optBoolean("snoozeEnabled", true) && event.optInt("rings") < limit(event)
    fun startRound(event: JSONObject, now: Long, elapsed: Long): Boolean {
        if (!event.optBoolean("enabled", true) || event.optBoolean("done") || now >= event.getLong("deadline") ||
            event.optLong("next") == 0L || now < event.getLong("next") || event.optLong("ringUntil") > now ||
            event.optInt("rings") >= limit(event)) return false
        if (now-event.getLong("next") > 15*60000L) {
            event.put("done",true).put("next",0L).put("skipReason","late_beyond_grace")
            return false
        }
        val until = AlarmPolicy.stopAt(now, event.getLong("deadline"))
        val count = event.optInt("rings") + 1
        event.put("rings", count).put("ringUntil", until).put("lastStop", until)
            .put("ringStarted", elapsed).put("realUntil", elapsed + until - now)
        event.put("next", AlarmPolicy.nextAt(until, event.getLong("deadline"), count, limit(event), event.getInt("interval")) ?: 0L)
        return true
    }
    fun stopRound(event: JSONObject, dismiss: Boolean, now: Long): Boolean {
        if (event.optBoolean("done")) return false
        if (!dismiss && (!canSnooze(event) || event.optLong("ringUntil") <= now)) return false
        event.put("ringUntil", 0L).put("realUntil", 0L).put("lastStop", now)
        val next = if (dismiss) null else AlarmPolicy.nextAt(now, event.getLong("deadline"), event.optInt("rings"), limit(event), event.getInt("interval"))
        event.put("next", next ?: 0L).put("done", dismiss || next == null)
        return true
    }
    fun merge(incoming: List<JSONObject>, previous: List<JSONObject>, now: Long): List<JSONObject> {
        val old = previous.associateBy { it.getString("key") }
        val requested = incoming.filter { it.getLong("deadline") > now }
        require(requested.map { it.getString("key") }.toSet().size == requested.size) { "重复的课程提醒标识" }
        val merged = requested.map { original ->
            val value = JSONObject(original.toString()).put("enabled", true)
            val prior = old[value.getString("key")] ?: previous.firstOrNull {
                value.has("id") && it.has("id") && value.getInt("id") == it.getInt("id") &&
                    !value.getString("key").startsWith("test-") && !it.getString("key").startsWith("test-")
            }
            value.put("version", if(prior==null) 1 else prior.optInt("version",1)+(if(sameConfiguration(value,prior)) 0 else 1))
            if (prior != null) {
                for (field in listOf("rings", "done", "next", "ringUntil", "lastStop", "realUntil", "ringStarted")) {
                    if (prior.has(field)) value.put(field, prior.get(field))
                }
                if (prior.getLong("at") != value.getLong("at") && value.optInt("rings") == 0) value.put("next", maxOf(value.getLong("at"),now))
                if (value.optLong("lastStop") > 0 && !value.optBoolean("done")) {
                    value.put("next", AlarmPolicy.nextAt(value.getLong("lastStop"), value.getLong("deadline"), value.optInt("rings"), limit(value), value.getInt("interval")) ?: 0L)
                }
                if (value.optInt("rings") >= limit(value)) value.put("next", 0L)
                if(!sameConfiguration(value,prior)) value.put("ringUntil",0L).put("realUntil",0L)
            } else {
                value.put("next", maxOf(value.getLong("at"),now)).put("rings", 0).put("done", false)
            }
            value
        }.toMutableList()
        val keys = merged.map { it.getString("key") }.toSet()
        old.values.filter { it.getString("key") !in keys && it.getLong("deadline") > now &&
            !(it.has("id") && merged.any { next -> next.has("id") && next.getInt("id") == it.getInt("id") }) }.forEach {
            val value = JSONObject(it.toString())
            if (!value.getString("key").startsWith("test-")) value.put("enabled", false).put("ringUntil", 0L).put("realUntil", 0L)
            merged.add(value)
        }
        return merged
    }
}
