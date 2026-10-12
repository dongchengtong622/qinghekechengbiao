import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  test(
    'view preference writes do not reemit unchanged courses or schedule',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final r = CourseRepository(db);
      await r.seedIfEmpty();
      final term = await r.watchActiveSemester().first;
      final courseEvents = <List<Course>>[];
      var scheduleEvents = 0;
      final c = r.watchCoursesForSemester(term.id).listen(courseEvents.add);
      final s = r.watchSchoolSchedule().listen((_) => scheduleEvents++);
      try {
        for (
          var i = 0;
          i < 30 && (courseEvents.isEmpty || scheduleEvents == 0);
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(courseEvents.length, 1);
        expect(scheduleEvents, 1);
        await r.setGridView(true);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(courseEvents.length, 1);
        expect(scheduleEvents, 1);
        final original = courseEvents.single.first;
        await r.saveCourse(
          Course(
            id: original.id,
            semesterId: original.semesterId,
            source: original.source,
            externalId: original.externalId,
            name: '更新后的课程',
            teacher: original.teacher,
            colorValue: original.colorValue,
            sessions: original.sessions,
          ),
        );
        for (var i = 0; i < 30 && courseEvents.length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(courseEvents.length, 2);
        expect(courseEvents.last.any((c) => c.name == '更新后的课程'), true);
      } finally {
        await c.cancel();
        await s.cancel();
        await db.close();
      }
    },
  );
}
