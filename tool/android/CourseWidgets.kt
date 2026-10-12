package com.qinghe.qinghe_timetable

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.min

object WidgetRuntime {
 const val REFRESH="com.qinghe.timetable.WIDGET_REFRESH"
 private const val PREFS="qinghe_widget_snapshot"
 private val zone=ZoneId.of("Asia/Shanghai")
 fun read(c:Context):JSONObject?=try{c.getSharedPreferences(PREFS,0).getString("snapshot",null)?.let{JSONObject(it)}}catch(_:Exception){null}
 @Synchronized fun save(c:Context,text:String){
  require(text.length<=1024*1024){"组件数据过大"};val data=JSONObject(text)
  require(data.getInt("schemaVersion")==1 && data.has("instances")){"组件格式无效"}
  val old=read(c);if(old!=null&&old.optLong("dataVersion")>data.getLong("dataVersion"))return
  check(c.getSharedPreferences(PREFS,0).edit().putString("snapshot",text).commit()){"组件保存失败"}
  updateAll(c)
 }
 fun ids(c:Context,provider:Class<out AppWidgetProvider>)=AppWidgetManager.getInstance(c).getAppWidgetIds(ComponentName(c,provider))
 fun updateAll(c:Context){
  val manager=AppWidgetManager.getInstance(c)
  for(provider in listOf(NextClassWidgetProvider::class.java,TodayClassesWidgetProvider::class.java))for(id in ids(c,provider))render(c,manager,id,provider==TodayClassesWidgetProvider::class.java)
  schedule(c)
 }
 private fun open(c:Context,id:Int,item:JSONObject?=null,route:String="home"):PendingIntent {
  val uri=Uri.Builder().scheme("qinghe-widget").authority("open").appendPath(id.toString()).appendQueryParameter("route",route)
  val intent=Intent(c,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP).putExtra("widgetRoute",route)
  if(item!=null){for(key in listOf("courseId","scheduleId","date")){val v=item.optString(key);intent.putExtra(key,v);uri.appendQueryParameter(key,v)};intent.putExtra("sessionIndex",item.optInt("sessionIndex"));uri.appendQueryParameter("sessionIndex",item.optInt("sessionIndex").toString())}
  intent.data=uri.build()
  return PendingIntent.getActivity(c,0,intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
 }
 private fun refresh(c:Context,id:Int):PendingIntent=PendingIntent.getBroadcast(c,id,Intent(c,NextClassWidgetProvider::class.java).setAction(REFRESH).setData(Uri.parse("qinghe-widget://refresh/$id")),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
 private fun clock(t:Long)=DateTimeFormatter.ofPattern("HH:mm").format(Instant.ofEpochMilli(t).atZone(zone))
 fun render(c:Context,m:AppWidgetManager,id:Int,today:Boolean){
  val now=System.currentTimeMillis();val data=read(c);val state=WidgetSnapshotLogic.select(data,now)
  val v=RemoteViews(c.packageName,if(today)R.layout.widget_today_classes else R.layout.widget_next_class)
  val route=if(state.status=="请先导入课表")"import" else "home"
  v.setOnClickPendingIntent(R.id.widget_root,open(c,id,route=route))
  v.setOnClickPendingIntent(R.id.widget_refresh,refresh(c,id))
  v.setOnClickPendingIntent(R.id.widget_title,open(c,id,route=route))
  v.setTextViewText(R.id.widget_updated,"更新于 ${clock(now)}")
  val opts=m.getAppWidgetOptions(id);val height=opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT,160)
  v.setViewVisibility(R.id.widget_updated,if(height<150)View.GONE else View.VISIBLE)
  if(today){
   val date=Instant.ofEpochMilli(now).atZone(zone);val day=listOf("一","二","三","四","五","六","日")[date.dayOfWeek.value-1]
   v.setTextViewText(R.id.widget_title,"${state.week?.let{"第${it}周 · "}?:""}星期$day")
   val limit=if(height>=190)4 else if(height<145)2 else 3
   val visible=state.today.take(limit)
   v.setTextViewText(R.id.widget_status,if(visible.isEmpty())state.status else if(state.conflicts>1)state.status else "今日课程")
   val rowIds=listOf(R.id.widget_row1,R.id.widget_row2,R.id.widget_row3,R.id.widget_row4)
   for((index,row) in rowIds.withIndex()){
    val item=visible.getOrNull(index);v.setViewVisibility(row,if(item==null)View.GONE else View.VISIBLE)
    if(item!=null){val time=if(item.isNull("startAt"))"时间待确认" else clock(item.getLong("startAt"));v.setTextViewText(row,"$time  ${item.optString("courseName")} · ${item.optString("room")}");v.setOnClickPendingIntent(row,open(c,id,item))}
   }
   v.setTextViewText(R.id.widget_more,if(state.today.size>limit)"还有 ${state.today.size-limit} 门 · 打开完整课表" else "打开完整课表")
   v.setOnClickPendingIntent(R.id.widget_more,open(c,id))
  }else{
   v.setTextViewText(R.id.widget_title,"青禾课表")
   v.setTextViewText(R.id.widget_status,state.status)
   val item=state.next
   v.setTextViewText(R.id.widget_course,item?.optString("courseName")?:"")
   v.setTextViewText(R.id.widget_room,item?.optString("room")?:"")
   val text=if(item==null)"" else if(item.isNull("startAt")||item.isNull("endAt"))"${item.optString("sectionLabel")} · 时间待确认" else if(state.status=="正在上课")"${item.optString("timeLabel")} · ${clock(item.optLong("endAt"))}结束" else "${item.optString("timeLabel")}\n更新时距上课约 ${((item.optLong("startAt")-now)/60000).coerceAtLeast(0)} 分钟"
   v.setInt(R.id.widget_course,"setMaxLines",if(height<180)1 else 2)
   v.setInt(R.id.widget_time,"setMaxLines",if(height<150)1 else 2)
   v.setTextViewText(R.id.widget_time,text)
   if(item!=null){val link=open(c,id,item);v.setOnClickPendingIntent(R.id.widget_course,link);v.setOnClickPendingIntent(R.id.widget_time,link);v.setOnClickPendingIntent(R.id.widget_room,link)}
   v.setTextViewTextSize(R.id.widget_course,android.util.TypedValue.COMPLEX_UNIT_SP,if(height<150)15f else 18f)
  }
  m.updateAppWidget(id,v)
 }
 private fun tick(c:Context)=PendingIntent.getBroadcast(c,10401,Intent(c,NextClassWidgetProvider::class.java).setAction(REFRESH).setData(Uri.parse("qinghe-widget://tick")),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
 fun schedule(c:Context){
  val alarm=c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
  if(ids(c,NextClassWidgetProvider::class.java).isEmpty()&&ids(c,TodayClassesWidgetProvider::class.java).isEmpty()){alarm.cancel(tick(c));return}
  val now=System.currentTimeMillis();val midnight=Instant.ofEpochMilli(now).atZone(zone).toLocalDate().plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
  var boundary=min(now+30*60000,midnight)
  read(c)?.optJSONArray("instances")?.let{a->for(i in 0 until a.length()){val item=a.optJSONObject(i)?:continue;for(k in listOf("startAt","endAt")){if(!item.isNull(k)){val t=item.optLong(k);if(t>now)boundary=min(boundary,t)}}}}
  alarm.set(AlarmManager.RTC,boundary.coerceAtLeast(now+1000),tick(c))
 }
 fun pin(c:Context,today:Boolean):Boolean {
  if(Build.VERSION.SDK_INT<26)return false
  val m=AppWidgetManager.getInstance(c);if(!m.isRequestPinAppWidgetSupported)return false
  return m.requestPinAppWidget(ComponentName(c,if(today)TodayClassesWidgetProvider::class.java else NextClassWidgetProvider::class.java),null,null)
 }
}
open class NextClassWidgetProvider:AppWidgetProvider(){
 override fun onReceive(c:Context,i:Intent){super.onReceive(c,i);if(i.action in listOf(WidgetRuntime.REFRESH,Intent.ACTION_BOOT_COMPLETED,Intent.ACTION_TIME_CHANGED,Intent.ACTION_TIMEZONE_CHANGED,Intent.ACTION_MY_PACKAGE_REPLACED))WidgetRuntime.updateAll(c)}
 override fun onUpdate(c:Context,m:AppWidgetManager,ids:IntArray){WidgetRuntime.updateAll(c)}
 override fun onAppWidgetOptionsChanged(c:Context,m:AppWidgetManager,id:Int,options:Bundle){WidgetRuntime.updateAll(c)}
 override fun onDeleted(c:Context,ids:IntArray){WidgetRuntime.schedule(c)}
 override fun onDisabled(c:Context){WidgetRuntime.schedule(c)}
}
class TodayClassesWidgetProvider:NextClassWidgetProvider()
