import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_models.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/cdcas_kingo_importer.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  late AppDatabase database;
  late CourseRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = CourseRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  final semester = Semester(
    id: '2026-autumn',
    name: '2026 秋季学期',
    firstWeekStart: DateTime(2026, 9, 7),
    totalWeeks: 18,
  );

  Course course({
    String id = 'math',
    String name = '高等数学',
    String room = 'A302',
    CourseSource source = CourseSource.manual,
    String? externalId,
    String? semesterId,
  }) {
    return Course(
      id: id,
      semesterId: semesterId ?? semester.id,
      source: source,
      externalId: externalId,
      name: name,
      teacher: '陈老师',
      colorValue: 0xFF2E7D66,
      sessions: [
        CourseSession(
          weekday: DateTime.monday,
          startSection: 1,
          endSection: 2,
          startWeek: 1,
          endWeek: 18,
          pattern: WeekPattern.everyWeek,
          room: room,
        ),
      ],
    );
  }

  test('saves and watches a course with its session', () async {
    await repository.saveSemester(semester, makeActive: true);
    await repository.saveCourse(course());

    final courses = await repository.watchCourses().first;

    expect(courses, hasLength(1));
    expect(courses.single.name, '高等数学');
    expect(courses.single.sessions.single.room, 'A302');
  });

  test('preserves source metadata and active semester', () async {
    await repository.saveSemester(semester, makeActive: true);
    await repository.saveCourse(
      course(source: CourseSource.cdcasKingo, externalId: 'K1001'),
    );

    final activeSemester = await repository.watchActiveSemester().first;
    final saved = (await repository.watchCourses().first).single;

    expect(activeSemester.id, semester.id);
    expect(saved.source, CourseSource.cdcasKingo);
    expect(saved.externalId, 'K1001');
    expect(saved.semesterId, semester.id);
  });

  test('watches only courses in the selected semester', () async {
    const springId = '2027-spring';
    await repository.saveCourse(course(id: 'autumn'));
    await repository.saveCourse(
      course(id: 'spring', semesterId: springId, name: '线性代数'),
    );

    final autumn = await repository.watchCoursesForSemester(semester.id).first;
    final spring = await repository.watchCoursesForSemester(springId).first;

    expect(autumn.map((item) => item.id), ['autumn']);
    expect(spring.map((item) => item.id), ['spring']);
  });

  test('persists reminder enabled state', () async {
    expect(await repository.watchRemindersEnabled().first, isFalse);

    await repository.setRemindersEnabled(true);
    expect(await repository.watchRemindersEnabled().first, isTrue);

    await repository.setRemindersEnabled(false);
    expect(await repository.watchRemindersEnabled().first, isFalse);
  });

  test('persists reminder lead time and sound', () async {
    final initial = await repository.watchReminderPreferences().first;
    expect(initial.leadMinutes, 30);
    expect(initial.sound, ReminderSound.systemDefault);

    await repository.setReminderLeadMinutes(10);
    await repository.setReminderSound(ReminderSound.chime);

    final saved = await repository.watchReminderPreferences().first;
    expect(saved.leadMinutes, 10);
    expect(saved.sound, ReminderSound.chime);
  });

  test('persists custom start and end times for a course session', () async {
    final custom = course();
    await repository.saveCourse(
      Course(
        id: custom.id,
        semesterId: custom.semesterId,
        source: custom.source,
        name: custom.name,
        teacher: custom.teacher,
        colorValue: custom.colorValue,
        sessions: [
          CourseSession(
            weekday: DateTime.monday,
            startSection: 1,
            endSection: 2,
            startWeek: 1,
            endWeek: 18,
            pattern: WeekPattern.everyWeek,
            room: 'A302',
            startMinute: 9 * 60 + 40,
            endMinute: 11 * 60 + 15,
          ),
        ],
      ),
    );

    final saved =
        (await repository.watchCourses().first).single.sessions.single;
    expect(saved.startMinute, 580);
    expect(saved.endMinute, 675);
  });

  test('updates a course and replaces its sessions', () async {
    await repository.saveCourse(course());
    await repository.saveCourse(course(name: '高等数学 A', room: 'B201'));

    final courses = await repository.watchCourses().first;

    expect(courses, hasLength(1));
    expect(courses.single.name, '高等数学 A');
    expect(courses.single.sessions, hasLength(1));
    expect(courses.single.sessions.single.room, 'B201');
  });

  test('deletes a course and its sessions', () async {
    await repository.saveCourse(course());

    await repository.deleteCourse('math');

    expect(await repository.watchCourses().first, isEmpty);
  });

  test('seeds sample courses only once', () async {
    await repository.seedIfEmpty();
    final seeded = await repository.watchCourses().first;
    expect(seeded, hasLength(3));

    for (final item in seeded) {
      await repository.deleteCourse(item.id);
    }
    await repository.seedIfEmpty();

    expect(await repository.watchCourses().first, isEmpty);
  });

  group('importTimetable', () {
    ImportPreview preview({
      Semester? targetSemester,
      List<Course>? courses,
      List<String> warnings = const [],
    }) {
      final selectedSemester = targetSemester ?? semester;
      return ImportPreview(
        semester: selectedSemester,
        courses:
            courses ??
            [
              course(
                id: 'school-math',
                semesterId: selectedSemester.id,
                source: CourseSource.cdcasKingo,
                externalId: 'K1001',
              ),
            ],
        warnings: warnings,
      );
    }

    test(
      'first import inserts school courses and activates semester',
      () async {
        final summary = await repository.importTimetable(
          preview(warnings: const ['一条可恢复提示']),
        );

        expect(summary.inserted, 1);
        expect(summary.updated, 0);
        expect(summary.removed, 0);
        expect(summary.warnings, const ['一条可恢复提示']);
        expect((await repository.watchActiveSemester().first).id, semester.id);
        expect(await repository.watchCourses().first, hasLength(1));
      },
    );

    test('idempotent re-import reports no changes', () async {
      final import = preview();
      await repository.importTimetable(import);

      final summary = await repository.importTimetable(import);

      expect(summary.inserted, 0);
      expect(summary.updated, 0);
      expect(summary.removed, 0);
      expect(await repository.watchCourses().first, hasLength(1));
    });

    test('keeps the same external course in different semesters', () async {
      final spring = Semester(
        id: '2027-spring',
        name: '2027 春季学期',
        firstWeekStart: DateTime(2027, 2, 22),
        totalWeeks: 18,
      );
      await repository.importTimetable(preview());
      await repository.importTimetable(
        preview(
          targetSemester: spring,
          courses: [
            course(
              id: 'school-math-spring',
              semesterId: spring.id,
              source: CourseSource.cdcasKingo,
              externalId: 'K1001',
            ),
          ],
        ),
      );

      final all = await repository.watchCourses().first;
      expect(all, hasLength(2));
      expect(all.map((item) => item.semesterId).toSet(), {
        semester.id,
        spring.id,
      });
    });

    test('updates changed course and removes stale imported course', () async {
      final stale = course(
        id: 'school-english',
        name: '大学英语',
        source: CourseSource.cdcasKingo,
        externalId: 'K1002',
      );
      await repository.importTimetable(
        preview(courses: [preview().courses.single, stale]),
      );

      final changed = course(
        id: 'different-local-id',
        room: 'B201',
        source: CourseSource.cdcasKingo,
        externalId: 'K1001',
      );
      final summary = await repository.importTimetable(
        preview(courses: [changed]),
      );

      expect(summary.inserted, 0);
      expect(summary.updated, 1);
      expect(summary.removed, 1);
      final saved = (await repository.watchCourses().first).single;
      expect(saved.id, 'cdcas-${semester.id}-K1001');
      expect(saved.sessions.single.room, 'B201');
    });

    test(
      'previews destructive changes without mutating stored courses',
      () async {
        final stale = course(
          id: 'school-english',
          name: '大学英语',
          source: CourseSource.cdcasKingo,
          externalId: 'K1002',
        );
        await repository.importTimetable(
          preview(courses: [preview().courses.single, stale]),
        );
        final changed = course(
          id: 'ignored',
          room: 'B201',
          source: CourseSource.cdcasKingo,
          externalId: 'K1001',
        );

        final summary = await repository.previewTimetableImport(
          preview(courses: [changed]),
        );

        expect(summary.inserted, 0);
        expect(summary.updated, 1);
        expect(summary.removed, 1);
        expect(await repository.watchCourses().first, hasLength(2));
      },
    );

    test('preserves manual courses in the imported semester', () async {
      await repository.saveCourse(course(id: 'manual-course'));

      await repository.importTimetable(preview());

      final courses = await repository.watchCourses().first;
      expect(courses.map((item) => item.id), contains('manual-course'));
      expect(
        courses.where((item) => item.source == CourseSource.cdcasKingo),
        hasLength(1),
      );
    });

    test('rejects a zero-course preview without changing data', () async {
      await repository.saveCourse(course(id: 'manual-course'));

      expect(
        () => repository.importTimetable(preview(courses: const [])),
        throwsA(isA<ArgumentError>()),
      );

      expect((await repository.watchCourses().first).map((item) => item.id), [
        'manual-course',
      ]);
    });

    test('rolls back all changes when a course insert fails', () async {
      await repository.importTimetable(preview());
      final otherSemester = Semester(
        id: '2027-spring',
        name: '2027 春季学期',
        firstWeekStart: DateTime(2027, 2, 22),
        totalWeeks: 18,
      );
      final invalidCourse = course(
        id: 'invalid',
        name: '超长课程名' * 20,
        semesterId: otherSemester.id,
        source: CourseSource.cdcasKingo,
        externalId: 'BROKEN',
      );

      await expectLater(
        repository.importTimetable(
          preview(targetSemester: otherSemester, courses: [invalidCourse]),
        ),
        throwsA(anything),
      );

      expect((await repository.watchActiveSemester().first).id, semester.id);
      final courses = await repository.watchCourses().first;
      expect(courses.map((item) => item.id), ['cdcas-${semester.id}-K1001']);
    });
  });
}
