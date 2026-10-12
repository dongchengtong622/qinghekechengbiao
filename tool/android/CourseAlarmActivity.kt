package com.qinghe.qinghe_timetable

import android.app.Activity
import android.content.Intent
import android.os.*
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.WindowManager
import android.widget.*
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

/** Course details stay readable after the current 60-second ring, until dismissal/class start. */
class CourseAlarmActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private var snoozeButton: Button? = null
    private var statusLabel: TextView? = null
    private val check = object : Runnable {
        override fun run() {
            val event = current()
            if (event == null || event.optBoolean("done") || !event.optBoolean("enabled",true)) { finish(); return }
            snoozeButton?.visibility = if (event.optLong("deadline") > System.currentTimeMillis() && AlarmJournal.canSnooze(event) && event.optLong("ringUntil") > System.currentTimeMillis()) android.view.View.VISIBLE else android.view.View.GONE
            statusLabel?.text = if(event.optLong("ringUntil") > System.currentTimeMillis()) "正在提醒 · 第 ${event.optInt("rings")} 次" else "本次响铃已结束"
            if (event.optLong("ringUntil") <= System.currentTimeMillis()) window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            handler.postDelayed(this,200)
        }
    }
    private fun current(): JSONObject? = AlarmStore(this).read().find { it.getString("key") == intent.getStringExtra("key") }
        ?: intent.getStringExtra("eventSnapshot")?.let { runCatching { JSONObject(it) }.getOrNull() }
    private fun allowDelivery(): Boolean = !intent.getBooleanExtra("automaticDelivery", false) || AlarmPolicy.shouldShowFullScreen(
        getSystemService(android.app.KeyguardManager::class.java).isKeyguardLocked,
        getSystemService(android.os.PowerManager::class.java).isInteractive)
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!allowDelivery()) { finish(); return }
        if (Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(true); setTurnScreenOn(true) }
        else window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        render(); check.run()
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); if (!allowDelivery()) { finish(); return }; render() }
    private fun render() {
        val event = current() ?: run { finish(); return }
        val key = event.getString("key")
        val ink = Color.rgb(27, 66, 53)
        val muted = Color.rgb(104, 129, 119)
        val green = Color.rgb(0, 119, 91)
        val surface = Color.rgb(243, 249, 246)
        window.statusBarColor = surface
        window.navigationBarColor = surface
        window.decorView.systemUiVisibility = android.view.View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or
            (if (Build.VERSION.SDK_INT >= 26) android.view.View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR else 0)
        fun rounded(color: Int, radius: Int, stroke: Int? = null) = GradientDrawable().apply {
            setColor(color); cornerRadius = dp(radius).toFloat()
            if (stroke != null) setStroke(dp(1), stroke)
        }
        val page = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(surface)
            fitsSystemWindows = true
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(28), dp(24), dp(20))
        }
        page.addView(ScrollView(this).apply {
            isFillViewport = true
            isVerticalScrollBarEnabled = false
            addView(content)
        }, LinearLayout.LayoutParams(-1, 0, 1f))
        fun label(parent: LinearLayout, text: String, size: Float, bold: Boolean = false): TextView = TextView(this).apply {
            this.text = text; textSize = size; setTextColor(ink)
            if (bold) setTypeface(null, Typeface.BOLD)
            setPadding(0, dp(5), 0, dp(5))
            parent.addView(this, LinearLayout.LayoutParams(-1, -2))
        }
        val badge = TextView(this).apply {
            text = "课程提醒"; textSize = 13f; setTextColor(green)
            setPadding(dp(12), dp(7), dp(12), dp(7))
            background = rounded(Color.rgb(222, 242, 232), 20)
        }
        content.addView(badge, LinearLayout.LayoutParams(-2, -2).apply { bottomMargin = dp(20) })
        val fallback = SimpleDateFormat("HH:mm", Locale.CHINA).apply {
            timeZone = TimeZone.getTimeZone("Asia/Shanghai")
        }.format(Date(event.getLong("deadline")))
        label(content, event.optString("timeLabel").ifBlank { fallback }, 34f, true)
        label(content, event.optString("courseName").ifBlank { event.optString("title", "课程提醒") }, 24f, true)
        if (event.optString("dateLabel").isNotBlank()) {
            label(content, event.getString("dateLabel"), 14f).setTextColor(muted)
        }
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(14), dp(18), dp(14))
            background = rounded(Color.WHITE, 22, Color.rgb(227, 239, 232))
        }
        content.addView(card, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(24); bottomMargin = dp(14) })
        fun field(title: String, value: String) {
            if (value.isBlank()) return
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.TOP
                setPadding(0, dp(10), 0, dp(10))
            }
            row.addView(TextView(this).apply {
                text = title; textSize = 14f; setTextColor(muted)
                setPadding(0, dp(3), dp(10), 0)
            }, LinearLayout.LayoutParams(dp(54), -2))
            row.addView(TextView(this).apply {
                text = value; textSize = 18f; setTextColor(ink)
            }, LinearLayout.LayoutParams(0, -2, 1f))
            card.addView(row, LinearLayout.LayoutParams(-1, -2))
        }
        field("教室", event.optString("room"))
        field("教师", event.optString("teacher"))
        field("节次", event.optString("sectionLabel"))
        field("周次", event.optString("weekLabel"))
        if (card.childCount == 0) field("信息", event.optString("body"))
        if (card.childCount == 0) card.visibility = android.view.View.GONE
        statusLabel = label(content, "", 13f).apply { setTextColor(muted) }
        val controls = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(8), dp(24), dp(24))
        }
        page.addView(controls, LinearLayout.LayoutParams(-1, -2))
        fun button(text: String, primary: Boolean, action: () -> Unit) = Button(this).apply {
            this.text = text; textSize = 16f; isAllCaps = false
            setTextColor(if (primary) Color.WHITE else green)
            background = rounded(if (primary) green else Color.rgb(225, 243, 234), 18)
            stateListAnimator = null
            setPadding(dp(14), dp(10), dp(14), dp(10))
            minimumHeight = dp(54)
            setOnClickListener { action() }
        }
        snoozeButton = button("稍后提醒 · ${event.getInt("interval")} 分钟", false) {
            AlarmStore(this@CourseAlarmActivity).stop(key, false, notificationId = event.optInt("id")); finish()
        }
        controls.addView(snoozeButton, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(10) })
        controls.addView(button("关闭本节课提醒", true) {
            AlarmStore(this@CourseAlarmActivity).stop(key, true, notificationId = event.optInt("id")); finish()
        }, LinearLayout.LayoutParams(-1, -2))
        label(controls, "关闭后，本节课不再提醒", 12f).apply {
            setTextColor(muted); gravity = Gravity.CENTER; setPadding(0, dp(12), 0, 0)
        }
        setContentView(page)
    }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null);super.onDestroy() }
}
