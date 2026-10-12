package com.qinghe.qinghe_timetable

import java.util.concurrent.Executors

/** Process-wide bridge work stays ordered without occupying the Android looper. */
class SerialAlarmExecutor : AutoCloseable {
    private val worker=Executors.newSingleThreadExecutor { task ->
        Thread(task,"qinghe-alarm-scheduler").apply { isDaemon=true }
    }
    fun execute(task:Runnable) { worker.execute(task) }
    override fun close() { worker.shutdownNow() }
}
