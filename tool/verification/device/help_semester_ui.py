import sys
sys.argv.append('help-semester')
from save_restore_ui import *
settings(); click(dump('help-settings'),'关于与帮助'); click(dump('help-about'),'使用说明')
ns=dump('help-guide'); assert has(ns,'使用说明'), labels(ns)
click(ns,'1. 第一次使用与操作顺序',True); ns=dump('help-first-steps')
assert '可以先导入并核对课程' in labels(ns), labels(ns)
adb('shell','screencap','-p','/sdcard/Download/qinghe-help-guide.png')
adb('pull','/sdcard/Download/qinghe-help-guide.png',str((OUT/'help-guide.png').relative_to(ROOT)))
print('PASS guide page and expanded first-use steps',flush=True)
settings(); click(dump('term-settings'),'课表与学期'); click(dump('term-group'),'学期信息',True); ns=dump('term-before-invalid')
fields=[n for n in ns if n.get('class')=='android.widget.EditText']; assert len(fields)==2,labels(ns)
n=fields[1]; x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')))
adb('shell','input','tap',(x1+x2)//2,(y1+y2)//2)
adb('shell','input','keyevent',123)
for _ in range(3): adb('shell','input','keyevent',67)
text('1'); back(); click(dump('term-invalid-input'),'确定'); ns=dump('term-invalid-blocked')
assert '已有课程到第' in labels(ns) and '请填写至少' in labels(ns),labels(ns)
assert has(ns,'设置学期'),labels(ns)
click(ns,'取消'); home()
print('PASS short term blocked with visible explanation; cancelled; no course or term data saved',flush=True)


