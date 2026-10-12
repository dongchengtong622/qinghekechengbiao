import sys
sys.argv.append('menu-visual')
from save_restore_ui import *
ns=home();click(ns,'更多');ns=dump('menu-animation-final')
assert all(v in labels(ns) for v in ['导入课表','课程提醒','桌面小组件','设置']),labels(ns)
adb('shell','screencap','-p','/sdcard/Download/qinghe-menu-animation-final.png')
adb('pull','/sdcard/Download/qinghe-menu-animation-final.png',str((OUT/'menu-animation-final.png').relative_to(ROOT)))
back();home()
print('PASS ordinary release menu opens and closes; home restored; no data edited',flush=True)
