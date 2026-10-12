import fs from 'node:fs/promises';
import path from 'node:path';
import { Workbook, SpreadsheetFile } from '@oai/artifact-tool';
const out=path.resolve('test/fixtures/v100_university');
const qa=path.resolve('docs/development/v1.0.1/excel-sample-previews');
await fs.mkdir(out,{recursive:true}); await fs.mkdir(qa,{recursive:true});
const expected=[];
const profiles=[
 ['software','软件工程',['高等数学A','面向对象程序设计','数据结构实验','计算机组成原理','软件工程导论','大学英语']],
 ['clinical','临床医学',['人体解剖学','生理学','生物化学实验','医学免疫学','病理学','医学伦理学']],
 ['mechanical','机械工程',['工程制图','理论力学','机械设计基础','机械制造实验','电工电子技术','线性代数']],
 ['business','工商管理',['微观经济学','管理学原理','财务管理','市场营销','会计学基础','统计学']],
 ['law','法学',['宪法学','民法总论','刑法学','法律逻辑学','法学导论','行政法学']],
 ['design','视觉传达设计',['设计素描','色彩构成','版式设计','字体设计','数字媒体实验','艺术史']],
 ['foreign','英语专业',['综合英语','英语听力','英语口语','英语阅读','英语写作','第二外语']],
 ['landscape','园林技术',['园林植物学','园林规划设计','景观生态学','测量学实验','花卉学','土壤肥料学']],
];
const times=[[480,575],[605,700],[840,935],[965,1060],[1110,1205],[1225,1320]];
const weekTexts=['1-16周(单周)','2-16周(双周)','1,3,5,8,10周','3-18周','9-12周','1-20周'];
const weekSets=[[1,3,5,7,9,11,13,15],[2,4,6,8,10,12,14,16],[1,3,5,8,10],Array.from({length:16},(_,i)=>i+3),[9,10,11,12],Array.from({length:20},(_,i)=>i+1)];
const teachers=['张明','李青','王芳','陈林','赵宁','周芸'];
const days=['','周一','周二','周三','周四','周五','周六','周日'];
const headers=['课程名称','教师','星期','开始节次','结束节次','周次','教室','开始时间','结束时间'];
const english=['Course','Teacher','Weekday','Start Period','End Period','Weeks','Room','Start Time','End Time'];
const clock=m=>`${Math.floor(m/60).toString().padStart(2,'0')}:${(m%60).toString().padStart(2,'0')}`;
function coursesFor(p,index){return p[2].map((name,i)=>({name,teacher:teachers[i],day:i===5?7:i+1,start:i*2+1,end:i*2+2,weeks:weekSets[i],room:i===5?'线上教学平台':`${p[1]}教学楼${String.fromCharCode(65+index)}${101+i}`,time:times[i]}));}
function style(s,range){s.showGridLines=false;const r=s.getRange(range);r.format.font={name:'Microsoft YaHei',size:11};r.format.wrapText=true;r.format.verticalAlignment='center';r.format.columnWidth=22;r.format.rowHeight=32;}
function records(s,courses,eng=false){const rows=[eng?english:headers,...courses.map((c,i)=>[c.name,c.teacher,eng?['','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][c.day]:days[c.day],c.start,c.end,weekTexts[i],c.room,clock(c.time[0]),clock(c.time[1])])];s.getRange(`A1:I${rows.length}`).values=rows;style(s,`A1:I${rows.length}`);s.getRange('A1:I1').format.fill='#D0EADB';s.getRange('A1:I1').format.font.bold=true;}
async function save(file,wb,courses,description,ranges){wb.recalculate();console.log((await wb.inspect({kind:'sheet',include:'id,name',maxChars:700})).ndjson);await (await SpreadsheetFile.exportXlsx(wb)).save(path.join(out,file));expected.push({file,description,courses});for(const [sheetName,range] of ranges){const png=await wb.render({sheetName,range,scale:1,format:'png'});await fs.writeFile(path.join(qa,`${file.replace('.xlsx','')}-${sheetName}.png`),new Uint8Array(await png.arrayBuffer()));}console.log(file,courses.length);}
for(let n=0;n<profiles.length;n++){const p=profiles[n],courses=coursesFor(p,n),w=Workbook.create(),s=w.worksheets.add(p[1]);records(s,courses,n===6);await save(`${String(n+1).padStart(2,'0')}_${p[0]}_records.xlsx`,w,courses,`${p[1]}大学课表；含单双周、离散周、短学期、周日、晚间、线上课程${n===6?'；英文表头':''}`,[[p[1],'A1:I7']]);}
const cs=coursesFor(profiles[0],0).slice(0,4);
function detail(c,i){return `${c.name}\n${weekTexts[i]}\n${c.teacher}\n${c.room}`;}
{
 const w=Workbook.create(),s=w.worksheets.add('周课表');s.getRange('A1:H1').merge();s.getRange('A1').values=[['2026秋季软件工程模拟课表']];s.getRange('A2:H2').values=[['节次及时间',...days.slice(1)]];
 for(let i=0;i<4;i++){s.getRange(`A${i*2+3}:A${i*2+4}`).merge();s.getRange(`A${i*2+3}`).values=[[`${i*2+1}-${i*2+2}节\n${clock(times[i][0])}-${clock(times[i][1])}`]];}
 cs.forEach((c,i)=>{const col=String.fromCharCode(65+c.day);s.getRange(`${col}${c.start+2}:${col}${c.end+2}`).merge();s.getRange(`${col}${c.start+2}`).values=[[detail(c,i)]];});style(s,'A1:H10');s.getRange('A3:H10').format.rowHeight=58;await save('09_merged_week_grid.xlsx',w,cs,'合并课程格、合并节次时间格的大学周课表',[['周课表','A1:H10']]);
}
{
 const w=Workbook.create(),s=w.worksheets.add('转置周表');s.getRange('A1:E1').values=[['星期',...times.slice(0,4).map((t,i)=>`${i*2+1}-${i*2+2}节\n${clock(t[0])}-${clock(t[1])}`)]];days.slice(1).forEach((d,i)=>s.getRange(`A${i+2}`).values=[[d]]);cs.forEach((c,i)=>s.getRange(`${String.fromCharCode(66+i)}${c.day+1}`).values=[[detail(c,i)]]);style(s,'A1:E8');s.getRange('A2:E8').format.rowHeight=96;await save('10_transposed_week_grid.xlsx',w,cs,'星期纵向排列，节次横向排列的转置周课表',[['转置周表','A1:E8']]);
}
{
 const w=Workbook.create(),s=w.worksheets.add('基础课程'),t=w.worksheets.add('专业课程'),note=w.worksheets.add('教务说明');records(s,cs.slice(0,2));records(t,cs.slice(2).map((c,i)=>({...c,weeks:weekSets[i]}))); // write independent weeks explicitly below
 const second=cs.slice(2);second.forEach((c,i)=>t.getRange(`F${i+2}`).values=[[weekTexts[i+2]]]);
 note.getRange('A1').values=[['模拟教务导出：说明页不能作为课程导入。']];style(note,'A1');note.getRange('A1').format.columnWidth=65;
 await save('11_multi_sheet_university.xlsx',w,cs,'基础课和专业课分工作表，并有非课程说明页',[['基础课程','A1:I3'],['专业课程','A1:I3'],['教务说明','A1']]);
}
{
 const w=Workbook.create(),s=w.worksheets.add('重复导出');records(s,cs);s.getRange('A6:I6').values=[[cs[0].name,cs[0].teacher,days[cs[0].day],cs[0].start,cs[0].end,weekTexts[0],cs[0].room,clock(cs[0].time[0]),clock(cs[0].time[1])]];style(s,'A1:I6');await save('12_duplicate_record_export.xlsx',w,cs,'教务导出重复行；不得产生重复课程',[['重复导出','A1:I6']]);
}
{
 const w=Workbook.create(),s=w.worksheets.add('无时间课表'),courses=coursesFor(profiles[0],0);
 records(s,courses);s.getRange('H1:I7').clear({applyTo:'contents'});
 await save('15_university_without_times.xlsx',w,courses.map(c=>({...c,time:null})),'只有节次和周次，没有时间；应提示补用默认作息',[['无时间课表','A1:G7']]);
}
{
 const w=Workbook.create(),s=w.worksheets.add('课程明细'),t=w.worksheets.add('统一作息'),c=coursesFor(profiles[0],0)[2];
 records(s,[c]);s.getRange('F2').values=[[weekTexts[2]]];s.getRange('H1:I2').clear({applyTo:'contents'});
 t.getRange('A1:C3').values=[['节次','开始时间','结束时间'],[5,'14:00','14:45'],[6,'14:50','15:35']];style(t,'A1:C3');
 await save('16_individual_section_times.xlsx',w,[c],'课程5-6节，独立作息工作表给出第5和第6节时间；必须优先于旧整段作息',[['课程明细','A1:G2'],['统一作息','A1:C3']]);
}
await fs.writeFile(path.join(out,'expected.json'),JSON.stringify(expected,null,2));
await fs.writeFile(path.join(out,'样本说明.md'),'# 大学课表模拟样本\n\n全部课程、教师和教室均为模拟数据，不代表任何大学实际排课。\n每个文件的字段预期保存于 expected.json，用于精确比对课程、教师、星期、节次、教室、周次和时间。\n\n'+expected.map(e=>`- ${e.file}：${e.description}`).join('\n')+'\n');


