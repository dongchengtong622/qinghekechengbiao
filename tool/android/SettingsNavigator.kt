package com.qinghe.qinghe_timetable
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

/** No unverified private component is required. Every entry has public fallbacks. */
object SettingsNavigator {
    fun open(activity:Activity,kind:String) {
        val uri=Uri.parse("package:${activity.packageName}")
        val candidates=mutableListOf<Intent>()
        if(kind in listOf("channel","notifications","soundChannel") && Build.VERSION.SDK_INT>=26) {
            if(kind=="channel" || kind=="soundChannel") candidates.add(Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,activity.packageName).putExtra(Settings.EXTRA_CHANNEL_ID,if(kind=="soundChannel") AlertChannelRegistry.selected(activity)?:CourseAlarmService.CHANNEL else CourseAlarmService.CHANNEL))
            candidates.add(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,activity.packageName))
        }
        if(kind=="fullScreen" && Build.VERSION.SDK_INT>=34)candidates.add(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,uri))
        if(kind=="exact" && Build.VERSION.SDK_INT>=31)candidates.add(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,uri))
        if(kind=="battery")candidates.add(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        candidates.add(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,uri))
        candidates.add(Intent(Settings.ACTION_SETTINGS))
        for(intent in candidates) {
            try {if(intent.resolveActivity(activity.packageManager)!=null){activity.startActivity(intent);return}}
            catch(_:android.content.ActivityNotFoundException){}
            catch(_:SecurityException){}
        }
        throw IllegalStateException("无法打开设置，请到系统设置 → 应用 → 青禾课表手动检查")
    }
}
