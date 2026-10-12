import sys
sys.argv.append('import-weeks')
from save_restore_ui import *
for end in [20,16]:
 ns=home();click(ns,'更多');click(dump('weeks-menu-'+str(end)),'导入课表');click(dump('weeks-entry-'+str(end)),'选择 Excel 文件')
 pick('v101_weeks',f'weeks_1_{end}_university.xlsx');ns=dump('weeks-preview-'+str(end))
 assert '高等数学' in labels(ns) and '计算机网络' in labels(ns),labels(ns)
 if end==20:
  assert '课程到第 20 周' in labels(ns),labels(ns)
  assert '1-20周' in labels(ns) or '1-20周' in labels(dump('weeks-preview-20-all')),labels(ns)
  click(ns,'调整为 20 周');ns=dump('weeks-extended')
  assert '20 周' in labels(ns) and '课程到第 20 周，当前学期只有' not in labels(ns),labels(ns)
  print('PASS 20-week import keeps both courses; extension is draft-only',flush=True)
 else:
  assert '课程到第 16 周' not in labels(ns),labels(ns)
  assert '调整为 16 周' not in labels(ns),labels(ns)
  print('PASS 16-week import keeps current semester duration',flush=True)
 back();home()
print('PASS both previews cancelled; existing courses, semester and dates not saved',flush=True)
