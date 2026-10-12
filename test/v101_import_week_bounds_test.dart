import 'package:qinghe_timetable/features/timetable/presentation/timetable_page.dart';
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/data/timetable_import.dart';
import 'package:qinghe_timetable/features/timetable/presentation/import_preview_page.dart';
import 'dart:typed_data';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/smart_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  final term = Semester(
    id: 'term',
    name: '当前学期',
    firstWeekStart: DateTime(2026, 8, 31),
    totalWeeks: 18,
  );
  const importer = SmartTimetableImporter();
  test('grid retains explicit weeks beyond current semester', () {
    final p = importer.parseGrid([
      const GridCell('周一', 0, 1),
      const GridCell('周二', 0, 2),
      const GridCell('第1节', 1, 0),
      const GridCell('高等数学\n张老师\n教学楼101\n1-20周', 1, 1),
    ], term);
    expect(p.courses.single.sessions.last.endWeek, 20);
    expect(p.semester.totalWeeks, 18);
    expect(p.warnings.join(' '), isNot(contains('未导入')));
  });
  test(
    'record workbook preserves 19-20 week course instead of replacing with whole term',
    () {
      final book = Excel.createExcel();
      final sheet = book['Sheet1'];
      final values = ['周一', '第1-2节', '计算机网络\n张老师\n教学楼101\n19-20周'];
      for (var c = 0; c < values.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
            .value = TextCellValue(
          values[c],
        );
      }
      final p = importer.parseExcel(Uint8List.fromList(book.encode()!), term);
      expect(p.courses.single.sessions.first.startWeek, 19);
      expect(p.courses.single.sessions.last.endWeek, 20);
      expect(p.semester.totalWeeks, 18);
    },
  );
  test('shorter grid does not shorten semester automatically', () {
    final p = importer.parseGrid([
      const GridCell('周一', 0, 1),
      const GridCell('周二', 0, 2),
      const GridCell('第1节', 1, 0),
      const GridCell('大学英语\n王老师\n教学楼102\n1-16周', 1, 1),
    ], term);
    expect(p.semester.totalWeeks, 18);
    expect(p.courses.single.sessions.last.endWeek, 16);
  });
  testWidgets(
    'preview offers explicit extension without saving or shifting dates',
    (tester) async {
      final p = importer.parseGrid([
        const GridCell('周一', 0, 1),
        const GridCell('周二', 0, 2),
        const GridCell('第1节', 1, 0),
        const GridCell('高等数学\n张老师\n教学楼101\n1-20周', 1, 1),
      ], term);
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ImportPreviewPage(
            preview: p,
            changes: const ImportSummary(
              inserted: 1,
              updated: 0,
              removed: 0,
              warnings: [],
            ),
            onConfirm: (p) async {
              saved = true;
              return const ImportSummary(
                inserted: 1,
                updated: 0,
                removed: 0,
                warnings: [],
              );
            },
          ),
        ),
      );
      expect(find.text('课程到第 20 周，当前学期只有 18 周'), findsOneWidget);
      await tester.tap(find.text('调整为 20 周'));
      await tester.pumpAndSettle();
      expect(find.text('课程到第 20 周，当前学期只有 18 周'), findsNothing);
      expect(find.textContaining('2026-08-31 · 20 周'), findsOneWidget);
      expect(saved, false);
    },
  );
  test(
    'import requires adequate weeks and later Monday edit keeps course data',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final r = CourseRepository(db);
      try {
        await r.saveSemester(term, makeActive: true);
        final p = importer.parseGrid([
          const GridCell('周一', 0, 1),
          const GridCell('周二', 0, 2),
          const GridCell('第1节', 1, 0),
          const GridCell('高等数学\n张老师\n教学楼101\n1-20周', 1, 1),
        ], term);
        await expectLater(() => r.importTimetable(p), throwsFormatException);
        expect(await r.watchCoursesForSemester(term.id).first, isEmpty);
        final extended = Semester(
          id: term.id,
          name: term.name,
          firstWeekStart: term.firstWeekStart,
          totalWeeks: 20,
        );
        await r.importTimetable(
          ImportPreview(semester: extended, courses: p.courses),
        );
        final corrected = Semester(
          id: term.id,
          name: term.name,
          firstWeekStart: DateTime(2026, 9, 7),
          totalWeeks: 20,
        );
        await r.saveSemester(corrected, makeActive: true);
        final saved = await r.watchActiveSemester().first;
        final courses = await r.watchCoursesForSemester(term.id).first;
        expect(saved.weekFor(DateTime(2026, 9, 7)), 1);
        expect(saved.weekFor(DateTime(2026, 9, 14)), 2);
        expect(courses.single.sessions.last.endWeek, 20);
        expect(courses.single.teacher, '张老师');
      } finally {
        await db.close();
      }
    },
  );
  testWidgets(
    'same timetable date correction returns home to corrected current week',
    (tester) async {
      Widget page(DateTime monday, int week) => MaterialApp(
        home: TimetablePage(
          semester: Semester(
            id: 'same',
            name: '学期',
            firstWeekStart: monday,
            totalWeeks: 20,
          ),
          courses: const [],
          initialDisplayWeek: week,
          currentWeek: week,
          now: DateTime(2026, 10, 8),
        ),
      );
      await tester.pumpWidget(page(DateTime(2026, 8, 31), 6));
      await tester.pumpAndSettle();
      expect(find.text('第 6 周'), findsOneWidget);
      await tester.pumpWidget(page(DateTime(2026, 9, 7), 5));
      await tester.pumpAndSettle();
      expect(find.text('第 5 周'), findsOneWidget);
      expect(find.textContaining('10/8'), findsWidgets);
    },
  );
}
