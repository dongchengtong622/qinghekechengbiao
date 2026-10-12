package com.qinghe.verification;
import android.app.Instrumentation; import android.content.Context; import android.os.Bundle;
import org.json.*; import java.io.*; import java.lang.reflect.*; import java.util.*;
public final class VerificationInstrumentation extends Instrumentation {
 private Bundle arguments;
 @Override public void onCreate(Bundle args){super.onCreate(args);arguments=args;start();}
 @Override public void onStart(){Bundle end=new Bundle();try {
  if("schedule-profile".equals(arguments.getString("mode"))){profileSchedule();return;}
  if("replace-profile".equals(arguments.getString("mode"))){profileReplace();return;}
  if("reminder-fixture".equals(arguments.getString("mode"))){seedReminderFixture();return;}
  if("widgets".equals(arguments.getString("mode"))){verifyWidgets();return;}
  if("reminders".equals(arguments.getString("mode"))){verifyReminders();return;}
  if("seed-retired".equals(arguments.getString("mode"))){seedRetired();end.putString("summary","PASS retired markers created without overwriting existing files");finish(-1,end);return;}
  JSONObject report=scanStorage(getTargetContext().getDataDir());report.put("tableDigests",databaseDigests());report.put("sessionContent",sessionContent());
  end.putString("storageBaseline",report.toString());finish(-1,end);
 }catch(Throwable e){end.putString("error",e.toString());StringWriter trace=new StringWriter();e.printStackTrace(new PrintWriter(trace));end.putString("trace",trace.toString());finish(0,end);}}
 private JSONArray sessionContent() throws Exception {
  File f=new File(getTargetContext().getFilesDir(),"qinghe_timetable.sqlite");JSONArray rows=new JSONArray();
  android.database.sqlite.SQLiteDatabase db=android.database.sqlite.SQLiteDatabase.openDatabase(f.getAbsolutePath(),null,android.database.sqlite.SQLiteDatabase.OPEN_READONLY);
  try(android.database.Cursor c=db.rawQuery("SELECT course_id,weekday,start_section,end_section,start_week,end_week,pattern,room,start_minute,end_minute,time_source FROM course_session_rows",null)){
   while(c.moveToNext()){JSONArray r=new JSONArray();for(int i=0;i<c.getColumnCount();i++)r.put(c.isNull(i)?JSONObject.NULL:c.getString(i));rows.put(r);}
  }finally{db.close();}return rows;
 }
 private void verifyWidgets() throws Exception {
  Context t=getTargetContext();String raw=t.getSharedPreferences("qinghe_widget_snapshot",0).getString("snapshot",null);
  if(raw==null)throw new AssertionError("Widget snapshot missing");JSONObject data=new JSONObject(raw);
  if(data.getInt("schemaVersion")!=1)throw new AssertionError("Invalid widget schema");JSONArray items=data.getJSONArray("instances");
  for(int i=0;i<items.length();i++){JSONObject c=items.getJSONObject(i);for(String key:new String[]{"courseId","scheduleId","sessionIndex","courseName","teacher","room","date","week","startSection","endSection","startAt","endAt"})if(!c.has(key))throw new AssertionError("Missing field "+key);}
  android.appwidget.AppWidgetManager m=android.appwidget.AppWidgetManager.getInstance(t);JSONArray providers=new JSONArray();
  for(String name:new String[]{"NextClassWidgetProvider","TodayClassesWidgetProvider"}){android.content.ComponentName cn=new android.content.ComponentName(t.getPackageName(),t.getPackageName()+"."+name);int[] ids=m.getAppWidgetIds(cn);JSONObject p=new JSONObject();p.put("name",name);p.put("boundCount",ids.length);JSONArray sizes=new JSONArray();for(int id:ids){Bundle o=m.getAppWidgetOptions(id);JSONObject size=new JSONObject();size.put("width",o.getInt("appWidgetMinWidth"));size.put("height",o.getInt("appWidgetMinHeight"));sizes.put(size);}p.put("sizes",sizes);providers.put(p);}
  JSONObject report=new JSONObject();report.put("instanceCount",items.length());report.put("allCourseFieldsPresent",true);report.put("providers",providers);report.put("schemaVersion",1);Bundle end=new Bundle();end.putString("widgets",report.toString());finish(-1,end);
 }
 private void seedRetired()throws Exception {
  Context t=getTargetContext();File dir=new File(t.getNoBackupFilesDir(),"ocr-v09");dir.mkdirs();
  for(String name:new String[]{"PP-OCRv6_det_small.onnx","PP-OCRv6_rec_small.onnx","slanet-plus.onnx"}){File f=new File(dir,name);if(!f.exists())try(OutputStream stream=new FileOutputStream(f)){stream.write(new byte[]{1,2,3,4});}}
  // Markers represent the retired assets; no model/inference code is installed by this tool.
 }
 private JSONArray databaseDigests()throws Exception {
  File file=new File(getTargetContext().getFilesDir(),"qinghe_timetable.sqlite");JSONArray report=new JSONArray();if(!file.isFile())return report;
  android.database.sqlite.SQLiteDatabase db=android.database.sqlite.SQLiteDatabase.openDatabase(file.getAbsolutePath(),null,android.database.sqlite.SQLiteDatabase.OPEN_READONLY);
  try(android.database.Cursor tables=db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",null)){
   while(tables.moveToNext()){
    String name=tables.getString(0);JSONArray rows=new JSONArray();int count=0;
    try(android.database.Cursor cursor=db.rawQuery("SELECT * FROM \""+name.replace("\"","\"\"")+"\" ORDER BY 1",null)){
     while(cursor.moveToNext()){JSONArray row=new JSONArray();for(int i=0;i<cursor.getColumnCount();i++)row.put(cursor.isNull(i)?JSONObject.NULL:cursor.getType(i)==android.database.Cursor.FIELD_TYPE_BLOB?android.util.Base64.encodeToString(cursor.getBlob(i),android.util.Base64.NO_WRAP):cursor.getString(i));rows.put(row);count++;}
    }
    java.security.MessageDigest sha=java.security.MessageDigest.getInstance("SHA-256");StringBuilder hash=new StringBuilder();for(byte b:sha.digest(rows.toString().getBytes("UTF-8")))hash.append(String.format("%02x",b&255));
    JSONObject item=new JSONObject();item.put("name",name);item.put("rows",count);item.put("sha256",hash.toString());report.put(item);
   }
  }finally{db.close();}return report;
 }
 private void profileSchedule() throws Exception {
  Context target=getTargetContext();final android.content.SharedPreferences isolated=target.getSharedPreferences("qinghe_verification_profile",0);
  final Context scoped=new android.content.ContextWrapper(target){@Override public android.content.SharedPreferences getSharedPreferences(String name,int mode){return "course_alarm_v1".equals(name)?isolated:super.getSharedPreferences(name,mode);}};
  Class<?> c=Class.forName(arguments.getString("storeClass"),true,target.getClassLoader());Constructor<?> ctor=c.getDeclaredConstructor(Context.class);ctor.setAccessible(true);final Object store=ctor.newInstance(scoped);
  Method schedule=null,pending=null;
  for(Method m:c.getDeclaredMethods()){Class<?>[] p=m.getParameterTypes();if(p.length==1&&p[0]==boolean.class&&Map.class.isAssignableFrom(m.getReturnType()))schedule=m;
   if(p.length==3&&p[0]==String.class&&p[1]==String.class&&android.app.PendingIntent.class.isAssignableFrom(m.getReturnType()))pending=m;}
  if(schedule==null)throw new AssertionError("Profile methods missing");schedule.setAccessible(true);final Method run=schedule;
  long at=System.currentTimeMillis()+86400000L;JSONArray events=new JSONArray();
  for(int i=0;i<32;i++)events.put(new JSONObject().put("key","verification-profile-"+i).put("id",-210000-i).put("at",at+i*60000L).put("next",at+i*60000L).put("deadline",at+i*60000L+1800000L).put("version",1).put("interval",5).put("limit",1).put("snoozeEnabled",false).put("rings",0).put("silent",true));
  isolated.edit().clear().putString("events",events.toString()).commit();final JSONArray times=new JSONArray();final Throwable[] error={null};
  try {
   for(int i=0;i<3;i++)runOnMainSync(()->{try{long start=android.os.SystemClock.elapsedRealtimeNanos();Map<?,?> result=(Map<?,?>)run.invoke(store,true);if(((List<?>)result.get("ids")).size()!=32)throw new AssertionError("Profile registration incomplete");times.put((android.os.SystemClock.elapsedRealtimeNanos()-start)/1000000.0);}catch(Throwable e){error[0]=e;}});
   if(error[0]!=null)throw new AssertionError(error[0]);
  } finally {
   android.app.AlarmManager am=target.getSystemService(android.app.AlarmManager.class);for(int i=0;i<32;i++){android.content.Intent intent=new android.content.Intent().setClassName(target.getPackageName(),target.getPackageName()+".CourseAlarmReceiver").setAction("fire").setData(android.net.Uri.parse("qinghe-alarm://fire/verification-profile-"+i));android.app.PendingIntent pi=android.app.PendingIntent.getBroadcast(target,0,intent,android.app.PendingIntent.FLAG_NO_CREATE|android.app.PendingIntent.FLAG_IMMUTABLE);if(pi!=null){am.cancel(pi);pi.cancel();}}isolated.edit().clear().commit();
  }
  Bundle end=new Bundle();end.putString("profile",new JSONObject().put("events",32).put("mainThreadMs",times).put("userTimetableUntouched",true).toString());finish(-1,end);
 }
 private void profileReplace() throws Exception {
  Context target=getTargetContext();final android.content.SharedPreferences isolated=target.getSharedPreferences("qinghe_verification_replace_profile",0);
  final Context scoped=new android.content.ContextWrapper(target){@Override public android.content.SharedPreferences getSharedPreferences(String name,int mode){return "course_alarm_v1".equals(name)?isolated:super.getSharedPreferences(name,mode);}};
  Class<?> c=Class.forName(arguments.getString("storeClass"),true,target.getClassLoader());Constructor<?> ctor=c.getDeclaredConstructor(Context.class);ctor.setAccessible(true);final Object store=ctor.newInstance(scoped);
  Method replace=null;
  for(Method m:c.getDeclaredMethods()){Class<?>[]p=m.getParameterTypes();if(p.length==2&&List.class.isAssignableFrom(p[0])&&p[1]==boolean.class&&Map.class.isAssignableFrom(m.getReturnType()))replace=m;}
  if(replace==null)throw new AssertionError("Replace method missing");replace.setAccessible(true);final Method run=replace;
  final List<JSONObject> events=new ArrayList<>();long at=System.currentTimeMillis()+86400000L;
  for(int i=0;i<300;i++)events.add(new JSONObject().put("key","verification-replace-"+i).put("id",-220000-i).put("at",at+i*60000L).put("deadline",at+i*60000L+1800000L).put("interval",5).put("limit",1).put("snoozeEnabled",false).put("silent",true).put("courseName","Profile course").put("room","Profile room").put("teacher","Profile teacher"));
  final JSONArray times=new JSONArray();final Throwable[] error={null};
  try {
   for(final boolean enabled:new boolean[]{true,false,true,false})runOnMainSync(()->{try{long start=android.os.SystemClock.elapsedRealtimeNanos();run.invoke(store,enabled?events:new ArrayList<JSONObject>(),false);times.put(new JSONObject().put("enabled",enabled).put("mainThreadMs",(android.os.SystemClock.elapsedRealtimeNanos()-start)/1000000.0));}catch(Throwable e){error[0]=e;}});
   if(error[0]!=null)throw new AssertionError(error[0]);
  } finally {
   android.app.AlarmManager am=target.getSystemService(android.app.AlarmManager.class);for(int i=0;i<300;i++){android.content.Intent intent=new android.content.Intent().setClassName(target.getPackageName(),target.getPackageName()+".CourseAlarmReceiver").setAction("fire").setData(android.net.Uri.parse("qinghe-alarm://fire/verification-replace-"+i));android.app.PendingIntent pi=android.app.PendingIntent.getBroadcast(target,0,intent,android.app.PendingIntent.FLAG_NO_CREATE|android.app.PendingIntent.FLAG_IMMUTABLE);if(pi!=null){am.cancel(pi);pi.cancel();}}isolated.edit().clear().commit();
  }
  Bundle end=new Bundle();end.putString("profile",new JSONObject().put("events",300).put("transitions",times).put("userTimetableUntouched",true).toString());finish(-1,end);
 }
 private void seedReminderFixture() throws Exception {
  Context t=getTargetContext();Class<?> c=Class.forName(arguments.getString("storeClass"),true,t.getClassLoader());
  Constructor<?> ctor=c.getDeclaredConstructor(Context.class);ctor.setAccessible(true);Object store=ctor.newInstance(t);
  for(Method m:c.getDeclaredMethods()){Class<?>[] p=m.getParameterTypes();
   if(p.length==4&&p[0]==String.class&&p[1]==String.class&&p[2]==long.class&&p[3]==boolean.class){m.setAccessible(true);m.invoke(store,null,null,15000L,false);}
  }
  android.content.SharedPreferences prefs=t.getSharedPreferences("course_alarm_v1",Context.MODE_PRIVATE);
  JSONArray events=new JSONArray(prefs.getString("events","[]"));JSONObject test=null;
  for(int i=0;i<events.length();i++){JSONObject e=events.getJSONObject(i);if(e.optString("key").startsWith("test-"))test=e;}
  if(test==null)throw new AssertionError("Test reminder missing");
  test.put("deadline",test.getLong("at")+180000L).put("snoozeEnabled",true).put("interval",1).put("limit",2);
  if(!prefs.edit().putString("events",events.toString()).commit())throw new AssertionError("Test reminder save failed");
  for(Method m:c.getDeclaredMethods()){Class<?>[] p=m.getParameterTypes();if(p.length==1&&p[0]==boolean.class&&java.util.Map.class.isAssignableFrom(m.getReturnType())){m.setAccessible(true);m.invoke(store,true);}}
  Bundle done=new Bundle();done.putString("summary","Independent reminder fixture registered; user timetable database untouched");finish(-1,done);
 }
 private void verifyReminders() throws Exception {
  Context target=getTargetContext();
  android.app.NotificationManager nm=target.getSystemService(android.app.NotificationManager.class);
  android.app.AlarmManager am=target.getSystemService(android.app.AlarmManager.class);
  JSONObject capabilities=new JSONObject();capabilities.put("notificationsAllowed",nm.areNotificationsEnabled());capabilities.put("exactAllowed",android.os.Build.VERSION.SDK_INT<31||am.canScheduleExactAlarms());capabilities.put("sdk",android.os.Build.VERSION.SDK_INT);
  JSONArray channels=new JSONArray();if(android.os.Build.VERSION.SDK_INT>=26)for(android.app.NotificationChannel c:nm.getNotificationChannels()){JSONObject ch=new JSONObject();ch.put("id",c.getId());ch.put("importance",c.getImportance());ch.put("sound",String.valueOf(c.getSound()));ch.put("visibility",c.getLockscreenVisibility());channels.put(ch);}capabilities.put("channels",channels);
  Bundle status=new Bundle();status.putString("capabilities",capabilities.toString());sendStatus(0,status);
  Class<?> storeClass=Class.forName(arguments.getString("storeClass"),true,target.getClassLoader());
  Constructor<?> constructor=storeClass.getDeclaredConstructor(Context.class);constructor.setAccessible(true);Object store=constructor.newInstance(target);
  Method addTest=null,stop=null;
  for(Method m:storeClass.getDeclaredMethods()){Class<?>[]p=m.getParameterTypes();if(p.length==4&&p[0]==String.class&&p[1]==String.class&&p[2]==long.class&&p[3]==boolean.class){addTest=m;}if((p.length==3||p.length==4)&&p[0]==String.class&&p[1]==boolean.class&&p[2]==Integer.class)stop=m;}
  if(addTest==null)throw new AssertionError("Real addTest method missing");addTest.setAccessible(true);
  long started=System.currentTimeMillis();addTest.invoke(store,null,null,5000L,true);
  boolean published=false;
  for(int i=0;i<45;i++){Thread.sleep(1000);for(android.service.notification.StatusBarNotification n:nm.getActiveNotifications())if(n.getId()==2147483646){JSONObject result=new JSONObject();result.put("timedNotificationActive",true);result.put("afterMs",System.currentTimeMillis()-started);result.put("category",n.getNotification().category);result.put("channel",android.os.Build.VERSION.SDK_INT>=26?n.getNotification().getChannelId():"legacy");result.put("visibility",n.getNotification().visibility);Bundle b=new Bundle();b.putString("reminder",result.toString());sendStatus(0,b);published=true;break;}if(published)break;}
  android.content.SharedPreferences prefs=target.getSharedPreferences("course_alarm_v1",Context.MODE_PRIVATE);
  JSONArray events=new JSONArray(prefs.getString("events","[]"));
  if(stop!=null){stop.setAccessible(true);for(int i=0;i<events.length();i++){JSONObject e=events.getJSONObject(i);if(e.optString("key").startsWith("test-")){if(stop.getParameterTypes().length==4)stop.invoke(store,e.getString("key"),true,e.optInt("version",1),e.optInt("id"));else stop.invoke(store,e.getString("key"),true,e.optInt("version",1));}}}
  nm.cancel(2147483646);nm.cancel(2147483647);
  if(!published)throw new AssertionError("Timed reminder was not submitted within 45 seconds");
  Bundle end=new Bundle();end.putString("summary","PASS release timer / receiver / notification");finish(-1,end);
 }

 private JSONObject scanStorage(File folder)throws Exception {
  JSONObject result=new JSONObject(); long total=0,cache=0,models=0;JSONArray databases=new JSONArray();
  List<File>queue=new ArrayList<>();queue.add(folder);
  for(int at=0;at<queue.size();at++){File current=queue.get(at);File[]children=current.listFiles();if(children==null)continue;for(File f:children){
   if(f.isDirectory()){if(!f.getCanonicalPath().startsWith(folder.getCanonicalPath()+File.separator))continue;queue.add(f);continue;}
   long bytes=f.length();total+=bytes;String relative=f.getAbsolutePath().substring(folder.getAbsolutePath().length()+1);
   if(relative.startsWith("cache/")||relative.startsWith("code_cache/"))cache+=bytes;if(relative.startsWith("no_backup/ocr-v09/"))models+=bytes;
   if(relative.endsWith(".sqlite")||relative.endsWith(".sqlite-wal")||relative.endsWith(".db")){
    java.security.MessageDigest sha=java.security.MessageDigest.getInstance("SHA-256");try(InputStream in=new FileInputStream(f)){byte[]b=new byte[8192];int n;while((n=in.read(b))!=-1)sha.update(b,0,n);}
    StringBuilder hash=new StringBuilder();for(byte b:sha.digest())hash.append(String.format("%02x",b&255));JSONObject db=new JSONObject();db.put("relativePath",relative);db.put("bytes",bytes);db.put("sha256",hash);databases.put(db);
   }
  }}
  result.put("privateFilesBytes",total);result.put("cacheFilesBytes",cache);result.put("ocrDirectoryBytes",models);result.put("databaseFiles",databases);try{if(android.os.Build.VERSION.SDK_INT>=26){android.app.usage.StorageStatsManager manager=getTargetContext().getSystemService(android.app.usage.StorageStatsManager.class);android.app.usage.StorageStats stats=manager.queryStatsForPackage(android.os.storage.StorageManager.UUID_DEFAULT,getTargetContext().getPackageName(),android.os.Process.myUserHandle());result.put("systemAppBytes",stats.getAppBytes());result.put("systemDataBytes",stats.getDataBytes());result.put("systemCacheBytes",stats.getCacheBytes());}}catch(Exception e){result.put("systemStorageUnavailable",e.getClass().getSimpleName());}return result;
 }
}

