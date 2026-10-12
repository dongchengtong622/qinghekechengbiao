import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/smart_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  final semester = Semester(
    id: 'sample-term',
    name: '2025-2026学年第1学期',
    firstWeekStart: DateTime(2025, 9, 1),
    totalWeeks: 16,
  );
  const importer = SmartTimetableImporter();
  const expectedCourseCounts = {
    '工科_机械工程.xlsx': 10,
    '计算机_软件工程.xlsx': 9,
    '经管_工商管理.xlsx': 9,
    '医学_临床医学.xlsx': 8,
    '艺术设计_视觉传达.xlsx': 8,
    '园林专升本_园林技术.xlsx': 8,
  };

  for (final sample in expectedCourseCounts.entries) {
    test('imports all courses from ${sample.key}', () {
      final bytes = File(
        'test/fixtures/other_timetable_formats/${sample.key}',
      ).readAsBytesSync();

      final workbook = importer.parseWorkbook(bytes, semester);

      expect(workbook.sheets, hasLength(1));
      final preview = workbook.sheets.single.preview;
      expect(preview, isNotNull, reason: workbook.sheets.single.error);
      expect(preview!.courses, hasLength(sample.value));
      expect(
        preview.courses.every((course) => course.sessions.isNotEmpty),
        isTrue,
      );
    });
  }

  test(
    'preserves orientation, room, teacher and week pattern across layouts',
    () {
      Course course(String file, String name) {
        final bytes = File(
          'test/fixtures/other_timetable_formats/$file',
        ).readAsBytesSync();
        final preview = importer
            .parseWorkbook(bytes, semester)
            .sheets
            .single
            .preview!;
        return preview.courses.singleWhere(
          (candidate) => candidate.name == name,
        );
      }

      final rows = course('医学_临床医学.xlsx', '诊断学实验');
      expect(rows.sessions.single.weekday, DateTime.tuesday);
      expect(rows.sessions.single.startSection, 5);
      expect(rows.sessions.single.endSection, 8);
      expect(rows.sessions.single.pattern, WeekPattern.evenWeeks);
      expect(rows.sessions.single.room, '临床技能中心实验室3');

      final horizontal = course('工科_机械工程.xlsx', '工程力学');
      expect(horizontal.teacher, '周启明');
      expect(horizontal.sessions.single.room, '明理楼A203');

      final vertical = course('园林专升本_园林技术.xlsx', '园林植物识别实习');
      expect(vertical.sessions, hasLength(1));
      expect(vertical.sessions.single.weekday, DateTime.tuesday);
      expect(vertical.sessions.single.startSection, 5);
      expect(vertical.sessions.single.endSection, 6);
      expect(vertical.sessions.single.startWeek, 4);
      expect(vertical.sessions.single.endWeek, 12);
      expect(vertical.sessions.single.pattern, WeekPattern.oddWeeks);
      expect(vertical.sessions.single.room, '校园苗圃集合');
      expect(vertical.teacher, '冯林');

      final records = course('计算机_软件工程.xlsx', '程序设计基础（Python）');
      expect(records.sessions.single.weekday, DateTime.tuesday);
      expect(records.sessions.single.startSection, 1);
      expect(records.sessions.single.endSection, 4);
      expect(records.sessions.single.endWeek, 8);
      expect(records.sessions.single.room, '计算机实验室C204');
      expect(records.teacher, '罗博');
    },
  );
}
