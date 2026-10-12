import fs from 'node:fs/promises';
import path from 'node:path';
import {Workbook,SpreadsheetFile} from '@oai/artifact-tool';
const out=path.resolve('test/fixtures/v101_diverse'),qa=path.resolve('docs/development/v1.0.1/excel-sample-previews');
await fs.mkdir(out,{recursive:true});await fs.mkdir(qa,{recursive:true});
const weekdays=['','周一','周二','周三','周四','周五','周六','周日'];
const rows=[
 ['高等数学A','张明',1,1,2,'1-8周','理科楼A101',480,580],
 ['高等数学A','李青',1,1,2,'9-16周','理科楼B201',480,580],
 ['大学英语','周芸',2,3,4,'1-16周(单周)','外语楼C301',610,710],
 ['大学英语','王芳',2,3,4,'2-16周(双周)','外语楼C302',610,710],
 ['程序设计实验','陈林',3,5,6,'1-6周','计算中心机房1',840,940],
 ['程序设计实验','陈林',3,5,6,'7-12周','计算中心机房2',840,940],
 ['程序设计实验','赵宁',3,5,6,'13-16周','计算中心机房3',840,940],
 ['机械设计','何新',4,7,8,'1,3,5,8,10,14周','工科楼D401',970,1070],
 ['医学伦理学','林澄',5,9,10,'3-14周','医学院E501',1110,1210],
 ['艺术史','刘岚',6,1,2,'9-12周','艺术楼F202',480,580],
 ['创新创业实践','郑云',7,5,6,'1-4周','创业中心203',840,940],
 ['创新创业实践','郑云',7,5,6,'5-8周','线上教学平台',840,940],
 ];
const clock=m=>`${String(Math.floor(m/60)).padStart(2,'0')}:${String(m%60).padStart(2,'0')}`;
const detail=r=>`${r[0]}\n${r[5]}\n${r[1]}\n${r[6]}`;
const headers=['课程名称','教师','星期','开始节次','结束节次','周次','教室','开始时间','结束时间'];
const expected=[];
function style(s,r){s.showGridLines=false;s.getRange(r).format.columnWidth=22;s.getRange(r).format.rowHeight=38;s.getRange(r).format.wrapText=true;s.getRange(r).format.horizontalAlignment='center';s.getRange(r).format.verticalAlignment='center';}
function titles(s,last){s.getRange(`A1:${last}1`).merge();s.getRange('A1').values=[['青禾示范大学（模拟） 本科学生课程表']];s.getRange(`A2:${last}2`).merge();s.getRange('A2').values=[['2026秋季学期 · 软件工程2026级 · 分段授课与单双周安排']];s.getRange(`A1:${last}2`).format.fill='#D0EADB';s.getRange(`A1:${last}2`).format.font.bold=true;}
async function save(file,w,s,range,description){await(await SpreadsheetFile.exportXlsx(w)).save(path.join(out,file));const png=await w.render({sheetName:s.name,range,scale:1,format:'png'});await fs.writeFile(path.join(qa,file+'.png'),new Uint8Array(await png.arrayBuffer()));expected.push({file,description,rows});console.log(file);}
for(const [file,offset,description] of [['01_school_title_records.xlsx',3,'学校及学期标题在第一二行，第三行才是字段'],['02_notes_then_records.xlsx',5,'学校标题、学期标题、说明及空行后才出现字段']]){
 const w=Workbook.create(),s=w.worksheets.add('课程安排');titles(s,'I');if(offset===5)s.getRange('A3:I3').merge(),s.getRange('A3').values=[['说明：教师及教室随周次变化，以本表各段安排为准。']];
 s.getRange(`A${offset}:I${offset+rows.length}`).values=[headers,...rows.map(r=>[r[0],r[1],weekdays[r[2]],r[3],r[4],r[5],r[6],clock(r[7]),clock(r[8])])];style(s,`A1:I${offset+rows.length}`);await save(file,w,s,`A1:I${offset+rows.length}`,description);
}
{
 const w=Workbook.create(),s=w.worksheets.add('周课表');titles(s,'H');s.getRange('A3:H3').values=[['节次及时间',...weekdays.slice(1)]];
 const slots=[[1,2,480,580],[3,4,610,710],[5,6,840,940],[7,8,970,1070],[9,10,1110,1210]];
 for(let i=0;i<slots.length;i++){const [first,last,start,end]=slots[i];const row=i+4;s.getRange(`A${row}`).values=[[`${first}-${last}节\n${clock(start)}-${clock(end)}`]];for(let d=1;d<=7;d++){const rs=rows.filter(r=>r[2]===d&&r[3]===first);if(rs.length)s.getRange(`${String.fromCharCode(65+d)}${row}`).values=[[rs.map(detail).join('\n\n')]];}}
 style(s,'A1:H8');s.getRange('A4:H8').format.rowHeight=225;await save('03_multi_block_week_grid.xlsx',w,s,'A1:H8','顶部学校标题，同一课程格包含分段周次、多教师、多教室');
}
await fs.writeFile(path.join(out,'expected.json'),JSON.stringify(expected,null,2));
await fs.writeFile(path.join(out,'样本说明.md'),'全部为大学课表模拟数据。含12条授课段：前后半学期教师变化、单双周教师教室变化、同一教师分周次更换机房、短期课程、离散周及线上课堂。每周逐字段核对，不能以课程名去重。\n');
