from pathlib import Path
import zipfile,json
root=Path(__file__).resolve().parents[2]
output=root/'交付安装包';output.mkdir(exist_ok=True)
files=[]
for folder,label in [('v101_diverse','新增3种标题与分段变化'),('v101_times','新增5种节长与连堂'),('v100_university','新增16种大学课表'),('v09_generated','既有结构回归'),('other_timetable_formats','既有专业课表')]:
 for p in (root/'test/fixtures'/folder).iterdir():
  if p.is_file() and p.suffix.lower() in ['.xls','.xlsx','.json','.md']:
   files.append((p,label+'/'+p.name))
files.append((root/'assets/templates/qinghe_timetable_template.xlsx','青禾课表导入模板.xlsx'))
notes='青禾课表 V1.0.1 Excel测试样本\n\n共24份专项模拟大学课表：22份xlsx、2份真正BIFF8 xls。另新增3份学校标题、分段周次与教师教室变化课表。本次新生成5份40/45/50分钟及三节连堂样本。8专业、合并、转置、多工作表、重复行、无时间、独立单节作息。全部为模拟数据。\n\n完整有效时间直接采用课表时间，不再选择旧作息；没有完整时间时才提示补用默认作息。导入前需正确填写学期总周数（新增样本为20周）和第一周日期。\n\n还附7份既有结构样本、6份既有专业样本及1份模板，共38个Excel文件。其中空表/说明样本用于验证拒绝错误文件，不能作为课程导入。\nexpected.json用于开发端逐字段核对。\n'
with zipfile.ZipFile(output/'V1.0.1大学课表Excel测试样本.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p,name in files:z.write(p,name)
 z.writestr('测试说明.txt',notes)
print('Excel files:',sum(p.suffix.lower() in ['.xls','.xlsx'] for p,_ in files))
print(output/'V1.0.1大学课表Excel测试样本.zip')
