import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/data/backup/timetable_backup_service.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';

void main() {
  final base = SchoolSchedule.defaults();
  const slots = [SectionTime(1, 480, 525), SectionTime(2, 540, 585)];
  test(
    'shrunk count and fixed mode survive encoding and isolate another table',
    () {
      final revised = base.withSemesterSections(
        'a',
        slots,
        sectionCount: 2,
        fixedLessonDuration: true,
        lessonMinutes: 45,
      );
      final decoded = SchoolSchedule.decode(revised.encode());
      expect(decoded.sectionCountFor('a'), 2);
      expect(decoded.sectionFor('a', 3), null);
      expect(decoded.sectionCountFor('b'), 12);
      expect(decoded.fixedLessonDurationFor('a'), true);
      expect(decoded.fixedLessonDurationFor('b'), false);
    },
  );
  test(
    'new imported evidence extends count and disables fixed editor only for its table',
    () {
      final revised = base
          .withSemesterSections(
            'a',
            slots,
            sectionCount: 2,
            fixedLessonDuration: true,
          )
          .withSemesterSections(
            'b',
            slots,
            sectionCount: 2,
            fixedLessonDuration: true,
          );
      final imported = revised.withRangeTime(
        const SectionRangeTime(
          semesterId: 'a',
          startSection: 3,
          endSection: 3,
          startMinute: 600,
          endMinute: 635,
        ),
      );
      expect(imported.sectionCountFor('a'), 3);
      expect(imported.fixedLessonDurationFor('a'), false);
      expect(imported.fixedLessonDurationFor('b'), true);
      expect(imported.sectionFor('a', 3)!.endMinute, 635);
    },
  );
  test('reducing count trims obsolete imported tail ranges', () {
    final imported = base.withRangeTime(
      const SectionRangeTime(
        semesterId: 'a',
        startSection: 11,
        endSection: 12,
        startMinute: 1260,
        endMinute: 1370,
      ),
    );
    final revised = imported.withSemesterSections('a', slots, sectionCount: 2);
    expect(revised.rangeTimes, isEmpty);
    expect(SchoolSchedule.decode(revised.encode()).sectionCountFor('a'), 2);
  });
  test('invalid overlap and midnight cannot be committed', () {
    expect(
      () => base.withSemesterSections('a', const [
        SectionTime(1, 480, 525),
        SectionTime(2, 510, 555),
      ]),
      throwsFormatException,
    );
    expect(
      () => base.withSemesterSections('a', const [SectionTime(1, 1420, 1465)]),
      throwsFormatException,
    );
  });
  test('repository backup restores mode and deleted period count', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final r = CourseRepository(db);
    await r.saveSemester(
      Semester(
        id: 'a',
        name: 'A',
        firstWeekStart: DateTime(2026, 9, 7),
        totalWeeks: 18,
      ),
      makeActive: true,
    );
    await r.saveSemesterSchedule(
      'a',
      base.withSemesterSections(
        'a',
        slots,
        sectionCount: 2,
        fixedLessonDuration: true,
        lessonMinutes: 45,
      ),
    );
    final backup = TimetableBackupService(db);
    final preview = backup.previewRestore(await backup.exportJson());
    await backup.restore(preview.backup);
    final saved = await r.readSchoolSchedule();
    expect(saved.sectionCountFor('a'), 2);
    expect(saved.fixedLessonDurationFor('a'), true);
    expect(saved.lessonMinutesFor('a'), 45);
  });
  test(
    'explicit-time course protects last used period and failed save is atomic',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final r = CourseRepository(db);
      await r.saveSemester(
        Semester(
          id: 'a',
          name: 'A',
          firstWeekStart: DateTime(2026, 9, 7),
          totalWeeks: 18,
        ),
        makeActive: true,
      );
      await r.saveCourse(
        const Course(
          id: 'c',
          semesterId: 'a',
          name: '实验',
          teacher: '老师',
          source: CourseSource.manual,
          colorValue: 0,
          sessions: [
            CourseSession(
              weekday: 1,
              startSection: 3,
              endSection: 3,
              startWeek: 1,
              endWeek: 18,
              pattern: WeekPattern.everyWeek,
              room: 'A1',
              startMinute: 600,
              endMinute: 645,
              timeSource: CourseTimeSource.custom,
            ),
          ],
        ),
      );
      final before = (await r.readSchoolSchedule()).encode();
      await expectLater(
        r.saveSemesterSchedule(
          'a',
          base.withSemesterSections('a', slots, sectionCount: 2),
        ),
        throwsFormatException,
      );
      expect((await r.readSchoolSchedule()).encode(), before);
      expect(
        (await r.watchCoursesForSemester('a').first)
            .single
            .sessions
            .single
            .endSection,
        3,
      );
    },
  );
}

