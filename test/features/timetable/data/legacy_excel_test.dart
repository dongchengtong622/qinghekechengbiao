import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/smart_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  final term = Semester(
    id: 's',
    name: '秋季',
    firstWeekStart: DateTime(2026, 9, 7),
    totalWeeks: 18,
  );
  for (final format in ['xlsx', 'xls']) {
    test(
      'reference $format discovers weekday, embedded periods and multiple courses',
      () {
        final result = const SmartTimetableImporter().parseExcel(
          File('test/fixtures/reference_timetable.$format').readAsBytesSync(),
          term,
        );
        final cad = result.courses
            .where((c) => c.name == '计算机辅助设计')
            .expand((c) => c.sessions)
            .toList();
        expect(
          cad.any(
            (s) =>
                s.weekday == 1 &&
                s.startSection == 2 &&
                s.endSection == 4 &&
                s.occursInWeek(4),
          ),
          isTrue,
        );
        final studio = result.courses
            .where((c) => c.name == '居住区景观规划设计综合实训')
            .expand((c) => c.sessions)
            .toList();
        expect(
          studio.any(
            (s) =>
                s.weekday == 3 &&
                s.startSection == 1 &&
                s.endSection == 4 &&
                s.occursInWeek(9) &&
                !s.occursInWeek(10),
          ),
          isTrue,
        );
        expect(cad.any((s) => s.room.contains('210')), isTrue);
      },
    );
  }
  for (final extension in ['xls', 'xlsx']) {
    test('ordinary row-based $extension needs no template metadata', () {
      final term = Semester(
        id: 'chosen',
        name: '用户学期',
        firstWeekStart: DateTime(2027, 2, 22),
        totalWeeks: 18,
      );
      final result = const SmartTimetableImporter().parseExcel(
        File(
          'test/fixtures/rows_without_template.$extension',
        ).readAsBytesSync(),
        term,
      );
      expect(result.semester.id, 'chosen');
      expect(result.courses.single.name, '线性代数');
      expect(result.courses.single.sessions.single.weekday, 3);
      expect(result.courses.single.sessions.single.startSection, 3);
    });
  }
}
