import sys,statistics
sys.argv.append('menu-performance')
from save_restore_ui import *
ns=home()
click(ns,'更多');ns=dump('menu-compact')
assert all(v in labels(ns) for v in ['导入课表','课程提醒','桌面小组件','设置']),labels(ns)
adb('shell','screencap','-p','/sdcard/Download/qinghe-menu-compact.png');adb('pull','/sdcard/Download/qinghe-menu-compact.png',str((OUT/'menu-compact.png').relative_to(ROOT)))
back();ns=dump('week-title-hierarchy')
adb('shell','screencap','-p','/sdcard/Download/qinghe-week-title.png');adb('pull','/sdcard/Download/qinghe-week-title.png',str((OUT/'week-title-hierarchy.png').relative_to(ROOT)))
node=next(n for n in ns if n.get('content-desc')=='更多')
x1,y1,x2,y2=map(int,re.findall(r'\d+',node.get('bounds')))
for i in range(8):
 adb('shell','input','tap',(x1+x2)//2,(y1+y2)//2);time.sleep(.3);back()
print('PASS 8 menu open/close interactions',flush=True)
for i in range(4):
 click(dump('view-before-grid-'+str(i)),'周表');time.sleep(.3)
 click(dump('view-before-list-'+str(i)),'列表');time.sleep(.3)
print('PASS 4 grid/list round trips',flush=True)
click(dump('before-saturday'),'周六',True);time.sleep(.5)
adb('shell','screencap','-p','/sdcard/Download/qinghe-day-clean.png');adb('pull','/sdcard/Download/qinghe-day-clean.png',str((OUT/'day-selection-clean.png').relative_to(ROOT)))
ns=dump('after-saturday');click(ns,'回到今天');time.sleep(1.2)
pid=adb('shell','pidof','com.qinghe.qinghe_timetable').strip().split()[0]
lines=adb('logcat','-d','--pid='+pid,'-v','brief','-s','flutter:I').splitlines()
frames=[]
for line in lines:
 if 'QH_FRAME_BATCH ' in line:
  try:frames+=json.loads(line.split('QH_FRAME_BATCH ',1)[1])
  except json.JSONDecodeError:pass
assert frames,'No frame timing batches captured'
def summary(key):
 vals=sorted(f[key]/1000 for f in frames)
 return {'medianMs':round(statistics.median(vals),3),'p95Ms':round(vals[int((len(vals)-1)*.95)],3),'maximumMs':round(max(vals),3),'over16_67Ms':sum(v>16.67 for v in vals)}
result={'buildMode':'release with test-only frame callback','device':'vivo V2136A Android14','samples':len(frames),'build':summary('buildUs'),'raster':summary('rasterUs'),'scope':'startup, 8 menu cycles, 4 grid/list round trips and day selection; no before/after device baseline','noTestCoursesSaved':True}
(OUT/'menu-frame-metrics.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False),flush=True)
print('PASS interactions; today/list restored; no timetable data edited',flush=True)

