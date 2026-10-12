from pathlib import Path
import json, xlwt
root=Path('test/fixtures/v100_university')
manifest=json.loads((root/'expected.json').read_text(encoding='utf-8'))
manifest=[e for e in manifest if not e['file'].endswith('.xls')]
for source,file in [(manifest[0],'13_software_biff8.xls'),(manifest[1],'14_clinical_biff8.xls')]:
    w=xlwt.Workbook(encoding='utf-8');s=w.add_sheet('课程明细')
    h=['课程名称','教师','星期','开始节次','结束节次','周次','教室','开始时间','结束时间']
    wt=['1-16周(单周)','2-16周(双周)','1,3,5,8,10周','3-18周','9-12周','1-20周']
    style=xlwt.easyxf('font: name Microsoft YaHei; alignment: vert centre, wrap on;')
    for j,v in enumerate(h):s.write(0,j,v,style);s.col(j).width=25*256
    for i,c in enumerate(source['courses']):
        clock=lambda m:f'{m//60:02}:{m%60:02}'
        row=[c['name'],c['teacher'],c['day'],c['start'],c['end'],wt[i],c['room'],clock(c['time'][0]),clock(c['time'][1])]
        for j,v in enumerate(row):s.write(i+1,j,v,style)
        s.row(i+1).height=640
    w.save(str(root/file))
    manifest.append({'file':file,'description':'真正BIFF8格式大学课表，不是改后缀的xlsx','courses':source['courses']})
(root/'expected.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(len(manifest),'university workbooks ready')

