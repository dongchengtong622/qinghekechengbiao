from device_ui import *
manifest=[]
for raw in json.loads((ROOT/'test/fixtures/v101_diverse/expected.json').read_text(encoding='utf-8')):
 manifest.append({'file':raw['file'],'folder':'v101_diverse','courses':[{'name':r[0],'teacher':r[1],'room':r[6],'time':[r[7],r[8]]} for r in raw['rows']]})
for c in json.loads((ROOT/'test/fixtures/v101_times/expected.json').read_text(encoding='utf-8')):
 manifest.append({'file':c['file'],'folder':'v101_times','lesson':c['lesson'],'gap':c['gap'],'courses':[{'name':c['name'],'teacher':c['teacher'],'room':'综合教学楼A301','time':[c['start'],c['end']]}]})
results=json.loads((OUT/'v101-samples-ui-results.json').read_text(encoding='utf-8')) if (OUT/'v101-samples-ui-results.json').exists() else []
ns=dump('start-home')
if '确认导入' in labels(ns):
 back();ns=dump('start-import')
if '选择 Excel 文件' not in labels(ns):
 click(ns,'更多');ns=dump('home-menu');click(ns,'导入课表')
for sample in manifest:
 if any(r['file']==sample['file'] for r in results):continue
 folder=sample['folder'];file=sample['file'];ns=dump('entry-'+file);click(ns,'选择 Excel 文件')
 ns=dump('file-picker-'+file)
 assert '核对学期信息' not in labels(ns), 'Unexpected automatic semester dialog'
 ns=dump('picker-'+file)
 if not any(n.get('text')==file for n in ns):
  click(ns,'显示根目录');ns=dump('roots-'+file);click(ns,'V2136A')
  for step in range(12):
   ns=dump('storage-'+file+'-'+str(step))
   if any(n.get('text')=='Download' for n in ns):click(ns,'Download');break
   adb('shell','input','swipe',800,1800,800,1200,650)
  for reset in range(20):adb('shell','input','swipe',800,800,800,2150,220)
  for step in range(12):
   ns=dump('downloads-'+file+'-'+str(step))
   if any(n.get('text')==folder for n in ns):click(ns,folder);break
   adb('shell','input','swipe',800,1800,800,1200,650)
  ns=dump('folder-'+file)
 for reset in range(5):adb('shell','input','swipe',800,800,800,2150,220)
 ns=dump('folder-top-'+file)
 for attempt in range(12):
  if any(n.get('text')==file for n in ns):break
  adb('shell','input','swipe',700,2100,700,800,350);time.sleep(.4);ns=dump('picker-'+file+'-'+str(attempt))
 else:raise AssertionError('File unavailable: '+file+'\n'+labels(ns))
 target=next(n for n in ns if n.get('text')==file)
 y1,y2=map(int,re.findall(r'\d+',target.get('bounds'))[1::2])
 if y1<230:
  adb('shell','input','swipe',800,850,800,1300,300);ns=dump('expose-'+file)
 elif y2>2240:
  adb('shell','input','swipe',800,1600,800,1100,300);ns=dump('expose-'+file)
 click(ns,file);time.sleep(1);ns=dump('selected-'+file)
 if file.startswith(('11_','16_')):
  print('MULTISHEET',file,flush=True)
  for node in ns:
   if node.get('checkable')=='true' and node.get('enabled')=='true' and node.get('checked')=='false':
    click(ns,node.get('content-desc') or node.get('text'))
  ns=dump('sheets-checked-'+file)
  for label in ['导入所选工作表','继续','下一步','预览导入','预览所选工作表','合并所选工作表']:
   if any(label==n.get('content-desc') or label==n.get('text') for n in ns):click(ns,label);break
  else:raise AssertionError('Need inspect multi sheet button\n'+labels(ns))
  ns=dump('merged-'+file)
 combined=labels(ns)
 hasTimes=all(c['time'] is not None for c in sample['courses'])
 if hasTimes:
  assert '时间冲突' not in combined and '已识别课表时间' not in combined and '需补用默认作息' not in combined,(file,combined)
 else:assert '默认作息' in combined,(file,combined)
 if '确认导入' not in combined:raise AssertionError('No preview for '+file+'\n'+combined)
 if folder=='v101_times':assert '1 门课程' in combined,(file,combined)
 for scroll in range(12):
  if all(all(c[field] in combined for field in ['name','teacher','room']) for c in sample['courses']):break
  adb('shell','input','swipe',760,2180,760,850,400);time.sleep(.4)
  combined+='\n'+labels(dump('preview-'+file+'-'+str(scroll)))
 missing=[(c['name'],field,c[field]) for c in sample['courses'] for field in ['name','teacher','room'] if c[field] not in combined]
 assert not missing,(file,missing)
 if hasTimes:
  for c in sample['courses']:
   expected=f"{c['time'][0]//60:02}:{c['time'][0]%60:02}–{c['time'][1]//60:02}:{c['time'][1]%60:02}"
   assert expected in combined,(file,c['name'],expected)
 else:
  click(dump('default-before-confirm'), '导入课表')
  ns=dump('default-confirmation')
  assert '确认使用默认作息' in labels(ns),labels(ns)
  click(ns,'返回核对')
 if folder=='v101_times' and __import__('os').environ.get('QH_PREVIEW_ONLY')!='1':
  for _ in range(3):adb('shell','input','swipe',800,2050,800,900,300)
  click(dump('split-entry-'+file),'导入课表');ns=dump('split-'+file)
  assert '确认节次时间拆分' in labels(ns),labels(ns)
  click(ns,'单节时长',contains=True);ns=dump('duration-menu-'+file);click(ns,str(sample['lesson'])+' 分钟');ns=dump('split-suggestion-'+file)
  if sample['gap'] is None:assert '手动' in labels(ns),labels(ns)
  else:assert str(sample['gap']) in labels(ns),labels(ns)
  back()
 results.append({'file':file,'courseCount':len(sample['courses']),'courseTeacherRoomVerified':True,'previewOpened':True,'savedToUserSemester':False,'excelTimesUsedWithoutPrompt':hasTimes,'defaultConfirmationChecked':not hasTimes})
 (OUT/'v101-samples-ui-results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
 print('PASS',file,len(sample['courses']),'courses; teacher/room visible; preview cancelled',flush=True)
 back()
print('PASS ALL',len(results),'real-device Excel previews',flush=True)





