import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/excel_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/data/smart_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  final term = Semester(
    id: 'term',
    name: '秋季',
    firstWeekStart: DateTime(2026, 9, 7),
    totalWeeks: 18,
  );
  test(
    'manual grid mapping keeps empty weekday columns in their real positions',
    () {
      final preview = const SmartTimetableImporter().parseGrid(
        const [
          GridCell('周一', 0, 1),
          GridCell('', 0, 2),
          GridCell('周三', 0, 3),
          GridCell('第1-2节', 1, 0),
          GridCell('英语\n1-16周\nA302', 1, 2),
        ],
        term,
        headerRow: 0,
        periodColumn: 0,
      );
      expect(preview.courses.single.sessions.single.weekday, DateTime.tuesday);
    },
  );
  test(
    'English Excel records preserve mixed ranges and discrete odd weeks',
    () {
      final preview = const ExcelTimetableImporter().parseRows([
        ['Course', 'Day', 'Periods', 'Weeks', 'Teacher', 'Room'],
        ['高等数学', 'Monday', '1-2', '1-5,9,13-16 odd', '王明', 'A302'],
      ], fallbackSemester: term);
      final course = preview.courses.single;
      expect(course.teacher, '王明');
      expect(
        course.sessions.every(
          (s) => s.weekday == 1 && s.pattern == WeekPattern.oddWeeks,
        ),
        isTrue,
      );
      expect(
        course.sessions.any((s) => s.startWeek <= 9 && s.endWeek >= 9),
        isTrue,
      );
      expect(
        course.sessions.any((s) => s.startWeek <= 7 && s.endWeek >= 7),
        isFalse,
      );
    },
  );
}
