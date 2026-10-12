import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/data/sample_schedule.dart';
import 'package:qinghe_timetable/features/timetable/data/smart_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/data/excel_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/presentation/timetable_page.dart';

final term = Semester(
  id: 's',
  name: 'term',
  firstWeekStart: DateTime(2026, 8, 31),
  totalWeeks: 18,
);
const rowHtml =
    '<table><tr><th>课程名称</th><th>教师</th><th>星期</th><th>节次</th><th>周次</th><th>教室</th></tr><tr><td>线性代数</td><td>张老师</td><td>星期三</td><td>3-4节</td><td>1-10周</td><td>A101</td></tr></table>';
void main() {
  test(
    'empty file and downloaded webpage have useful non-encryption errors',
    () {
      for (final item in [
        (Uint8List(0), '文件为空'),
        (
          Uint8List.fromList(utf8.encode('<html><body>请登录</body></html>')),
          '没有表格',
        ),
      ]) {
        expect(
          () => const SmartTimetableImporter().parseWorkbook(item.$1, term),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(item.$2),
            ),
          ),
        );
      }
    },
  );
  test('HTML nested course detail table retains outer course columns', () {
    final html = rowHtml.replaceFirst(
      '<td>线性代数</td>',
      '<td><table><tr><td>线性代数</td></tr></table></td>',
    );
    final result = const SmartTimetableImporter().parseExcel(
      Uint8List.fromList(utf8.encode(html)),
      term,
    );
    expect(result.courses.single.name, '线性代数');
    expect(result.courses.single.teacher, '张老师');
    expect(result.courses.single.sessions.single.weekday, 3);
    expect(result.courses.single.sessions.single.room, 'A101');
  });
  test('HTML single-cell layout wrapper does not replace actual table', () {
    final html = '<table><tr><td>大学课表$rowHtml</td></tr></table>';
    final result = const SmartTimetableImporter().parseExcel(
      Uint8List.fromList(utf8.encode(html)),
      term,
    );
    expect(result.courses.single.name, '线性代数');
  });
  for (final weeks in [1, 10, 16, 30, 60]) {
    test(
      'first setup accepts $weeks weeks without sample constraints',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final repo = CourseRepository(db);
        try {
          await repo.seedIfEmpty();
          expect(await repo.minimumSemesterWeeks(sampleSemester.id), 1);
          await repo.saveSemester(
            Semester(
              id: sampleSemester.id,
              name: '我的学期',
              firstWeekStart: sampleSemester.firstWeekStart,
              totalWeeks: weeks,
            ),
            makeActive: true,
          );
          expect((await repo.watchActiveSemester().first).totalWeeks, weeks);
          expect(await repo.watchCourses().first, isEmpty);
        } finally {
          await db.close();
        }
      },
    );
  }
  test(
    'first setup preserves edited sample and protects its actual weeks',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = CourseRepository(db);
      try {
        await repo.seedIfEmpty();
        expect(await repo.minimumSemesterWeeks(sampleSemester.id), 1);
        final original = sampleCourses.first;
        await repo.saveCourse(
          Course(
            id: original.id,
            semesterId: original.semesterId,
            source: original.source,
            name: '我编辑的课',
            teacher: original.teacher,
            colorValue: original.colorValue,
            sessions: original.sessions,
          ),
        );
        await expectLater(
          repo.saveSemester(
            Semester(
              id: sampleSemester.id,
              name: '学期',
              firstWeekStart: sampleSemester.firstWeekStart,
              totalWeeks: 10,
            ),
            makeActive: true,
          ),
          throwsFormatException,
        );
        expect(
          (await repo.watchCourses().first).any((c) => c.name == '我编辑的课'),
          isTrue,
        );
      } finally {
        await db.close();
      }
    },
  );
  for (final encoding in ['utf8', 'gbk', 'utf16']) {
    test('HTML exported as xls reads $encoding without resave', () {
      final html =
          '<html><head><meta charset="${encoding == 'gbk'
              ? 'gb2312'
              : encoding == 'utf16'
              ? 'utf-16'
              : 'utf-8'}"></head><body>$rowHtml</body></html>';
      final bytes = encoding == 'gbk'
          ? const GbkCodec().encode(html)
          : encoding == 'utf16'
          ? [
              255,
              254,
              ...html.codeUnits.expand((n) => [n & 255, n >> 8]),
            ]
          : utf8.encode(html);
      final result = const SmartTimetableImporter().parseExcel(
        Uint8List.fromList(bytes),
        term,
      );
      expect(result.courses.single.name, '线性代数');
      expect(result.courses.single.teacher, '张老师');
      expect(result.courses.single.sessions.single.weekday, 3);
      expect(result.courses.single.sessions.single.endWeek, 10);
    });
  }
  test('HTML merged cells and line breaks preserve grid coordinates', () {
    const html =
        '<html><table><tr><td rowspan="2">节次</td><td colspan="2">星期一</td><td>星期二</td></tr><tr><td>A</td><td>B</td><td>C</td></tr><tr><td>1-2节</td><td colspan="2">数学<br>张老师<br>1-10周<br>A101</td><td></td></tr></table></html>';
    final book = const ExcelTimetableImporter().decodeWorkbook(
      Uint8List.fromList(utf8.encode(html)),
    );
    final sheet = book.tables.values.single;
    expect(
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2))
          .value
          .toString(),
      contains('数学\n张老师'),
    );
    expect(sheet.spannedItems, contains('A1:A2'));
    expect(sheet.spannedItems, contains('B3:C3'));
  });
  test('XML Spreadsheet 2003 export supports named sheets and cell indexes', () {
    const xml =
        '''<?xml version="1.0"?><Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"><Worksheet ss:Name="课表"><Table><Row><Cell ss:MergeAcross="5"><Data ss:Type="String">某大学课表</Data></Cell></Row><Row><Cell><Data ss:Type="String">课程名称</Data></Cell><Cell><Data ss:Type="String">教师</Data></Cell><Cell><Data ss:Type="String">星期</Data></Cell><Cell><Data ss:Type="String">节次</Data></Cell><Cell><Data ss:Type="String">周次</Data></Cell><Cell><Data ss:Type="String">教室</Data></Cell></Row><Row ss:Index="4"><Cell><Data ss:Type="String">线性代数</Data></Cell><Cell><Data ss:Type="String">张老师</Data></Cell><Cell><Data ss:Type="String">星期三</Data></Cell><Cell><Data ss:Type="String">3-4节</Data></Cell><Cell><Data ss:Type="String">1-10周</Data></Cell><Cell><Data ss:Type="String">A101</Data></Cell></Row></Table></Worksheet></Workbook>''';
    final result = const SmartTimetableImporter().parseExcel(
      Uint8List.fromList(utf8.encode(xml)),
      term,
    );
    expect(result.courses.single.name, '线性代数');
  });
  test('unreadable bytes do not claim encryption', () {
    expect(
      () => const SmartTimetableImporter().parseWorkbook(
        Uint8List.fromList([0, 1, 2, 3]),
        term,
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          isNot(contains('加密文件')),
        ),
      ),
    );
  });
  testWidgets('other week title remains inside toolbar with large text', (
    t,
  ) async {
    t.view.physicalSize = const Size(393, 864);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(393, 864),
            padding: EdgeInsets.only(top: 24),
            textScaler: TextScaler.linear(1.2),
          ),
          child: TimetablePage(
            semester: term,
            courses: const [],
            initialDisplayWeek: 6,
            currentWeek: 6,
            initialGridView: true,
            now: DateTime(2026, 10, 8),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final before = t.getRect(find.text('第 6 周'));
    await t.tap(find.byKey(const Key('week_selector')));
    await t.pumpAndSettle();
    await t.tap(find.text('第 7 周').last);
    await t.pumpAndSettle();
    final after = t.getRect(find.text('第 7 周'));
    expect(after.top, greaterThanOrEqualTo(24));
    expect(after.bottom, lessThanOrEqualTo(80));
    expect(after.center.dy, closeTo(before.center.dy, 1));
    expect(find.byKey(const Key('return_to_current_week')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
