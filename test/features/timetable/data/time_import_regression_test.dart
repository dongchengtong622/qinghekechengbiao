import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/data/excel_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/data/smart_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  final semester = Semester(
    id: 'autumn',
    name: '学期',
    firstWeekStart: DateTime(2026, 9, 7),
    totalWeeks: 18,
  );
  test('Excel times survive confirmation and database reload', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = CourseRepository(database);
    final preview = const ExcelTimetableImporter().parseRows([
      ['课程名称', '星期', '节次', '周次', '开始时间', '结束时间'],
      ['数学', '周五', '5-6', '1-18', '14:00', '15:35'],
    ], fallbackSemester: semester);
    await repository.importTimetable(preview);
    final session = (await repository.watchCoursesForSemester('autumn').first)
        .single
        .sessions
        .single;
    expect(session.startMinute, 840);
    expect(session.endMinute, 935);
  });
  test('grid period headings carry their own timetable time', () {
    final preview = const SmartTimetableImporter().parseGrid([
      const GridCell('周一', 0, 1),
      const GridCell('周二', 0, 2),
      const GridCell('一\n01、02小节\n08:00~09:40', 1, 0),
      const GridCell('数学\n1-18周\nA302', 1, 1),
    ], semester);
    expect(preview.courses.single.sessions.single.startMinute, 480);
    expect(preview.courses.single.sessions.single.endMinute, 580);
  });
  test(
    'a manual time change reaches all matching periods in its semester',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = CourseRepository(database);
      Course course(
        String id,
        int day, {
        String term = 'autumn',
        int? start,
        int? end,
      }) => Course(
        id: id,
        semesterId: term,
        source: CourseSource.manual,
        name: id,
        teacher: '',
        colorValue: 0xFF2E7D66,
        sessions: [
          CourseSession(
            weekday: day,
            startSection: 5,
            endSection: 6,
            startWeek: 1,
            endWeek: 18,
            pattern: WeekPattern.everyWeek,
            room: '',
            startMinute: start,
            endMinute: end,
          ),
        ],
      );
      await repository.saveCourse(course('Thursday', 4));
      await repository.saveCourse(course('Friday', 5));
      await repository.saveCourse(course('other-term', 5, term: 'spring'));
      await repository.saveCourse(course('Thursday', 4, start: 505, end: 600));
      final reloaded = await CourseRepository(
        database,
      ).watchCoursesForSemester('autumn').first;
      expect(reloaded.map((c) => c.sessions.single.timeLabel).toSet(), {
        '08:25–10:00',
      });
      expect(
        (await repository.watchCoursesForSemester('spring').first)
            .single
            .sessions
            .single
            .timeLabel,
        '13:40–15:15',
      );
      await repository.saveCourse(course('new-class', 1));
      expect(
        (await repository.watchCoursesForSemester('autumn').first)
            .singleWhere((c) => c.id == 'new-class')
            .sessions
            .single
            .timeLabel,
        '08:25–10:00',
      );
    },
  );
}
