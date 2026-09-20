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
}
