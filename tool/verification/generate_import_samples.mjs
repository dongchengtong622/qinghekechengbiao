import fs from 'node:fs/promises';
import path from 'node:path';
import { Workbook, SpreadsheetFile } from '@oai/artifact-tool';
const out=path.resolve('test/fixtures/v09_generated');
await fs.mkdir(out,{recursive:true});
const expected=[];
const courses=[
 {name:'高等数学',teacher:'张明',day:1,start:1,end:2,weeks:[1,3,5,7,9,11,13,15],room:'明理楼A101',time:[480,575]},
 {name:'程序设计',teacher:'李青',day:2,start:3,end:4,weeks:[2,4,6,8,10,12,14,16],room:'实验楼B202',time:[605,700]},
 {name:'大学英语',teacher:'王芳',day:3,start:5,end:6,weeks:[1,3,5,8,10],room:'文科楼C303',time:[840,935]},
 {name:'数据结构',teacher:'陈林',day:5,start:7,end:8,weeks:[...Array(16)].map((_,i)=>i+1),room:'计算中心D404',time:[965,1060]},
];
const weekTexts=['1-16周(单周)','1-16周(双周)','1,3,5,8,10周','1-16周'];
function style(s,r){const q=s.getRange(r); q.format.font={name:'Microsoft YaHei',size:11};q.format.wrapText=true;q.format.verticalAlignment='center';q.format.columnWidth=22;q.format.rowHeight=28;q.format.borders={preset:'all',style:'thin',color:'#D8E2DC'};}
async function save(name,wb,expectedCourses){wb.recalculate();const blob=await SpreadsheetFile.exportXlsx(wb);await blob.save(path.join(out,name));expected.push({file:name,courses:expectedCourses});console.log(name,expectedCourses.length);}
for(const [file,english]of [['01_records_cn.xlsx',false],['02_records_en.xlsx',true]]){
 const w=Workbook.create(),s=w.worksheets.add('课程明细');
 const h=english?['Course','Teacher','Weekday','Start Period','End Period','Weeks','Room','Start Time','End Time']:['课程名称','教师','星期','开始节次','结束节次','周次','教室','开始时间','结束时间'];
 s.getRange('A1:I5').values=[h,...courses.map((c,i)=>[c.name,c.teacher,english?['','Mon','Tue','Wed','Thu','Fri'][c.day]:'周'+['','一','二','三','四','五'][c.day],c.start,c.end,weekTexts[i],c.room,`${Math.floor(c.time[0]/60)}:${String(c.time[0]%60).padStart(2,'0')}`,`${Math.floor(c.time[1]/60)}:${String(c.time[1]%60).padStart(2,'0')}`])];
 style(s,'A1:I5');s.getRange('A1:I1').format.fill='#D0EADB';await save(file,w,courses);
}
function details(c,i){return `${c.name}\n${weekTexts[i]}\n${c.teacher}\n${c.room}`;}
const groups=[[1,2,'08:00-09:35'],[3,4,'10:05-11:40'],[5,6,'14:00-15:35'],[7,8,'16:05-17:40']];
{
 const w=Workbook.create(),s=w.worksheets.add('周课表');s.getRange('A1:H1').merge();s.getRange('A1').values=[['2026年秋季教学课表（合并课程格）']];s.getRange('A2:H2').values=[['节次/时间','周一','周二','周三','周四','周五','周六','周日']];
 for(let i=0;i<8;i++){s.getRange(`A${i+3}`).values=[[`${i+1}节`]];}
 groups.forEach((g,i)=>{s.getRange(`A${3+i*2}:A${4+i*2}`).merge();s.getRange(`A${3+i*2}`).values=[[`${g[0]}-${g[1]}节\n${g[2]}`]];});
 courses.forEach((c,i)=>{const col=String.fromCharCode(65+c.day);s.getRange(`${col}${c.start+2}:${col}${c.end+2}`).merge();s.getRange(`${col}${c.start+2}`).values=[[details(c,i)]];});
 style(s,'A1:H10');s.getRange('A3:H10').format.rowHeight=52;await save('03_merged_grid.xlsx',w,courses);
}
{
 const w=Workbook.create(),s=w.worksheets.add('横向节次');s.getRange('A1:E1').values=[['星期','1-2节\n08:00-09:35','3-4节\n10:05-11:40','5-6节\n14:00-15:35','7-8节\n16:05-17:40']];
 for(let d=1;d<=7;d++)s.getRange(`A${d+1}`).values=[['周'+['','一','二','三','四','五','六','日'][d]]];
 courses.forEach((c,i)=>s.getRange(`${String.fromCharCode(66+(c.start-1)/2)}${c.day+1}`).values=[[details(c,i)]]);style(s,'A1:E8');s.getRange('A2:E8').format.rowHeight=92;await save('04_transposed_grid.xlsx',w,courses);
}
{
 const w=Workbook.create(),s=w.worksheets.add('课程一'),t=w.worksheets.add('课程二'),times=w.worksheets.add('统一作息'),note=w.worksheets.add('说明');
 const h=['课程名称','教师','星期','节次','周次','教室'];
 [s,t].forEach((tab,index)=>{tab.getRange('A1:F3').values=[h,...courses.slice(index*2,index*2+2).map((c,j)=>[c.name,c.teacher,c.day,`${c.start}-${c.end}`,weekTexts[index*2+j],c.room])];style(tab,'A1:F3');});
 times.getRange('A1:C5').values=[['节次','开始时间','结束时间'],...groups.map(g=>[`${g[0]}-${g[1]}节`,g[2].split('-')[0],g[2].split('-')[1]])];style(times,'A1:C5');note.getRange('A1').values=[['说明页不是课程，不应当被当作课程导入。']];await save('05_multi_sheet_with_times.xlsx',w,courses);
}
{
 const w=Workbook.create(),s=w.worksheets.add('空表'),n=w.worksheets.add('只有说明');s.getRange('A1').values=[['']];n.getRange('A1').values=[['这不是课表。']];await save('06_empty_and_notes.xlsx',w,[]);
}
await fs.writeFile(path.join(out,'expected.json'),JSON.stringify(expected,null,2));
// A bounded render checks the authored merged Excel workbook.
const merged=await SpreadsheetFile.importXlsx(await (await import('@oai/artifact-tool')).FileBlob.load(path.join(out,'03_merged_grid.xlsx')));
console.log((await merged.inspect({kind:'sheet',include:'id,name',maxChars:1000})).ndjson);
try {const png=await merged.render({sheetName:'周课表',range:'A1:H10',scale:1,format:'png'});await fs.writeFile(path.join(out,'excel_preview.png'),new Uint8Array(await png.arrayBuffer()));}catch(e){console.log('render limitation:',e.message);}

