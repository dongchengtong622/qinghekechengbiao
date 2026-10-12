import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/excel_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  const importer = ExcelTimetableImporter();

  test('parses a Chinese-header timetable worksheet', () {
    final preview = importer.parseRows([
      ['学期', '2026-2027学年第1学期'],
      ['第一周日期', '2026-09-07'],
      ['总周数', 18],
      <Object?>[],
      [
        '课程名称',
        '教师',
        '星期',
        '开始节次',
        '结束节次',
        '开始周',
        '结束周',
        '单双周',
        '教室',
        '开始时间',
        '结束时间',
      ],
      ['高等数学', '陈老师', '星期一', 1, 2, 1, 18, '每周', 'A302', '09:40', '11:15'],
      ['高等数学', '陈老师', '周三', 3, 4, 1, 18, '单周', 'B201', '', ''],
    ]);

    expect(preview.semester.id, 'excel-2026-2027-1');
    expect(preview.semester.firstWeekStart, DateTime(2026, 9, 7));
    expect(preview.courses, hasLength(1));
    expect(preview.courses.single.sessions, hasLength(2));
    expect(preview.courses.single.sessions.first.startMinute, 580);
    expect(preview.courses.single.sessions.first.endMinute, 675);
    expect(
      preview.courses.single.sessions.first.timeSource,
      CourseTimeSource.imported,
    );
    expect(preview.courses.single.sessions.last.weekday, DateTime.wednesday);
    expect(preview.courses.single.sessions.last.pattern, WeekPattern.oddWeeks);
  });

  test('reports missing required columns without creating a preview', () {
    expect(
      () => importer.parseRows([
        ['学期', '2026-2027学年第1学期'],
        ['第一周日期', '2026-09-07'],
        ['课程名称', '教师'],
        ['高等数学', '陈老师'],
      ]),
      throwsA(
        isA<ExcelImportException>().having(
          (error) => error.message,
          'message',
          contains('星期'),
        ),
      ),
    );
  });

  test('accepts common aliases and keeps valid rows around a warning', () {
    final preview = importer.parseRows([
      ['学期', '2026-2027学年第1学期'],
      ['第一周日期', '2026-09-07'],
      ['总周数', 18],
      <Object?>[],
      ['课程', '任课教师', '上课星期', '上课节次', '上课周次', '上课地点'],
      ['景观设计', '李老师', '星期一', '第1-2节', '1-18周', 'A302'],
      ['无效课程', '王老师', '星期九', '第3-4节', '1-18周', 'A303'],
      ['景观设计', '李老师', '星期三', '第3-4节', '1,3,5周', 'B201'],
    ]);

    expect(preview.courses, hasLength(1));
    expect(preview.courses.single.sessions, hasLength(4));
    expect(
      preview.courses.single.sessions.map((session) => session.startWeek),
      [1, 1, 3, 5],
    );
    expect(preview.warnings, hasLength(1));
    expect(preview.warnings.single, contains('第 7 行'));
    expect(preview.warnings.single, contains('无效课程'));
  });

  test('selects timetable sheet from the real xlsx fixture', () {
    final bytes = File(
      'test/fixtures/qinghe_timetable_import_template.xlsx',
    ).readAsBytesSync();

    final preview = importer.parseBytes(bytes);

    expect(preview.semester.name, '2026-2027学年第1学期');
    expect(preview.semester.firstWeekStart, DateTime(2026, 8, 31));
    expect(preview.semester.totalWeeks, 16);
    expect(preview.courses, hasLength(7));
    expect(
      preview.courses
          .singleWhere((course) => course.name == '居住区景观规划设计综合实训')
          .sessions
          .any((session) => session.pattern == WeekPattern.oddWeeks),
      isTrue,
    );
  });
}
