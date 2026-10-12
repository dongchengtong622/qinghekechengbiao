from pathlib import Path
import json
import xlwt
out=Path('test/fixtures/v09_generated')
manifest=json.loads((out/'expected.json').read_text(encoding='utf-8'))
courses=manifest[0]['courses']
# Genuine BIFF8, not OOXML renamed to .xls.
w=xlwt.Workbook(encoding='utf-8');s=w.add_sheet('课程明细')
headers=['课程名称','教师','星期','开始节次','结束节次','周次','教室','开始时间','结束时间']
week_text=['1-16周(单周)','1-16周(双周)','1,3,5,8,10周','1-16周']
for j,h in enumerate(headers):s.write(0,j,h)
for i,c in enumerate(courses):
    row=[c['name'],c['teacher'],c['day'],c['start'],c['end'],week_text[i],c['room'],f"{c['time'][0]//60:02}:{c['time'][0]%60:02}",f"{c['time'][1]//60:02}:{c['time'][1]%60:02}"]
    for j,v in enumerate(row):s.write(i+1,j,v)
w.save(str(out/'07_biff8_records.xls'))
manifest=[entry for entry in manifest if entry['file']!='07_biff8_records.xls']
manifest.append({'file':'07_biff8_records.xls','courses':courses})
(out/'expected.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')

