import sys,time,json
sys.path.insert(0,'tool/verification/device')
from device_ui import *
click(dump('lockscreen-test-start'),'测试定时提醒')
print('Scheduled one-minute locked-screen test',flush=True)
adb('shell','input','keyevent',223)
started=time.monotonic();found=False
while time.monotonic()-started<85:
 time.sleep(2)
 state=adb('shell','dumpsys','window')
 if 'mCurrentFocus' in state and any('CourseAlarmActivity' in line for line in state.splitlines() if 'mCurrentFocus' in line):
  found=True;break
print('Lockscreen automatic activity:',found,'after',round(time.monotonic()-started,1),flush=True)
ns=dump('lockscreen-test-result');print(labels(ns),flush=True)
adb('shell','screencap','-p','/sdcard/Download/qinghe-lockscreen-test.png');adb('pull','/sdcard/Download/qinghe-lockscreen-test.png',str((OUT/'lockscreen-test.png').relative_to(ROOT)))
assert found,'System did not automatically show full-screen course reminder'
for expected in ['测试课程 · 锁屏提醒','测试上课时间','测试教室 A101','测试教师','关闭本节课提醒']:
 assert expected in labels(ns),expected
click(ns,'关闭本节课提醒')
print('PASS locked full-screen details and dismissal',flush=True)

