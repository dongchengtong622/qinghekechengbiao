import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/cdcas_kingo_importer.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  const importer = CdcasKingoImporter();

  test('parses courses, merged sessions, sections, and week patterns', () {
    final fixture = File(
      'test/fixtures/cdcas_timetable.html',
    ).readAsStringSync();

    final preview = importer.parse(fixture);

    expect(preview.semester.id, 'cdcas-2026-2027-1');
    expect(preview.semester.firstWeekStart, DateTime(2026, 9, 7));
    expect(preview.semester.totalWeeks, 18);
    expect(preview.courses, hasLength(3));

    final math = preview.courses.singleWhere((c) => c.name == '高等数学');
    expect(math.source, CourseSource.cdcasKingo);
    expect(math.externalId, isNotEmpty);
    expect(math.sessions, hasLength(2));
    expect(math.sessions.first.weekday, DateTime.monday);
    expect(math.sessions.first.startSection, 1);
    expect(math.sessions.first.endSection, 2);
    expect(math.sessions.first.pattern, WeekPattern.oddWeeks);
    expect(math.sessions.first.room, 'A302');

    final english = preview.courses.singleWhere((c) => c.name == '大学英语');
    expect(english.sessions.single.pattern, WeekPattern.evenWeeks);

    final design = preview.courses.singleWhere((c) => c.name == '设计基础');
    expect(design.sessions.single.room, isEmpty);
    expect(design.sessions.single.pattern, WeekPattern.everyWeek);
  });

  test('rejects a login page without a timetable', () {
    expect(
      () => importer.parse('<html><body>帐号登录 密码 验证码</body></html>'),
      throwsA(
        isA<TimetableImportException>().having(
          (error) => error.code,
          'code',
          TimetableImportErrorCode.notTimetablePage,
        ),
      ),
    );
  });

  test('rejects a timetable table containing no courses', () {
    const html = '''
      <table><tr><th>节次</th><th>星期一</th><th>星期二</th>
      <th>星期三</th><th>星期四</th><th>星期五</th></tr></table>
    ''';

    expect(
      () => importer.parse(html),
      throwsA(
        isA<TimetableImportException>().having(
          (error) => error.code,
          'code',
          TimetableImportErrorCode.emptyTimetable,
        ),
      ),
    );
  });

  test('rejects a timetable whose semester calendar is not verifiable', () {
    const html = '''
      <html><body><h1>2026-2027学年第1学期学生课表</h1>
      <table><tr><th>节次</th><th>星期一</th><th>星期二</th>
      <th>星期三</th><th>星期四</th><th>星期五</th></tr>
      <tr><td>第1-2节</td><td>高等数学<br>1-18周<br>陈老师</td>
      <td></td><td></td><td></td><td></td></tr></table></body></html>
    ''';

    expect(
      () => importer.parse(html),
      throwsA(
        isA<TimetableImportException>().having(
          (error) => error.code,
          'code',
          TimetableImportErrorCode.invalidSemester,
        ),
      ),
    );
  });

  test('creates semester-scoped local IDs for the same course', () {
    String html(String term, String start) =>
        '''
      <html><body><h1>2026-2027学年第$term学期学生课表</h1>
      <table data-first-week-start="$start" data-total-weeks="18">
      <tr><th>节次</th><th>星期一</th><th>星期二</th>
      <th>星期三</th><th>星期四</th><th>星期五</th></tr>
      <tr><td>第1-2节</td><td>高等数学<br>1-18周<br>陈老师</td>
      <td></td><td></td><td></td><td></td></tr></table></body></html>
    ''';

    final autumn = importer.parse(html('1', '2026-09-07')).courses.single;
    final spring = importer.parse(html('2', '2027-02-22')).courses.single;

    expect(autumn.externalId, spring.externalId);
    expect(autumn.id, isNot(spring.id));
  });

  test('accounts for rowspans when mapping later cells to weekdays', () {
    const html = '''
      <html><body><h1>2026-2027学年第1学期学生课表</h1>
      <table data-first-week-start="2026-09-07" data-total-weeks="18">
      <tr><th>节次</th><th>星期一</th><th>星期二</th><th>星期三</th>
      <th>星期四</th><th>星期五</th></tr>
      <tr><td>第1-2节</td><td rowspan="2">高等数学<br>1-18周<br>陈老师</td>
      <td></td><td></td><td></td><td></td></tr>
      <tr><td>第3-4节</td><td>大学英语<br>1-18周<br>B201<br>李老师</td>
      <td></td><td></td><td></td></tr>
      </table></body></html>
    ''';

    final preview = importer.parse(html);
    final english = preview.courses.singleWhere((item) => item.name == '大学英语');

    expect(english.sessions.single.weekday, DateTime.tuesday);
  });

  test(
    'warns instead of silently importing an ambiguous multi-course cell',
    () {
      const html = '''
      <html><body><h1>2026-2027学年第1学期学生课表</h1>
      <table data-first-week-start="2026-09-07" data-total-weeks="18">
      <tr><th>节次</th><th>星期一</th><th>星期二</th><th>星期三</th>
      <th>星期四</th><th>星期五</th></tr>
      <tr><td>第1-2节</td><td>高等数学<br>1-18周<br>陈老师<br>
      大学英语<br>1-18周<br>李老师</td><td>设计基础<br>1-18周<br>王老师</td>
      <td></td><td></td><td></td></tr>
      </table></body></html>
    ''';

      final preview = importer.parse(html);

      expect(preview.courses.map((item) => item.name), isNot(contains('高等数学')));
      expect(preview.warnings, isNotEmpty);
    },
  );
}
