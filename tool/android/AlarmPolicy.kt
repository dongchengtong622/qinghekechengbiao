package com.qinghe.qinghe_timetable

object AlarmPolicy {
    fun shouldShowFullScreen(locked: Boolean, interactive: Boolean) = locked || !interactive

    fun allowsAppAudio(api:Int, notifications:Boolean, channel:Boolean, high:Boolean, channelSilent:Boolean, userSoundSet:Boolean, normalRinger:Boolean, dndAllows:Boolean, explicitAudioConsent:Boolean=false):Boolean =
        notifications && channel && high && (api<26 || channelSilent) && !userSoundSet && !(api in 26..29 && channelSilent && !explicitAudioConsent) && normalRinger && dndAllows

    fun legacyNotificationSound(silent:Boolean, appAudio:Boolean)=!silent && !appAudio
    fun legacyNotificationVibration(vibration:String,appAudio:Boolean)=if(appAudio) longArrayOf() else vibrationPattern(vibration)
    fun vibrationPattern(id: String): LongArray = when(id) {
        "none" -> longArrayOf()
        "gentle" -> longArrayOf(0,150,1000)
        "heartbeat" -> longArrayOf(0,120,120,250,900)
        "urgent" -> longArrayOf(0,200,100,200,100,200,600)
        else -> longArrayOf(0,500,800)
    }
    fun nextAt(now: Long, deadline: Long, rings: Int, maxRings: Int, intervalMinutes: Int): Long? {
        if (rings >= maxRings || now >= deadline) return null
        val next = now + intervalMinutes * 60000L
        return next.takeIf { it < deadline }
    }
    fun shouldSchedule(next: Long, deadline: Long, rings: Int, limit: Int, done: Boolean, now: Long): Boolean =
        !done && next > 0 && maxOf(next, now + 100L) < deadline && rings < limit
    fun stopAt(now: Long, deadline: Long): Long = minOf(now + 60000L, deadline)
}
