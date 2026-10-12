package com.qinghe.qinghe_timetable

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

class SerialAlarmExecutorTest {
    @Test fun schedulingDoesNotRunOnTheCallingUiThread() {
        val worker=SerialAlarmExecutor()
        try {
            val caller=Thread.currentThread().id
            val actual=AtomicLong(caller)
            val done=CountDownLatch(1)
            worker.execute(Runnable { actual.set(Thread.currentThread().id);done.countDown() })
            assertTrue(done.await(2,TimeUnit.SECONDS))
            assertNotEquals(caller,actual.get())
        } finally { worker.close() }
    }

    @Test fun blockedFirstScheduleDoesNotBlockCallerOrAllowLaterScheduleToOvertake() {
        val worker=SerialAlarmExecutor()
        val started=CountDownLatch(1)
        val release=CountDownLatch(1)
        val second=CountDownLatch(1)
        try {
            worker.execute(Runnable { started.countDown();release.await(2,TimeUnit.SECONDS) })
            assertTrue(started.await(2,TimeUnit.SECONDS))
            worker.execute(Runnable { second.countDown() })
            assertFalse(second.await(30,TimeUnit.MILLISECONDS))
            release.countDown()
            assertTrue(second.await(2,TimeUnit.SECONDS))
        } finally { release.countDown();worker.close() }
    }
}
