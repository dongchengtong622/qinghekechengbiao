import 'dart:typed_data';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/smart_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  final semester = Semester(
    id: 'term',
    name: '秋季学期',
    firstWeekStart: DateTime(2026, 9, 7),
    totalWeeks: 18,
  );
  test('recognizes alternative weekday and paired Chinese section labels', () {
    expect(SmartTimetableImporter.weekday('礼拜三'), DateTime.wednesday);
    expect(SmartTimetableImporter.weekday('周3'), DateTime.wednesday);
    expect(SmartTimetableImporter.weekday('呈期二'), DateTime.tuesday);
    expect(SmartTimetableImporter.sections('一二节'), (1, 2));
  });
  test('offset grid and merged periods preserve noncontinuous weeks', () {
    final result = const SmartTimetableImporter().parseGrid([
      const GridCell('星期一', 2, 2),
      const GridCell('Tue', 2, 3),
      const GridCell('第1节', 3, 1),
      const GridCell('第2节', 4, 1),
      const GridCell('高等数学\n张老师\n第三教学楼210\n1,3,5-9周', 3, 2, rowSpan: 2),
    ], semester);
    final course = result.courses.single;
    expect(course.name, '高等数学');
    expect(course.teacher, '张老师');
    expect(course.sessions.first.room, '第三教学楼210');
    expect(course.sessions.first.endSection, 2);
    final weeks = <int>{
      for (final s in course.sessions)
        for (var w = 1; w <= 18; w++)
          if (s.occursInWeek(w)) w,
    };
    expect(weeks, {1, 3, 5, 6, 7, 8, 9});
    expect(result.replaceExisting, isFalse);
  });
  test(
    'room numbers never become week ranges and missing weeks are flagged',
    () {
      final result = const SmartTimetableImporter().parseGrid([
        const GridCell('周一', 0, 1),
        const GridCell('周二', 0, 2),
        const GridCell('第1节', 1, 0),
        const GridCell('素描@王明@A302', 1, 1),
      ], semester);
      expect(result.courses.single.sessions.single.endWeek, 18);
      expect(result.warnings, isNotEmpty);
      expect(result.courses.single.sessions.single.room, 'A302');
    },
  );
  test('unrecognized grid fails with an actionable message', () {
    expect(
      () => const SmartTimetableImporter().parseGrid([
        const GridCell('随机文本', 0, 0),
      ], semester),
      throwsA(isA<FormatException>()),
    );
  });
  test(
    'wrapped course title and room from screenshot retain complete text',
    () {
      final result = const SmartTimetableImporter().parseGrid([
        const GridCell('星期一', 0, 1),
        const GridCell('星期二', 0, 2),
        const GridCell('二', 1, 0),
        const GridCell(
          '[28303083]计算机辅助设\n计 [2-5, 7-8周][2-4节]\n第三教学楼210-制图实训\n室',
          1,
          1,
        ),
      ], semester);
      expect(result.courses.single.name, '计算机辅助设计');
      expect(result.courses.single.sessions.first.room, '第三教学楼210-制图实训室');
      expect(result.courses.single.sessions.first.startSection, 2);
      expect(result.courses.single.sessions.first.endSection, 4);
    },
  );
  test('same slot with different weeks has a distinct import identity', () {
    List<GridCell> cells(String weeks) => [
      const GridCell('周一', 0, 1),
      const GridCell('周二', 0, 2),
      const GridCell('第1节', 1, 0),
      GridCell('数学@王明@A302@$weeks', 1, 1),
    ];
    final a = const SmartTimetableImporter().parseGrid(cells('1-8周'), semester);
    final b = const SmartTimetableImporter().parseGrid(
      cells('9-16周'),
      semester,
    );
    expect(a.courses.single.externalId, isNot(b.courses.single.externalId));
  });
  test('one OCR-misread week range does not discard other courses', () {
    final preview = const SmartTimetableImporter().parseGrid([
      const GridCell('周一', 0, 1),
      const GridCell('周二', 0, 2),
      const GridCell('第1节', 1, 0),
      const GridCell('数学\nA302\n1-16周', 1, 1),
      const GridCell('绘画\nB202\n14-61周', 1, 2),
    ], semester);
    expect(preview.courses.map((c) => c.name), ['数学']);
    expect(preview.warnings.join(' '), contains('周次超出'));
  });

  test(
    'noisy OCR course codes are removed and uncertain coded weeks are held',
    () {
      final preview = const SmartTimetableImporter().parseGrid([
        const GridCell('周一', 0, 1),
        const GridCell('周二', 0, 2),
        const GridCell('第1节', 1, 0),
        const GridCell('T28303065]居住区景观规划设计[1-4周][1-2节]\n第三教学楼210室', 1, 1),
        const GridCell('[28303066居住区景观规划设计[1-?周][1-2节]', 1, 2),
      ], semester);
      expect(preview.courses.single.name, '居住区景观规划设计');
      expect(preview.courses.single.sessions.single.weekday, DateTime.monday);
      expect(preview.warnings.join(' '), contains('周次识别不清'));
    },
  );

  test(
    'manual header row and section column recover an unusual Excel grid',
    () {
      final importer = const SmartTimetableImporter();
      final cells = [
        const GridCell('学院课表', 0, 0),
        const GridCell('时段', 2, 1),
        const GridCell('第一天', 2, 2),
        const GridCell('第二天', 2, 3),
        const GridCell('第1-2节', 3, 1),
        const GridCell('数学\nA302\n1-16周', 3, 2, rowSpan: 2),
      ];
      expect(() => importer.parseGrid(cells, semester), throwsFormatException);

      final preview = importer.parseGrid(
        cells,
        semester,
        headerRow: 2,
        periodColumn: 1,
      );
      expect(preview.courses.single.name, '数学');
      expect(preview.courses.single.sessions.single.weekday, DateTime.monday);
      expect(preview.courses.single.sessions.single.endSection, 2);
      expect(preview.warnings.join(' '), contains('星期'));
    },
  );

  test('failed auto-detection exposes workbook rows for manual mapping', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('时段');
    sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue('第一天');
    sheet.cell(CellIndex.indexByString('C2')).value = TextCellValue('第二天');
    sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('第1-2节');
    sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue(
      '数学\n1-16周',
    );
    final bytes = Uint8List.fromList(workbook.encode()!);

    void error() {
      const SmartTimetableImporter().parseExcel(bytes, semester);
    }

    expect(error, throwsA(isA<ExcelMappingRequiredException>()));
    try {
      error();
    } on ExcelMappingRequiredException catch (mapping) {
      expect(mapping.sheets, isNotEmpty);
      final preview = const SmartTimetableImporter().parseGrid(
        mapping.sheets.first.cells,
        semester,
        headerRow: 1,
        periodColumn: 0,
      );
      expect(preview.courses.single.name, '数学');
    }
  });

  test('imports courses from every valid worksheet', () {
    final workbook = Excel.createExcel();
    for (final (sheetName, title, weekday) in [
      ('Sheet1', '高等数学', '星期一'),
      ('第二张', '大学英语', '星期二'),
    ]) {
      final sheet = workbook[sheetName];
      final headers = ['课程名称', '星期', '节次', '周次'];
      final values = [title, weekday, '第1-2节', '1-16周'];
      for (var column = 0; column < headers.length; column++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0))
            .value = TextCellValue(
          headers[column],
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 1))
            .value = TextCellValue(
          values[column],
        );
      }
    }

    final preview = const SmartTimetableImporter().parseExcel(
      Uint8List.fromList(workbook.encode()!),
      semester,
    );

    expect(preview.courses.map((course) => course.name).toSet(), {
      '高等数学',
      '大学英语',
    });
  });

  test('merges sessions of the same course across worksheets', () {
    final workbook = Excel.createExcel();
    for (final (sheetName, weekday) in [('Sheet1', '星期一'), ('第二张', '星期三')]) {
      final sheet = workbook[sheetName];
      final headers = ['课程名称', '星期', '节次', '周次'];
      final values = ['高等数学', weekday, '第1-2节', '1-16周'];
      for (var column = 0; column < headers.length; column++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0))
            .value = TextCellValue(
          headers[column],
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 1))
            .value = TextCellValue(
          values[column],
        );
      }
    }

    final preview = const SmartTimetableImporter().parseExcel(
      Uint8List.fromList(workbook.encode()!),
      semester,
    );

    expect(preview.courses, hasLength(1));
    expect(
      preview.courses.single.sessions.map((session) => session.weekday).toSet(),
      {DateTime.monday, DateTime.wednesday},
    );
  });
}
