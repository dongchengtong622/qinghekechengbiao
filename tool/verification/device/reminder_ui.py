from save_restore_ui import *
ns=home();click(ns,'更多');click(dump('reminder-menu'),'课程提醒');ns=dump('reminders-enabled')
switches=[n for n in ns if n.get('class')=='android.widget.Switch' and '上课提醒' in n.get('content-desc','')]
assert len(switches)==1,labels(ns)
original_on=switches[0].get('checked')=='true'
if not original_on:click(ns,'上课提醒',True);ns=dump('reminders-enabled')
assert '提醒时间' in labels(ns) and '法定节假日静默' in labels(ns),labels(ns)
assert all(x in labels(ns) for x in ['下一次已安排提醒','教室：','教师：','上课：','提醒：']),labels(ns)
adb('shell','screencap','-p','/sdcard/Download/qinghe-v101-screen.png');adb('pull','/sdcard/Download/qinghe-v101-screen.png',str((OUT/'reminder-details.png').relative_to(ROOT)))
click(ns,'上课提醒',True);ns=dump('reminders-disabled')
assert '提醒时间' not in labels(ns) and '法定节假日静默' not in labels(ns),labels(ns)
assert '下一次已安排提醒' in labels(ns)
if original_on:click(ns,'上课提醒',True)
settings();ns=dump('reminder-settings')
assert all(v in labels(ns) for v in ['铃声','振动','稍后提醒','课程提醒权限']),labels(ns)
find_click('课程提醒权限',True);ns=dump('permission-settings')
assert '最近调度记录' not in labels(ns),labels(ns)
assert '通知权限' in labels(ns) and '精确提醒' in labels(ns),labels(ns)
home();print('PASS reminders detail, collapsed options, settings entry, hidden developer records; original switch restored',flush=True)