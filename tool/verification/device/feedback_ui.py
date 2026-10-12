import sys
sys.argv.append('verify-feedback')
from save_restore_ui import *
settings();ns=dump('feedback-settings-home')
for v in ['提醒设置','课表与学期','作息时间','数据管理','关于与帮助']:assert has(ns,v),labels(ns)
for v in ['铃声','振动','学期信息','备份与恢复']:assert not has(ns,v),labels(ns)
print('PASS five settings entries; details hidden',flush=True)
adb('shell','screencap','-p','/sdcard/Download/qinghe-feedback-settings.png');adb('pull','/sdcard/Download/qinghe-feedback-settings.png',str((OUT/'feedback-settings-home.png').relative_to(ROOT)))
click(ns,'提醒设置');ns=dump('feedback-reminder-options')
assert all(v in labels(ns) for v in ['铃声','振动','稍后提醒','课程提醒权限']),labels(ns)
back();click(dump('feedback-settings-return'),'课表与学期');ns=dump('feedback-semester-options')
assert '课表管理' in labels(ns) and '学期信息' in labels(ns) and '备份与恢复' not in labels(ns),labels(ns)
back();click(dump('feedback-settings-return'),'作息时间');ns=dump('feedback-schedule')
assert '19:35' not in labels(ns) and '20:25' not in labels(ns),labels(ns)
assert '19:00' in labels(ns) and '19:55' in labels(ns),labels(ns)
print('PASS current imported periods retained; stale default 11/12 no longer mixed',flush=True)
adb('shell','screencap','-p','/sdcard/Download/qinghe-feedback-schedule.png');adb('pull','/sdcard/Download/qinghe-feedback-schedule.png',str((OUT/'feedback-schedule.png').relative_to(ROOT)))
home();ns=home();click(ns,'更多');click(dump('feedback-import-menu'),'导入课表');click(dump('feedback-import-entry'),'选择 Excel 文件')
pick('v101_times','06_covered_evening_block.xlsx');ns=dump('feedback-evening-preview')
assert '确认导入' in labels(ns),labels(ns)
find_click('导入课表');ns=dump('feedback-evening-split')
assert '确认节次时间拆分' in labels(ns),labels(ns)
click(ns,'单节时长',True);click(dump('feedback-evening-duration'),'45 分钟')
combined=''
for i in range(5):
 combined+='\n'+labels(dump('feedback-evening-split-'+str(i)))
 adb('shell','input','swipe',800,2050,800,950,500)
assert '原始：第9–12节' not in combined,combined
assert '原始：第9–10节' in combined and '原始：第11–12节' in combined,combined
assert '课间不等或不是整分钟' not in combined,combined
assert '19:20' in combined and '20:15' in combined and '21:05' in combined,combined
print('PASS covered 9-12 block not redundantly split; smaller periods and unequal middle break preserved',flush=True)
# Cancel the split page and import preview. Never click the final save button.
back();back();home()
print('PASS preview cancelled; no test timetable saved; app returned home',flush=True)

