package com.qinghe.qinghe_timetable
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

data class WidgetSelection(val status:String,val today:List<JSONObject> = emptyList(),val next:JSONObject?=null,val conflicts:Int=0,val week:Int?=null)
object WidgetSnapshotLogic {
 fun select(data:JSONObject?,now:Long):WidgetSelection {
  if(data==null || data.optInt("schemaVersion")!=1 || now < data.optLong("coverageStart") || now>=data.optLong("coverageEnd"))return WidgetSelection("数据需更新")
  if(!data.optBoolean("configured"))return WidgetSelection("请先导入课表")
  return try{
   val zone=ZoneId.of(data.optString("timeZone","Asia/Shanghai"));val date=Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
   val first=LocalDate.parse(data.getString("firstWeekStart"));val offset=java.time.temporal.ChronoUnit.DAYS.between(first,date)
   val week=(offset/7+1).toInt().takeIf{offset>=0&&it<=data.getInt("totalWeeks")}
   val entries=data.getJSONArray("instances");val all=(0 until entries.length()).map{entries.getJSONObject(it)}.filter{it.optString("date")==date.toString()}.sortedBy{it.optInt("startSection")}
   val active=all.filter{!it.isNull("startAt")&&!it.isNull("endAt")&&it.optLong("startAt")<=now&&now<it.optLong("endAt")}
   val future=all.filter{it.isNull("startAt")||it.isNull("endAt")||it.optLong("endAt")>now}
   val unknown=future.firstOrNull{it.isNull("startAt")||it.isNull("endAt")}
   when{
    active.size>1->WidgetSelection("同时有${active.size}门课程",future,null,active.size,week)
    active.isNotEmpty()->WidgetSelection("正在上课",future,active.first(),1,week)
    unknown!=null->WidgetSelection("时间待确认",future,unknown,0,week)
    future.isNotEmpty()->WidgetSelection("下一节课",future,future.minBy{it.optLong("startAt")},0,week)
    all.isNotEmpty()->WidgetSelection("今日课程已结束",emptyList(),null,0,week)
    else->WidgetSelection("今天没有课程",emptyList(),null,0,week)
   }
  }catch(_:Exception){WidgetSelection("数据需更新")}
 }
}
