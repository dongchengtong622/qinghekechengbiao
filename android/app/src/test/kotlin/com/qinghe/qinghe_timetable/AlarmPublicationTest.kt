package com.qinghe.qinghe_timetable

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AlarmPublicationTest {
    private fun event()=JSONObject().put("key","course-one").put("enabled",true).put("version",1)
        .put("rings",1).put("ringUntil",5000L).put("realUntil",6000L).put("ringStarted",1000L).put("deadline",10000L)
    private fun allowed(current:JSONObject?,snapshot:JSONObject,retired:Boolean=false,active:Boolean=true)=
        AlarmJournal.canPublishSnapshot(current,snapshot,retired,active,2000L,3000L)

    @Test fun disableBetweenFireAndPublicationRejectsOldSnapshot() {
        val snapshot=event()
        assertFalse(allowed(event().put("enabled",false),snapshot))
    }
    @Test fun changedConfigurationRejectsPriorVersion() {
        assertFalse(allowed(event().put("version",2),event()))
    }
    @Test fun snoozeBeforePublicationRejectsEndedRound() {
        assertFalse(allowed(event().put("ringUntil",0L),event()))
    }
    @Test fun oldRoundCannotPublishOverNewRound() {
        assertFalse(allowed(event().put("rings",2),event()))
    }
    @Test fun currentTriggeredRoundCanStillPublish() {
        assertTrue(allowed(event(),event()))
    }
    @Test fun onlyExplicitCollapseCanUseRetiredCourseSnapshot() {
        assertFalse(allowed(null,event()))
        assertTrue(allowed(null,event(),retired=true,active=false))
        assertFalse(allowed(event().put("enabled",false),event(),retired=true,active=false))
    }
}
