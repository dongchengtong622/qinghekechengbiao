package com.qinghe.qinghe_timetable
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
class AlarmJournalTest {
    private fun event(at:Long=1000)=JSONObject().put("key","course-one").put("at",at).put("deadline",900000L).put("limit",2).put("interval",5)
    @Test fun dismissSurvivesDisableAndChangedLeadTime() {
        val first=event().put("rings",1).put("done",true).put("next",0L)
        val disabled=AlarmJournal.merge(emptyList(),listOf(first),2000)
        assertFalse(disabled.single().getBoolean("enabled"))
        val enabled=AlarmJournal.merge(listOf(event(5000)),disabled,3000).single()
        assertTrue(enabled.getBoolean("done"))
        assertEquals(1,enabled.getInt("rings"))
        assertFalse(AlarmPolicy.shouldSchedule(enabled.getLong("next"),enabled.getLong("deadline"),enabled.getInt("rings"),2,enabled.getBoolean("done"),3000))
    }
    @Test fun unchangedSyncPreservesSnoozeAndCount() {
        val first=event().put("rings",1).put("done",false).put("next",306000L).put("lastStop",6000L)
        val restored=AlarmJournal.merge(listOf(event()),listOf(first),7000).single()
        assertEquals(306000L,restored.getLong("next"))
        assertEquals(1,restored.getInt("rings"))
    }
    @Test fun turningSnoozeOffCancelsAPendingRepeatDuringSync() {
        val first=event().put("rings",1).put("next",306000L).put("lastStop",6000L)
        val incoming=event().put("snoozeEnabled",false)
        val restored=AlarmJournal.merge(listOf(incoming),listOf(first),7000).single()
        assertEquals(0L,restored.getLong("next"))
    }
    @Test fun duplicateFireDoesNotStartAnotherAudioRound() {
        val e=event().put("next",1000L).put("rings",0)
        assertTrue(AlarmJournal.startRound(e,1000,2000))
        assertFalse(AlarmJournal.startRound(e,1001,2001))
        assertEquals(1,e.getInt("rings"))
        assertEquals(61000L,e.getLong("ringUntil"))
    }
    @Test fun snoozeDisabledHasOneRoundAndNoAutomaticRepeat() {
        val e=event().put("next",1000L).put("snoozeEnabled",false).put("limit",5)
        assertTrue(AlarmJournal.startRound(e,1000,2000))
        assertEquals(0L,e.getLong("next"))
        assertFalse(AlarmJournal.stopRound(e,false,2000))
        assertEquals(1,e.getInt("rings"))
    }
    @Test fun dismissEndsAudioAndEveryLaterRound() {
        val e=event().put("next",1000L)
        assertTrue(AlarmJournal.startRound(e,1000,2000))
        assertTrue(AlarmJournal.stopRound(e,true,2000))
        assertEquals(0L,e.getLong("ringUntil"))
        assertEquals(0L,e.getLong("next"))
        assertTrue(e.getBoolean("done"))
        assertFalse(AlarmJournal.startRound(e,310000,311000))
    }
    @Test fun repeatedSnoozeCannotPostponeWaitingRound() {
        val e=event().put("next",1000L)
        AlarmJournal.startRound(e,1000,2000)
        assertTrue(AlarmJournal.stopRound(e,false,2000))
        assertEquals(302000L,e.getLong("next"))
        assertFalse(AlarmJournal.stopRound(e,false,3000))
        assertEquals(302000L,e.getLong("next"))
    }
    @Test fun classDeadlineStopsRingAndRejectsFutureRound() {
        val e=event().put("next",1000L).put("deadline",2000L)
        assertTrue(AlarmJournal.startRound(e,1000,2000))
        assertEquals(2000L,e.getLong("ringUntil"))
        assertEquals(0L,e.getLong("next"))
        assertFalse(AlarmJournal.startRound(e,2000,3000))
    }
    @Test fun expiredTombstonesArePruned() {
        assertTrue(AlarmJournal.merge(emptyList(),listOf(event()),900001).isEmpty())
    }
    @Test fun upgradeKeyAndChangedScheduleKeepDismissal() {
        val old=event().put("key","old-timestamp-key").put("id",321).put("done",true).put("rings",1)
        val next=event(5000).put("key","stable-new-key").put("id",321)
        val merged=AlarmJournal.merge(listOf(next),listOf(old),3000)
        assertEquals(1,merged.size)
        assertTrue(merged.single().getBoolean("done"))
    }
    @Test fun staleConfigurationCannotFireAfterEdit() {
        val e=event().put("version",3).put("next",1000L)
        assertFalse(AlarmJournal.acceptsVersion(e,2))
        assertTrue(AlarmJournal.acceptsVersion(e,3))
    }
    @Test fun tooLateBeforeClassIsSkippedAndMarkedDone() {
        val e=event().put("next",1000L).put("deadline",1800000L)
        assertFalse(AlarmJournal.startRound(e,901001L,901001L))
        assertTrue(e.optBoolean("done"))
    }
    @Test fun newlyEditedPastTriggerAlertsOnceBeforeClass() {
        val e=AlarmJournal.merge(listOf(event()),emptyList(),2000L).single()
        assertEquals(2000L,e.getLong("next"))
        assertTrue(AlarmJournal.startRound(e,2000L,2000L))
    }
    @Test fun configurationChangeStopsOldActiveRound() {
        val old=event().put("room","old").put("next",1000L).put("version",1)
        AlarmJournal.startRound(old,1000L,1000L)
        val revised=AlarmJournal.merge(listOf(event().put("room","new")),listOf(old),2000L).single()
        assertEquals(2,revised.getInt("version"))
        assertEquals(0L,revised.getLong("ringUntil"))
    }
    @Test fun changingLeadPastNowAlertsOnceWhileUnchangedLateEventsStayLate() {
        val old=event(700000L).put("next",700000L).put("rings",0)
        // Deadline must remain future for this product rule.
        val futureOld=old.put("deadline",2000000L)
        val futureNew=event(1000L).put("deadline",2000000L)
        val changed=AlarmJournal.merge(listOf(futureNew),listOf(futureOld),1000000L).single()
        assertEquals(1000000L,changed.getLong("next"))
        assertTrue(AlarmJournal.startRound(changed,1000000L,1000000L))
        val unchanged=AlarmJournal.merge(listOf(futureNew),listOf(futureNew.put("next",1000L).put("rings",0)),1000000L).single()
        assertFalse(AlarmJournal.startRound(unchanged,1000000L,1000000L))
    }
}
