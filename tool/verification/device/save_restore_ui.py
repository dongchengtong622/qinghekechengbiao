from device_ui import *
def has(ns,label):return any(label==n.get('text') or label==n.get('content-desc') for n in ns)
def find_click(label,contains=False):
 for step in range(12):
  ns=dump('locate-'+str(step))
  if any(label in (n.get('text','')+'\n'+n.get('content-desc','')) if contains else label in (n.get('text',''),n.get('content-desc','')) for n in ns):click(ns,label,contains);return
  adb('shell','input','swipe',800,1800,800,1200,650)
 raise AssertionError('Missing '+label+'\n'+labels(ns))
def pick(folder,file):
 ns=dump('pick-roots');click(ns,'显示根目录');ns=dump('pick-root-list');click(ns,'V2136A')
 for _ in range(8):adb('shell','input','swipe',800,800,800,2150,200)
 find_click('Download')
 for _ in range(20):adb('shell','input','swipe',800,800,800,2150,200)
 find_click(folder)
 for _ in range(5):adb('shell','input','swipe',800,800,800,2150,200)
 find_click(file)
 time.sleep(1)
def home():
 for _ in range(6):
  ns=dump('return-home')
  if has(ns,'更多'):return ns
  back()
 raise AssertionError('Home unavailable')
def settings():
 ns=home();click(ns,'更多');click(dump('settings-menu'),'设置')
mode=sys.argv[1]
if mode=='save':
 ns=home();click(ns,'更多');click(dump('import-menu'),'导入课表');click(dump('import-entry'),'选择 Excel 文件')
 pick('v101_times','01_45min_lecture.xlsx');ns=dump('save-preview')
 assert '高等数学' in labels(ns) and '张明' in labels(ns),labels(ns)
 find_click('导入课表');ns=dump('save-split');assert '确认节次时间拆分' in labels(ns),labels(ns)
 click(ns,'单节时长',True);click(dump('save-duration'),'45 分钟');ns=dump('save-suggestion')
 assert '08:00' in labels(ns) and '08:45' in labels(ns) and '08:55' in labels(ns) and '09:40' in labels(ns),labels(ns)
 find_click('确认拆分并继续导入');time.sleep(2);ns=dump('save-complete');assert '确认节次时间拆分' not in labels(ns),labels(ns)
 print('PASS actual course save and 45-minute split',flush=True)
elif mode=='restore':
 settings();find_click('备份与恢复',True);click(dump('backup-entry'),'从 JSON 备份恢复')
 pick('v100_university','Qinghe_V101_pretest_20261007.json');ns=dump('restore-confirm')
 assert '备份包含 26 门课程' in labels(ns),labels(ns)
 click(ns,'覆盖并恢复');time.sleep(2);ns=dump('restored')
 assert '恢复失败' not in labels(ns),labels(ns)
 settings();find_click('学期信息',True);ns=dump('semester-before-restore17')
 fields=[n for n in ns if n.get('class')=='android.widget.EditText'];assert len(fields)==2,labels(ns)
 n=fields[1];x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')));adb('shell','input','tap',(x1+x2)//2,(y1+y2)//2)
 adb('shell','input','keyevent',123);adb('shell','input','keyevent',67);adb('shell','input','keyevent',67);text('17');back()
 ns=dump('semester-17');assert any(n.get('text')=='17' for n in ns),labels(ns);click(ns,'确定');ns=dump('term-restored')
 assert '17周' in labels(ns),labels(ns)
 home();print('PASS backup restore and original 17-week term restored',flush=True)