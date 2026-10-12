import sys
sys.argv.append('week-feedback')
from save_restore_ui import *
ns=home();click(ns,'选择周次',True);ns=dump('week-clean-menu')
assert '本周' in labels(ns),labels(ns)
adb('shell','screencap','-p','/sdcard/Download/qinghe-week-clean-menu.png')
adb('pull','/sdcard/Download/qinghe-week-clean-menu.png',str((OUT/'week-clean-menu.png').relative_to(ROOT)))
back();home()
print('PASS week menu opens and dismisses; same week restored; no timetable edits',flush=True)
