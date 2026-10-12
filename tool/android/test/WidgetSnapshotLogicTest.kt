package com.qinghe.qinghe_timetable
import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject
import java.time.Instant
class WidgetSnapshotLogicTest {
 private val now=Instant.parse("2026-10-07T02:00:00Z").toEpochMilli()
 private fun snapshot(entries:String)=JSONObject("""{"schemaVersion":1,"configured":true,"coverageStart":$now,"coverageEnd":${now+86400000},"firstWeekStart":"2026-09-07","totalWeeks":20,"timeZone":"Asia/Shanghai","instances":[$entries]}""")
 @Test fun unknownDoesNotBecomeCountdown(){val r=WidgetSnapshotLogic.select(snapshot("""{"date":"2026-10-07","courseName":"未知","startAt":null,"endAt":null,"startSection":1}"""),now);assertEquals("时间待确认",r.status);assertNull(r.next?.optLong("startAt")?.takeIf{it!=0L});}
 @Test fun halfOpenBoundsAndTodayEnd(){val item="""{"date":"2026-10-07","courseName":"A","startAt":$now,"endAt":${now+1000},"startSection":1}""";assertEquals("正在上课",WidgetSnapshotLogic.select(snapshot(item),now).status);assertEquals("今日课程已结束",WidgetSnapshotLogic.select(snapshot(item),now+1000).status);}
 @Test fun futureSnapshotExpiredFailsRecoverably(){val s=snapshot("");assertEquals("今天没有课程",WidgetSnapshotLogic.select(s,now).status);assertEquals("数据需更新",WidgetSnapshotLogic.select(s,now+86400000).status);s.put("schemaVersion",99);assertEquals("数据需更新",WidgetSnapshotLogic.select(s,now).status);}
 @Test fun noImportAndConflictStates(){val s=snapshot("");s.put("configured",false);assertEquals("请先导入课表",WidgetSnapshotLogic.select(s,now).status);val item="""{"date":"2026-10-07","startAt":$now,"endAt":${now+1000},"startSection":1}""";assertEquals(2,WidgetSnapshotLogic.select(snapshot("$item,$item"),now).conflicts);}
}
