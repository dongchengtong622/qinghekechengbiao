import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';

void main() {
  test(
    'replacement refreshes section times without changing custom times',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = CourseRepository(db);
      await repo.saveCourse(
        Course(
          id: 'one',
          semesterId: 's',
          source: CourseSource.manual,
          name: '数学',
          teacher: '',
          colorValue: 0,
          sessions: [
            const CourseSession(
              weekday: 1,
              startSection: 1,
              endSection: 2,
              startWeek: 1,
              endWeek: 18,
              pattern: WeekPattern.everyWeek,
              room: '',
            ),
            const CourseSession(
              weekday: 2,
              startSection: 3,
              endSection: 4,
              startWeek: 1,
              endWeek: 18,
              pattern: WeekPattern.everyWeek,
              room: '',
              startMinute: 600,
              endMinute: 690,
            ),
          ],
        ),
      );
      final initial = (await repo.watchCourses().first).single;
      expect(initial.sessions.first.startMinute, 505);
      expect(initial.sessions.first.endMinute, 600);
      final schedule = SchoolSchedule(
        id: 'custom',
        sections: [
          const SectionTime(1, 480, 525),
          const SectionTime(2, 535, 580),
        ],
      );
      await repo.saveSchoolSchedule(schedule);
      final sessions = (await repo.watchCourses().first).single.sessions;
      expect(sessions.first.startMinute, 480);
      expect(sessions.first.endMinute, 580);
      expect(sessions.last.startMinute, 600);
      expect(sessions.last.endMinute, 690);
      await repo.saveCourse((await repo.watchCourses().first).single);
      expect((await repo.watchSchoolSchedule().first).sections.length, 2);
      await repo.saveSchoolSchedule(SchoolSchedule.defaults());
      expect(
        (await repo.watchCourses().first).single.sessions.first.startMinute,
        505,
      );
    },
  );
  test(
    'invalid schedule and uncovered sections leave saved schedule intact',
    () async {
      expect(
        () => SchoolSchedule(
          id: 'bad',
          sections: [
            const SectionTime(1, 500, 540),
            const SectionTime(1, 530, 580),
          ],
        ),
        throwsFormatException,
      );
      expect(
        () => SchoolSchedule(
          id: 'bad',
          sections: [const SectionTime(1, 500, 490)],
        ),
        throwsFormatException,
      );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = CourseRepository(db);
      await repo.seedIfEmpty();
      await expectLater(
        repo.saveSchoolSchedule(
          SchoolSchedule(
            id: 'short',
            sections: [const SectionTime(1, 500, 540)],
          ),
        ),
        throwsFormatException,
      );
      expect((await repo.watchSchoolSchedule().first).sections.length, 12);
    },
  );
  test(
    'new courses cannot silently use periods missing from current schedule',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = CourseRepository(db);
      await repo.saveSchoolSchedule(
        SchoolSchedule(id: 'short', sections: [const SectionTime(1, 480, 525)]),
      );
      await expectLater(
        repo.saveCourse(
          const Course(
            id: 'outside',
            semesterId: 's',
            source: CourseSource.manual,
            name: '课程',
            teacher: '',
            colorValue: 0,
            sessions: [
              CourseSession(
                weekday: 1,
                startSection: 2,
                endSection: 2,
                startWeek: 1,
                endWeek: 18,
                pattern: WeekPattern.everyWeek,
                room: '',
              ),
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(await repo.watchCourses().first, isEmpty);
    },
  );
}
