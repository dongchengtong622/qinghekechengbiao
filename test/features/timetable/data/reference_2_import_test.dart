import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/smart_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  test(
    'imports timetable with paired periods and multiple courses per cell',
    () {
      final semester = Semester(
        id: 'reference-2',
        name: '2026-2027学年第1学期',
        firstWeekStart: DateTime(2026, 9, 7),
        totalWeeks: 18,
      );
      final bytes = File(
        'test/fixtures/reference_timetable_2.xls',
      ).readAsBytesSync();
      final preview = const SmartTimetableImporter().parseExcel(
        bytes,
        semester,
      );

      expect(preview.courses, hasLength(26));
      final artificialMath = preview.courses.singleWhere(
        (course) =>
            course.name == '人工智能数学基础' &&
            course.sessions.any(
              (session) => session.weekday == DateTime.tuesday,
            ),
      );
      expect(artificialMath.teacher, '牛磊副教授');
      expect(artificialMath.sessions.single.startSection, 1);
      expect(artificialMath.sessions.single.endSection, 2);
      expect(artificialMath.sessions.single.endWeek, 16);
      expect(artificialMath.sessions.single.room, '南湖综合楼2(n210)');

      final wearable = preview.courses
          .where((course) => course.name == '可穿戴柔性电子器件前沿')
          .toList();
      expect(wearable, hasLength(2));
      expect(wearable.map((course) => course.teacher).toSet(), {
        '李攀副研究员',
        '简刚副研究员',
      });
      expect(
        wearable.every(
          (course) =>
              course.sessions.single.weekday == DateTime.saturday &&
              course.sessions.single.startSection == 1 &&
              course.sessions.single.endSection == 2,
        ),
        isTrue,
      );

      final humanities = preview.courses
          .where((course) => course.name == '人文社科经典导引')
          .toList();
      expect(humanities, hasLength(8));
      expect(humanities.map((course) => course.teacher).toSet(), hasLength(8));
      expect(
        humanities.every(
          (course) =>
              course.sessions.single.weekday == DateTime.thursday &&
              course.sessions.single.startSection == 9 &&
              course.sessions.single.endSection == 12,
        ),
        isTrue,
      );
      expect(
        preview.courses.every((course) => !course.name.contains(';')),
        isTrue,
      );
    },
  );
}
