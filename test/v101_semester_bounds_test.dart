import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  test(
    'term shrink protects imported course weeks and date edit preserves courses',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final r = CourseRepository(db);
      try {
        final term = Semester(
          id: 'test',
          name: '测试学期',
          firstWeekStart: DateTime(2026, 8, 31),
          totalWeeks: 20,
        );
        await r.saveSemester(term, makeActive: true);
        await r.saveCourse(
          const Course(
            id: 'c',
            semesterId: 'test',
            source: CourseSource.manual,
            name: '高等数学',
            teacher: '王老师',
            colorValue: 0xff008800,
            sessions: [
              CourseSession(
                weekday: 1,
                startSection: 1,
                endSection: 2,
                startWeek: 1,
                endWeek: 18,
                pattern: WeekPattern.everyWeek,
                room: 'A101',
              ),
            ],
          ),
          synchronizeTimes: false,
        );
        await expectLater(
          r.saveSemester(
            Semester(
              id: 'test',
              name: '改名',
              firstWeekStart: DateTime(2026, 9, 7),
              totalWeeks: 16,
            ),
            makeActive: true,
          ),
          throwsA(isA<FormatException>()),
        );
        expect((await r.watchActiveSemester().first).totalWeeks, 20);
        await r.saveSemester(
          Semester(
            id: 'test',
            name: '新学期',
            firstWeekStart: DateTime(2026, 9, 7),
            totalWeeks: 18,
          ),
          makeActive: true,
        );
        expect(
          (await r.watchActiveSemester().first).firstWeekStart,
          DateTime(2026, 9, 7),
        );
        final courses = await r.watchCoursesForSemester('test').first;
        expect(courses.single.sessions.single.endWeek, 18);
        expect(courses.single.teacher, '王老师');
        expect(courses.single.sessions.single.room, 'A101');
        await r.saveSemester(
          Semester(
            id: 'empty',
            name: '独立课表',
            firstWeekStart: DateTime(2026, 9, 7),
            totalWeeks: 4,
          ),
        );
      } finally {
        await db.close();
      }
    },
  );
}
