import sys,time,re
sys.path.insert(0,'tool/verification/device')
from device_ui import *
store=re.search(r'^com\.qinghe\.qinghe_timetable\.AlarmStore -> (.+):$',(ROOT/'build/app/outputs/mapping/release/mapping.txt').read_text(encoding='utf-8'),re.M).group(1)
def capture(name):
 adb('shell','screencap','-p','/sdcard/Download/qinghe-persistent.png')
 adb('pull','/sdcard/Download/qinghe-persistent.png',str((OUT/(name+'.png')).relative_to(ROOT)))
def active():return 'id=2147483646 ' in adb('shell','dumpsys','notification')
def pinned():
 data=adb('shell','dumpsys','activity','service','com.android.systemui/.SystemUIService')
 return 'mHeadsUpPinnedMode=true' in data

def fixture():
 adb('shell','input','keyevent',224);adb('shell','input','keyevent',3)
 assert 'showing=false' in adb('shell','dumpsys','window','policy'),'Unlock phone first'
 result=adb('shell','am','instrument','-w','-e','mode','reminder-fixture','-e','storeClass',store,'com.qinghe.verification/com.qinghe.verification.VerificationInstrumentation')
 assert 'Independent reminder fixture registered' in result,result
 time.sleep(18)
 assert active(),'Reminder not delivered'
 assert pinned(),'Heads-up not pinned'
 assert not any('CourseAlarmActivity' in x for x in adb('shell','dumpsys','window').splitlines() if 'mCurrentFocus' in x),'Unlocked takeover'

fixture();capture('persistent-banner-start');print('PASS unlocked persistent heads-up displayed, no automatic full screen',flush=True)
for i in range(0 if '--quick-actions' in sys.argv else 4):
 time.sleep(15)
 assert pinned(),'Banner auto-disappeared at '+str(18+(i+1)*15)+' seconds'
if '--quick-actions' not in sys.argv:
 capture('persistent-banner-after-60s');print('PASS banner still pinned after 60-second sound limit',flush=True)
adb('shell','input','swipe',540,460,540,60,350);time.sleep(1)
assert not pinned(),'Up swipe did not collapse heads-up'
assert active(),'Up swipe removed notification-center card'
adb('shell','cmd','statusbar','expand-notifications');ns=dump('persistent-up-swipe-center')
for field in ['测试课程 · 锁屏提醒','测试上课时间','测试教室 A101','测试教师']:assert field in labels(ns),field
click(ns,'测试课程 · 锁屏提醒');ns=dump('persistent-after-swipe-details');click(ns,'关闭本节课提醒');time.sleep(1);assert not active(),'Close left notification in center'
print('PASS up swipe retains full center card; Close removes the shared reminder',flush=True)
fixture();capture('persistent-banner-before-side-swipe')
adb('shell','input','swipe',540,300,1040,300,350);time.sleep(3)
assert not pinned(),'Side swipe did not collapse heads-up'
assert active(),'Side swipe removed notification-center card'
print('PASS side swipe collapses banner while retaining notification-center card',flush=True)
adb('shell','cmd','statusbar','expand-notifications');ns=dump('persistent-side-swipe-center');click(ns,'测试课程 · 锁屏提醒');ns=dump('persistent-after-side-details');click(ns,'关闭本节课提醒')
fixture()
adb('shell','input','tap',865,310);time.sleep(1)
assert not active(),'Banner Close left notification-center card'
assert not pinned(),'Banner Close left heads-up'
print('PASS banner Close removes both heads-up and notification-center card',flush=True)
