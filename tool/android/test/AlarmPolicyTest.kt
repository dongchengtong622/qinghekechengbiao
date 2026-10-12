package com.qinghe.qinghe_timetable

import org.junit.Assert.*
import org.junit.Test

class AlarmPolicyTest {
    @Test fun fullScreenOnlyWhenLockedOrDisplayAsleep() {
        assertFalse(AlarmPolicy.shouldShowFullScreen(false, true))
        assertTrue(AlarmPolicy.shouldShowFullScreen(true, true))
        assertTrue(AlarmPolicy.shouldShowFullScreen(true, false))
        assertTrue(AlarmPolicy.shouldShowFullScreen(false, false))
    }

    @Test fun noVibrationProducesNoPatternAndRhythmsAreDistinct() {
        assertArrayEquals(longArrayOf(), AlarmPolicy.vibrationPattern("none"))
        assertArrayEquals(longArrayOf(0,120,120,250,900), AlarmPolicy.vibrationPattern("heartbeat"))
        assertArrayEquals(longArrayOf(0,500,800), AlarmPolicy.vibrationPattern("unknown-legacy"))
        assertFalse(AlarmPolicy.vibrationPattern("gentle").contentEquals(AlarmPolicy.vibrationPattern("urgent")))
    }
    @Test fun countsIncludeFirstRing() {
        assertEquals(300000L, AlarmPolicy.nextAt(0, 900000, 1, 2, 5))
        assertNull(AlarmPolicy.nextAt(0, 900000, 2, 2, 5))
    }
    @Test fun noRingAtOrAfterClassStart() {
        assertNull(AlarmPolicy.nextAt(0, 300000, 1, 10, 5))
        assertNull(AlarmPolicy.nextAt(0, 299999, 1, 10, 5))
        assertEquals(300000L, AlarmPolicy.nextAt(0, 300001, 1, 10, 5))
    }
    @Test fun ringStopsAtTheEarlierDeadline() {
        assertEquals(60000L, AlarmPolicy.stopAt(0, 900000))
        assertEquals(1000L, AlarmPolicy.stopAt(0, 1000))
    }
    @Test fun allIntervalsAndCountsAreFinite() {
        for (interval in listOf(5,10,15,30)) for (limit in listOf(2,3,5,10)) {
            assertEquals(interval * 60000L + 60000L, AlarmPolicy.nextAt(60000, 9000000, limit-1, limit, interval))
            assertNull(AlarmPolicy.nextAt(60000, 9000000, limit, limit, interval))
        }
    }
    @Test fun dueConcurrentAlarmsAreNotDroppedWhenAnotherAlarmFires() {
        assertTrue(AlarmPolicy.shouldSchedule(1000, 900000, 0, 2, false, 1001))
        assertFalse(AlarmPolicy.shouldSchedule(1000, 1001, 0, 2, false, 1001))
        assertFalse(AlarmPolicy.shouldSchedule(1000, 900000, 0, 2, true, 1001))
        assertFalse(AlarmPolicy.shouldSchedule(0, 900000, 2, 2, false, 1001))
    }
    @Test fun userChannelSoundAlwaysOwnsAudioEvenWhenNonNull() {
        assertFalse(AlarmPolicy.allowsAppAudio(36,true,true,true,false,true,true,true))
        assertFalse(AlarmPolicy.allowsAppAudio(36,true,true,true,true,true,true,true))
        assertTrue(AlarmPolicy.allowsAppAudio(36,true,true,true,true,false,true,true))
    }
    @Test fun uncertainLegacyMuteAndDndCannotBeBypassed() {
        assertFalse(AlarmPolicy.allowsAppAudio(28,true,true,true,true,false,true,true))
        assertFalse(AlarmPolicy.allowsAppAudio(36,true,true,true,false,false,true,false))
        assertFalse(AlarmPolicy.allowsAppAudio(36,true,true,true,false,false,false,true))
        assertFalse(AlarmPolicy.allowsAppAudio(36,true,true,false,false,false,true,true))
        assertTrue(AlarmPolicy.allowsAppAudio(24,true,true,true,false,false,true,true))
    }
    @Test fun activeConsentRestoresLegacyNullButNeverOverridesUserSound() {
        assertTrue(AlarmPolicy.allowsAppAudio(28,true,true,true,true,false,true,true,true))
        assertFalse(AlarmPolicy.allowsAppAudio(36,true,true,true,true,true,true,true,true))
        assertFalse(AlarmPolicy.allowsAppAudio(36,true,true,true,false,false,true,true,true))
    }
    @Test fun api24And25SilenceAndVibrationAreIndependentAndNoDoubleSound() {
        assertFalse(AlarmPolicy.legacyNotificationSound(true,false))
        assertTrue(AlarmPolicy.legacyNotificationSound(false,false))
        assertFalse(AlarmPolicy.legacyNotificationSound(false,true))
        assertArrayEquals(longArrayOf(),AlarmPolicy.legacyNotificationVibration("none",false))
        assertArrayEquals(AlarmPolicy.vibrationPattern("gentle"),AlarmPolicy.legacyNotificationVibration("gentle",false))
        assertArrayEquals(longArrayOf(),AlarmPolicy.legacyNotificationVibration("gentle",true))
    }
}
