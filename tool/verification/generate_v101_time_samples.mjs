import fs from 'node:fs/promises';
import path from 'node:path';
import {Workbook,SpreadsheetFile} from '@oai/artifact-tool';
const out=path.resolve('test/fixtures/v101_times'),qa=path.resolve('docs/development/v1.0.1/excel-sample-previews');
await fs.mkdir(out,{recursive:true});await fs.mkdir(qa,{recursive:true});
const cases=[
 {file:'01_45min_lecture.xlsx',name:'高等数学',teacher:'张明',day:1,first:1,last:2,start:480,end:580,lesson:45,gap:10},
 {file:'02_40min_seminar.xlsx',name:'法学研讨',teacher:'李青',day:2,first:5,last:6,start:840,end:940,lesson:40,gap:20},
 {file:'03_50min_evening.xlsx',name:'设计工作坊',teacher:'王芳',day:3,first:9,last:10,start:1110,end:1220,lesson:50,gap:10},
 {file:'04_three_period_lab.xlsx',name:'大学物理实验',teacher:'陈林',day:4,first:1,last:3,start:480,end:625,lesson:45,gap:5},
 {file:'05_unequal_break_review.xlsx',name:'医学综合实验',teacher:'赵宁',day:5,first:1,last:3,start:480,end:624,lesson:45,gap:null},
];
const clock=m=>`${String(Math.floor(m/60)).padStart(2,'0')}:${String(m%60).padStart(2,'0')}`;
for(const c of cases){
 const w=Workbook.create(),s=w.worksheets.add('大学课程明细');
 s.getRange('A1:I2').values=[['课程名称','教师','星期','开始节次','结束节次','周次','教室','开始时间','结束时间'],[c.name,c.teacher,['','周一','周二','周三','周四','周五'][c.day],c.first,c.last,'1-16周','综合教学楼A301',clock(c.start),clock(c.end)]];
 s.showGridLines=false;s.getRange('A1:I2').format.horizontalAlignment='center';s.getRange('A1:I2').format.columnWidth=20;s.getRange('A1:I2').format.rowHeight=38;s.getRange('A1:I2').format.wrapText=true;s.getRange('A1:I1').format.fill='#D0EADB';s.getRange('A1:I1').format.font.bold=true;
 await (await SpreadsheetFile.exportXlsx(w)).save(path.join(out,c.file));
 const png=await w.render({sheetName:s.name,range:'A1:I2',scale:1,format:'png'});
 await fs.writeFile(path.join(qa,c.file+'.png'),new Uint8Array(await png.arrayBuffer()));
 console.log(c.file);
}
await fs.writeFile(path.join(out,'expected.json'),JSON.stringify(cases,null,2));
