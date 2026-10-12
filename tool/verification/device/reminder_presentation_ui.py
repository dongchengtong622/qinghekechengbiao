import sys,time,re
sys.path.insert(0,'tool/verification/device')
from device_ui import *
store=re.search(r'^com\.qinghe\.qinghe_timetable\.AlarmStore -> (.+):$',(ROOT/'build/app/outputs/mapping/release/mapping.txt').read_text(encoding='utf-8'),re.M).group(1)
adb('shell','input','keyevent',224);adb('shell','input','keyevent',3)
state=adb('shell','dumpsys','window','policy');assert 'showing=false' in state,'Unlock phone first'
result=adb('shell','am','instrument','-w','-e','mode','reminder-fixture','-e','storeClass',store,'com.qinghe.verification/com.qinghe.verification.VerificationInstrumentation')
assert 'Independent reminder fixture registered' in result,result
print('Fixture scheduled in 15 seconds',flush=True)
time.sleep(11);found=False
for i in range(6):
 ns=dump('fast-unlocked-'+str(i))
 if '测试课程 · 锁屏提醒' in labels(ns):found=True;break
 time.sleep(.3)
state=adb('shell','dumpsys','window');assert not any('CourseAlarmActivity' in x for x in state.splitlines() if 'mCurrentFocus' in x), 'Unlocked takeover'
found = found or 'mHeadsUpPinnedMode=true' in adb('shell','dumpsys','activity','service','com.android.systemui/.SystemUIService')
print('Unlocked heads-up:',found,flush=True)
adb('shell','screencap','-p','/sdcard/Download/qinghe-unlocked-test.png');adb('pull','/sdcard/Download/qinghe-unlocked-test.png',str((OUT/'unlocked-banner-test.png').relative_to(ROOT)))
adb('shell','cmd','statusbar','expand-notifications');time.sleep(.5)
ns=dump('notification-center-details');print(labels(ns),flush=True)
for field in ['测试课程 · 锁屏提醒','测试上课时间','测试教室 A101','测试教师']:
 assert field in labels(ns), 'Missing center field '+field
adb('shell','screencap','-p','/sdcard/Download/qinghe-center-test.png');adb('pull','/sdcard/Download/qinghe-center-test.png',str((OUT/'notification-center-test.png').relative_to(ROOT)))
click(ns,'测试课程 · 锁屏提醒');ns=dump('unlocked-click-details')
assert '测试教室 A101' in labels(ns) and '测试教师' in labels(ns), labels(ns)
adb('shell','screencap','-p','/sdcard/Download/qinghe-style-test.png');adb('pull','/sdcard/Download/qinghe-style-test.png',str((OUT/'reminder-light-style.png').relative_to(ROOT)))
click(ns,'稍后提醒',True)
print('PASS center directly shows course/time/room/teacher, click details, snooze stops',flush=True)
started=time.monotonic()
while time.monotonic()-started<75:
 time.sleep(10);adb('shell','input','keyevent',224)
 if 'id=2147483646 ' in adb('shell','dumpsys','notification'):break
adb('shell','cmd','statusbar','expand-notifications');time.sleep(.5);ns=dump('snoozed-center')
assert '测试课程 · 锁屏提醒' in labels(ns),labels(ns)
click(ns,'测试课程 · 锁屏提醒');ns=dump('snoozed-details')
assert '第 2 次' in labels(ns), labels(ns)
assert '稍后提醒' not in labels(ns), labels(ns)
click(ns,'关闭本节课提醒')
print('PASS snooze fires second round and close stops reminder; heads-up='+str(found),flush=True)
assert found,'All detail/action checks passed, but no unlocked heads-up visible'
