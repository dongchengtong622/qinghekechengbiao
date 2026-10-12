import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';

import 'package:qinghe_timetable/features/timetable/data/backup/timetable_backup_service.dart';
import 'package:qinghe_timetable/features/timetable/data/timetable_import.dart';

void main() {
  test('seeded example does not satisfy first import semester setup', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final r = CourseRepository(db);
    await r.seedIfEmpty();
    expect(await r.hasConfiguredSemester(), false);
    final t = await r.watchActiveSemester().first;
    await r.saveSemester(t, makeActive: true);
    expect(await r.hasConfiguredSemester(), true);
  });
  test(
    'extended scoped period survives own backup export and restore',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final r = CourseRepository(db);
      await r.saveSemester(
        Semester(
          id: 'a',
          name: 'A',
          firstWeekStart: DateTime(2026, 9, 7),
          totalWeeks: 20,
        ),
        makeActive: true,
      );
      await r.saveSemesterSchedule(
        'a',
        SchoolSchedule.defaults().withSemesterSections('a', [
          const SectionTime(13, 1300, 1345),
        ], lessonMinutes: 45),
      );
      await r.saveCourse(
        const Course(
          id: 'late',
          semesterId: 'a',
          source: CourseSource.manual,
          name: '晚课',
          teacher: '张老师',
          colorValue: 0,
          sessions: [
            CourseSession(
              weekday: 1,
              startSection: 13,
              endSection: 13,
              startWeek: 1,
              endWeek: 20,
              pattern: WeekPattern.everyWeek,
              room: 'A301',
            ),
          ],
        ),
      );
      final service = TimetableBackupService(db);
      final encoded = await service.exportJson();
      final preview = service.previewRestore(encoded);
      await service.restore(preview.backup);
      expect(
        (await r.watchCoursesForSemester('a').first)
            .single
            .sessions
            .single
            .timeLabel,
        '21:40–22:25',
      );
      expect((await r.readSchoolSchedule()).lessonMinutesFor('a'), 45);
    },
  );
  test(
    'multiple schedules switch independently and semester edit keeps active',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final r = CourseRepository(db);
      const id = 'a';
      final a = Semester(
        id: id,
        name: 'A',
        firstWeekStart: DateTime(2026, 9, 7),
        totalWeeks: 20,
      );
      final b = Semester(
        id: 'b',
        name: 'B',
        firstWeekStart: DateTime(2026, 9, 14),
        totalWeeks: 18,
      );
      await r.saveSemester(a, makeActive: true);
      await r.saveSemester(b);
      expect((await r.watchSemesters().first).length, 2);
      await r.activateSemester('b');
      expect((await r.watchActiveSemester().first).id, 'b');
      await r.saveSemester(b);
      expect((await r.watchActiveSemester().first).id, 'b');
      await r.saveSemesterSchedule(
        'a',
        SchoolSchedule.defaults().withSemesterSections('a', [
          const SectionTime(1, 480, 525),
        ]),
      );
      expect(
        (await r.readSchoolSchedule()).sectionFor('a', 1)?.startMinute,
        480,
      );
      expect(
        (await r.readSchoolSchedule()).sectionFor('b', 1)?.startMinute,
        505,
      );
      expect(await r.hasConfiguredSemester(), true);
    },
  );
  test(
    'confirmed imported times replace settings profile and isolate other terms',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final r = CourseRepository(db);
      final term = Semester(
        id: 'a',
        name: 'A',
        firstWeekStart: DateTime(2026, 9, 7),
        totalWeeks: 17,
      );
      await r.saveSemester(term, makeActive: true);
      final initial = SchoolSchedule.defaults().withSemesterSections('a', [
        const SectionTime(1, 505, 550),
        const SectionTime(2, 555, 600),
      ]);
      await r.saveSemesterSchedule('a', initial);
      final imported = initial
          .withRangeTime(
            const SectionRangeTime(
              semesterId: 'a',
              startSection: 1,
              endSection: 2,
              startMinute: 480,
              endMinute: 580,
            ),
          )
          .withSemesterSections('a', [
            const SectionTime(1, 480, 525),
            const SectionTime(2, 535, 580),
          ]);
      await r.importTimetable(
        ImportPreview(
          semester: term,
          sectionSchedule: imported,
          importedTimes: [imported.rangeTimes.single],
          courses: const [
            Course(
              id: 'new',
              externalId: 'new',
              semesterId: 'a',
              source: CourseSource.cdcasKingo,
              name: '大学物理',
              teacher: '张老师',
              colorValue: 0,
              sessions: [
                CourseSession(
                  weekday: 1,
                  startSection: 1,
                  endSection: 2,
                  startWeek: 1,
                  endWeek: 17,
                  pattern: WeekPattern.everyWeek,
                  room: 'A101',
                  startMinute: 480,
                  endMinute: 580,
                  timeSource: CourseTimeSource.imported,
                ),
              ],
            ),
          ],
        ),
      );
      final settings = await r.readSchoolSchedule();
      expect(settings.sectionFor('a', 1)!.startMinute, 480);
      expect(settings.sectionFor('a', 2)!.startMinute, 535);
      expect(settings.sectionFor('b', 1)!.startMinute, 505);
      expect(
        (await r.watchCoursesForSemester('a').first)
            .single
            .sessions
            .single
            .timeLabel,
        '08:00–09:40',
      );
    },
  );
}
