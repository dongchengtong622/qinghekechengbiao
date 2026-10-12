import sys,time
sys.path.insert(0,'tool/verification/device')
from device_ui import *
click(dump('unlocked-test-start'),'测试定时提醒')
adb('shell','input','keyevent',3)
print('Scheduled one-minute unlocked test; launcher remains visible',flush=True)
started=time.monotonic()
while time.monotonic()-started<45:
 time.sleep(10)
 # Keep the screen awake without changing any persistent device setting.
 adb('shell','input','tap',1000,1950)
found=False
while time.monotonic()-started<85:
 ns=dump('unlocked-banner-result')
 state=adb('shell','dumpsys','window')
 assert not any('CourseAlarmActivity' in x for x in state.splitlines() if 'mCurrentFocus' in x),'Unexpected automatic takeover while unlocked'
 if '测试课程 · 锁屏提醒' in labels(ns):found=True;break
 time.sleep(1)
print('Heads-up visible:',found,'after',round(time.monotonic()-started,1),flush=True)
print(labels(ns),flush=True)
adb('shell','screencap','-p','/sdcard/Download/qinghe-unlocked-test.png');adb('pull','/sdcard/Download/qinghe-unlocked-test.png',str((OUT/'unlocked-banner-test.png').relative_to(ROOT)))
assert found,'No visible unlocked heads-up notification'
adb('shell','cmd','statusbar','expand-notifications');time.sleep(.5)
ns=dump('notification-center-details')
for expected in ['测试课程 · 锁屏提醒', '测试上课时间', '测试教室 A101', '测试教师']:
 assert expected in labels(ns), 'Missing notification-center field: '+expected
adb('shell','screencap','-p','/sdcard/Download/qinghe-center-test.png');adb('pull','/sdcard/Download/qinghe-center-test.png',str((OUT/'notification-center-test.png').relative_to(ROOT)))
click(ns,'测试课程 · 锁屏提醒');ns=dump('unlocked-click-details')
adb('shell','screencap','-p','/sdcard/Download/qinghe-style-test.png');adb('pull','/sdcard/Download/qinghe-style-test.png',str((OUT/'reminder-light-style.png').relative_to(ROOT)))
for expected in ['测试教室 A101','测试教师','关闭本节课提醒']:
 assert expected in labels(ns),expected
click(ns,'关闭本节课提醒')
print('PASS unlocked heads-up without takeover, click opens details, dismiss',flush=True)
