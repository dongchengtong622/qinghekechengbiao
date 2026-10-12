import sys,time,re
sys.path.insert(0,'tool/verification/device')
from device_ui import *
store=re.search(r'^com\.qinghe\.qinghe_timetable\.AlarmStore -> (.+):$',(ROOT/'build/app/outputs/mapping/release/mapping.txt').read_text(encoding='utf-8'),re.M).group(1)
adb('shell','input','keyevent',224);adb('shell','input','keyevent',3)
r=adb('shell','am','instrument','-w','-e','mode','reminder-fixture','-e','storeClass',store,'com.qinghe.verification/com.qinghe.verification.VerificationInstrumentation')
assert 'Independent reminder fixture registered' in r
adb('shell','input','keyevent',223)
time.sleep(18)
state=adb('shell','dumpsys','window')
assert any('CourseAlarmActivity' in x for x in state.splitlines() if 'mCurrentFocus' in x),'Locked alarm did not open full-screen'
ns=dump('lockscreen-new-style')
for field in ['测试课程 · 锁屏提醒','测试上课时间','测试教室 A101','测试教师']:assert field in labels(ns),field
adb('shell','screencap','-p','/sdcard/Download/qinghe-locked-new.png');adb('pull','/sdcard/Download/qinghe-locked-new.png',str((OUT/'lockscreen-new-style.png').relative_to(ROOT)))
click(ns,'关闭本节课提醒');time.sleep(1)
assert 'id=2147483646 ' not in adb('shell','dumpsys','notification'),'Close left center notification'
print('PASS locked full-screen mint course/time/room/teacher and shared Close',flush=True)
