import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/backup/timetable_backup_service.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';

void main() {
  late AppDatabase database;
  late CourseRepository repository;
  late TimetableBackupService service;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = CourseRepository(database);
    service = TimetableBackupService(database);
  });
  tearDown(() => database.close());

  test('exports and restores courses and reminder preferences', () async {
    final semester = Semester(
      id: 'term',
      name: '秋季学期',
      firstWeekStart: DateTime(2026, 9, 7),
      totalWeeks: 18,
    );
    await repository.saveSemester(semester, makeActive: true);
    await repository.saveCourse(
      Course(
        id: 'math',
        semesterId: 'term',
        source: CourseSource.manual,
        name: '高等数学',
        teacher: '陈老师',
        colorValue: 0xff234567,
        sessions: const [
          CourseSession(
            weekday: DateTime.monday,
            startSection: 1,
            endSection: 2,
            startWeek: 1,
            endWeek: 18,
            pattern: WeekPattern.oddWeeks,
            room: 'A302',
          ),
        ],
      ),
    );
    await repository.setReminderLeadMinutes(15);
    final json = await service.exportJson();
    final preview = service.previewRestore(json);
    expect(preview.courseCount, 1);
    expect(preview.semesterCount, 1);
    expect((jsonDecode(json) as Map)['majorVersion'], 1);

    await repository.deleteCourse('math');
    await service.restore(preview.backup);

    final restored = (await repository.watchCourses().first).single;
    expect(restored.name, '高等数学');
    expect(restored.sessions.single.pattern, WeekPattern.oddWeeks);
    expect((await repository.watchReminderPreferences().first).leadMinutes, 15);
  });

  test(
    'round trips custom time, discrete weeks, schedule and semesters',
    () async {
      await repository.saveSemester(
        Semester(
          id: 'spring',
          name: '春季学期',
          firstWeekStart: DateTime(2026, 2, 23),
          totalWeeks: 20,
        ),
        makeActive: false,
      );
      await repository.saveSemester(
        Semester(
          id: 'autumn',
          name: '秋季学期',
          firstWeekStart: DateTime(2026, 9, 7),
          totalWeeks: 18,
        ),
        makeActive: true,
      );
      await repository.saveSchoolSchedule(
        SchoolSchedule(
          id: 'custom',
          sections: const [SectionTime(1, 480, 525)],
        ),
      );
      await repository.saveCourse(
        const Course(
          id: 'lab',
          semesterId: 'autumn',
          source: CourseSource.cdcasKingo,
          externalId: 'source-42',
          name: '实验课',
          teacher: '教师',
          colorValue: 0xff123456,
          sessions: [
            CourseSession(
              weekday: 3,
              startSection: 2,
              endSection: 2,
              startWeek: 2,
              endWeek: 16,
              pattern: WeekPattern.evenWeeks,
              room: '实验楼',
              startMinute: 600,
              endMinute: 650,
              timeSource: CourseTimeSource.custom,
            ),
          ],
        ),
      );

      final exported = await service.exportJson();
      final preview = service.previewRestore(exported);
      await repository.deleteCourse('lab');
      await service.restore(preview.backup);

      expect(preview.backup.semesters, hasLength(2));
      expect((await repository.watchActiveSemester().first).id, 'autumn');
      expect(
        (await repository.watchSchoolSchedule().first)
            .sections
            .single
            .startMinute,
        480,
      );
      final restored = (await repository.watchCourses().first).single;
      expect(restored.externalId, 'source-42');
      expect(restored.sessions.single.pattern, WeekPattern.evenWeeks);
      expect(restored.sessions.single.startWeek, 2);
      expect(restored.sessions.single.endWeek, 16);
      expect(restored.sessions.single.startMinute, 600);
      expect(restored.sessions.single.endMinute, 650);
      expect(restored.sessions.single.timeSource, CourseTimeSource.custom);
    },
  );

  test('rejects a missing backup creation time', () async {
    await repository.saveSemester(
      Semester(
        id: 'term',
        name: '学期',
        firstWeekStart: DateTime(2026, 9, 7),
        totalWeeks: 18,
      ),
      makeActive: true,
    );
    final data = jsonDecode(await service.exportJson()) as Map<String, dynamic>;
    data.remove('createdAt');
    expect(
      () => service.previewRestore(jsonEncode(data)),
      throwsFormatException,
    );
  });

  test(
    'rejects an unsupported version without touching current data',
    () async {
      final semester = Semester(
        id: 'term',
        name: '秋季学期',
        firstWeekStart: DateTime(2026, 9, 7),
        totalWeeks: 18,
      );
      await repository.saveSemester(semester, makeActive: true);
      final json = await service.exportJson();
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      decoded['majorVersion'] = 99;

      expect(
        () => service.previewRestore(jsonEncode(decoded)),
        throwsFormatException,
      );
      expect((await repository.watchActiveSemester().first).id, 'term');
    },
  );

  test('shows which courses a restore will add and remove', () async {
    final semester = Semester(
      id: 'term',
      name: '秋季学期',
      firstWeekStart: DateTime(2026, 9, 7),
      totalWeeks: 18,
    );
    await repository.saveSemester(semester, makeActive: true);
    await repository.saveCourse(
      Course(
        id: 'old',
        semesterId: 'term',
        source: CourseSource.manual,
        name: '旧课程',
        teacher: '',
        colorValue: 0xff123456,
        sessions: const [
          CourseSession(
            weekday: 1,
            startSection: 1,
            endSection: 1,
            startWeek: 1,
            endWeek: 18,
            pattern: WeekPattern.everyWeek,
            room: '',
          ),
        ],
      ),
    );
    final exported =
        jsonDecode(await service.exportJson()) as Map<String, dynamic>;
    final courses = exported['courses'] as List;
    (courses.single as Map<String, dynamic>)['id'] = 'new';
    final preview = service.previewRestore(jsonEncode(exported));

    final diff = await service.compare(preview.backup);

    expect(diff.added, 1);
    expect(diff.removed, 1);
    expect(diff.replaced, 0);
  });

  test('rejects invalid reminder preferences before restoring', () async {
    final semester = Semester(
      id: 'term',
      name: '秋季学期',
      firstWeekStart: DateTime(2026, 9, 7),
      totalWeeks: 18,
    );
    await repository.saveSemester(semester, makeActive: true);
    final data = jsonDecode(await service.exportJson()) as Map<String, dynamic>;
    (data['reminderPreferences']
            as Map<String, dynamic>)['reminder_lead_minutes'] =
        'tomorrow';

    expect(
      () => service.previewRestore(jsonEncode(data)),
      throwsFormatException,
    );
    expect((await repository.watchActiveSemester().first).id, 'term');
  });

  test('rolls back all data when a restore write fails', () async {
    final semester = Semester(
      id: 'term',
      name: '秋季学期',
      firstWeekStart: DateTime(2026, 9, 7),
      totalWeeks: 18,
    );
    await repository.saveSemester(semester, makeActive: true);
    await repository.saveCourse(
      Course(
        id: 'math',
        semesterId: 'term',
        source: CourseSource.manual,
        name: '高等数学',
        teacher: '',
        colorValue: 0xff123456,
        sessions: const [
          CourseSession(
            weekday: 1,
            startSection: 1,
            endSection: 1,
            startWeek: 1,
            endWeek: 18,
            pattern: WeekPattern.everyWeek,
            room: '',
          ),
        ],
      ),
    );
    final valid = service.previewRestore(await service.exportJson()).backup;
    final invalid = ValidatedTimetableBackup(
      semesters: valid.semesters,
      activeSemesterId: valid.activeSemesterId,
      courses: [valid.courses.single, valid.courses.single],
      schoolSchedule: valid.schoolSchedule,
      reminderPreferences: valid.reminderPreferences,
      warnings: const [],
    );

    await expectLater(service.restore(invalid), throwsA(isA<Exception>()));
    expect((await repository.watchCourses().first).single.id, 'math');
    expect((await repository.watchActiveSemester().first).id, 'term');
  });
}
