import 'package:drift/native.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/backup/timetable_backup_service.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/data/excel_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/data/import_time_plan.dart';
import 'package:qinghe_timetable/features/timetable/data/smart_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/data/timetable_import.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';
import 'dart:typed_data';
import 'dart:convert';

final term = Semester(
  id: 'term',
  name: '秋季',
  firstWeekStart: DateTime(2026, 9, 7),
  totalWeeks: 18,
);
Course course(
  String id, {
  int? start,
  int? end,
  CourseTimeSource? source,
  bool imported = false,
}) => Course(
  id: id,
  semesterId: term.id,
  source: imported ? CourseSource.cdcasKingo : CourseSource.manual,
  externalId: imported ? id : null,
  name: id,
  teacher: '',
  colorValue: 0,
  sessions: [
    CourseSession(
      weekday: id == 'Thursday' ? 4 : 5,
      startSection: 5,
      endSection: 6,
      startWeek: 1,
      endWeek: 18,
      pattern: WeekPattern.everyWeek,
      room: '',
      startMinute: start,
      endMinute: end,
      timeSource: source,
    ),
  ],
);

void main() {
  late AppDatabase db;
  late CourseRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = CourseRepository(db);
  });
  tearDown(() => db.close());
  for (final courseSuppliesStart in [true, false]) {
    test(
      'partial course and workbook section fully override old range $courseSuppliesStart',
      () async {
        await repo.saveCourse(course('Thursday', start: 820, end: 915));
        final preview = ImportPreview(
          semester: term,
          courses: [
            course(
              'math',
              start: courseSuppliesStart ? 840 : null,
              end: courseSuppliesStart ? null : 935,
              source: CourseTimeSource.imported,
              imported: true,
            ),
          ],
          importedTimes: [
            SectionRangeTime(
              semesterId: term.id,
              startSection: courseSuppliesStart ? 6 : 5,
              endSection: courseSuppliesStart ? 6 : 5,
              startMinute: courseSuppliesStart ? 890 : 840,
              endMinute: courseSuppliesStart ? 935 : 885,
            ),
          ],
        );
        final plan = ImportTimePlan(preview, await repo.readSchoolSchedule());
        expect(plan.conflicts, isEmpty);
        expect(plan.missingCount, 0);
        await repo.importTimetable(preview);
        expect(
          (await repo.watchCoursesForSemester(term.id).first)
              .map((c) => c.sessions.single.timeLabel)
              .toSet(),
          {'14:00–15:35'},
        );
      },
    );
  }
  test(
    'workbook single-section times override an older paired range',
    () async {
      await repo.saveCourse(course('Thursday', start: 820, end: 915));
      final preview = ImportPreview(
        semester: term,
        courses: [course('math', imported: true)],
        importedTimes: [
          SectionRangeTime(
            semesterId: term.id,
            startSection: 5,
            endSection: 5,
            startMinute: 840,
            endMinute: 885,
          ),
          SectionRangeTime(
            semesterId: term.id,
            startSection: 6,
            endSection: 6,
            startMinute: 890,
            endMinute: 935,
          ),
        ],
      );
      final plan = ImportTimePlan(preview, await repo.readSchoolSchedule());
      expect(plan.conflicts, isEmpty);
      expect(plan.missingCount, 0);
      expect(
        plan.schedule
            .resolve(
              preview.courses.single.sessions.single,
              semesterId: term.id,
            )
            .timeLabel,
        '14:00–15:35',
      );
      await repo.importTimetable(preview);
      expect(
        (await repo.watchCoursesForSemester(term.id).first)
            .map((c) => c.sessions.single.timeLabel)
            .toSet(),
        {'14:00–15:35'},
      );
    },
  );

  test(
    'editing one session controls same-range siblings in a multi-session course',
    () async {
      final edited = course('Thursday', start: 840, end: 935).sessions.first;
      final old = course('Friday', start: 505, end: 600).sessions.first;
      await repo.saveCourse(
        Course(
          id: 'multi',
          semesterId: term.id,
          source: CourseSource.manual,
          name: '数学',
          teacher: '',
          colorValue: 0,
          sessions: [edited, old],
        ),
        timeToSynchronize: edited,
      );
      expect(
        (await repo.watchCourses().first).single.sessions
            .map((s) => s.timeLabel)
            .toSet(),
        {'14:00–15:35'},
      );
    },
  );

  test('invalid inherited time rolls back the entire manual edit', () async {
    await repo.saveCourse(course('Thursday'));
    final single = Course(
      id: 'single',
      semesterId: term.id,
      source: CourseSource.manual,
      name: '单节',
      teacher: '',
      colorValue: 0,
      sessions: const [
        CourseSession(
          weekday: 1,
          startSection: 5,
          endSection: 5,
          startWeek: 1,
          endWeek: 18,
          pattern: WeekPattern.everyWeek,
          room: '',
          startMinute: 960,
          endMinute: 1005,
        ),
      ],
    );
    await expectLater(repo.saveCourse(single), throwsFormatException);
    expect(
      (await repo.watchCourses().first).single.sessions.single.timeLabel,
      '13:40–15:15',
    );
    expect((await repo.watchSchoolSchedule().first).rangeTimes, isEmpty);
  });
  test(
    'partial course time uses this import bell time before existing defaults',
    () async {
      final preview = ImportPreview(
        semester: term,
        courses: [
          course(
            'math',
            start: 840,
            source: CourseTimeSource.imported,
            imported: true,
          ),
        ],
        importedTimes: [
          SectionRangeTime(
            semesterId: term.id,
            startSection: 6,
            endSection: 6,
            startMinute: 890,
            endMinute: 935,
          ),
        ],
      );
      final plan = ImportTimePlan(preview, SchoolSchedule.defaults());
      expect(plan.missingCount, 0);
      expect(
        plan.schedule
            .resolve(
              preview.courses.single.sessions.single,
              semesterId: term.id,
            )
            .timeLabel,
        '14:00–15:35',
      );
      await repo.importTimetable(preview);
      expect(
        (await repo.watchCourses().first).single.sessions.single.timeLabel,
        '14:00–15:35',
      );
    },
  );
  test(
    'import requires a choice for conflicting legacy manual times',
    () async {
      await repo.saveCourse(
        course('Thursday', start: 505, end: 600),
        synchronizeTimes: false,
      );
      await repo.saveCourse(
        course('Friday', start: 840, end: 935),
        synchronizeTimes: false,
      );
      await repo.seedIfEmpty();
      final preview = ImportPreview(
        semester: term,
        courses: [course('math', imported: true)],
      );
      final plan = ImportTimePlan(
        preview,
        await repo.readSchoolSchedule(),
        existingTimes: await repo.readUnsharedTimes(term.id),
      );
      expect(plan.conflicts.values.single, hasLength(2));
      await expectLater(repo.importTimetable(preview), throwsFormatException);
      final selected = plan.conflicts.values.single.last;
      await repo.importTimetable(
        ImportPreview(
          semester: term,
          courses: preview.courses,
          timeChoices: {selected.key: selected},
        ),
      );
      expect(
        (await repo.watchCourses().first)
            .map((c) => c.sessions.single.timeLabel)
            .toSet(),
        {'14:00–15:35'},
      );
    },
  );
  test(
    'restoring a pre-upgrade backup migrates unique manual time again',
    () async {
      await repo.saveSemester(term, makeActive: true);
      await repo.saveCourse(
        course('Thursday', start: 505, end: 600),
        synchronizeTimes: false,
      );
      await repo.saveCourse(course('Friday'), synchronizeTimes: false);
      final service = TimetableBackupService(db);
      final old =
          jsonDecode(await service.exportJson()) as Map<String, dynamic>;
      (old['schoolSchedule'] as Map).remove('ranges');
      await repo.seedIfEmpty();
      await service.restore(service.previewRestore(jsonEncode(old)).backup);
      expect(
        (await repo.watchCourses().first)
            .map((c) => c.sessions.single.timeLabel)
            .toSet(),
        {'08:25–10:00'},
      );
    },
  );
  test('single-line and partial headings keep their observed time', () {
    ImportPreview parse(String heading) =>
        const SmartTimetableImporter().parseGrid([
          const GridCell('周一', 0, 1),
          const GridCell('周二', 0, 2),
          GridCell(heading, 1, 0),
          const GridCell('数学\n1-18周\nA302', 1, 1),
        ], term);
    expect(
      parse('第5-6节 14:00–15:35').courses.single.sessions.single.timeLabel,
      '14:00–15:35',
    );
    final directionless = parse('第5-6节 14:00');
    expect(directionless.courses.single.sessions.single.startMinute, isNull);
    expect(
      ImportTimePlan(directionless, SchoolSchedule.defaults()).missingCount,
      1,
    );
    final partial = parse('第5-6节\n14:00–');
    expect(partial.courses.single.sessions.single.startMinute, 840);
    expect(ImportTimePlan(partial, SchoolSchedule.defaults()).missingCount, 1);
    expect(
      ImportTimePlan(partial, SchoolSchedule.defaults()).schedule
          .resolve(partial.courses.single.sessions.single, semesterId: term.id)
          .timeLabel,
      '14:00–15:15',
    );
  });

  test('legacy unique manual time is inherited on upgrade', () async {
    await repo.saveCourse(
      course('Thursday', start: 505, end: 600),
      synchronizeTimes: false,
    );
    await repo.saveCourse(course('Friday'), synchronizeTimes: false);
    await repo.seedIfEmpty();
    final values = (await repo.watchCourses().first)
        .map((c) => c.sessions.single.timeLabel)
        .toSet();
    expect(values, {'08:25–10:00'});
    await repo.seedIfEmpty();
    expect((await repo.watchSchoolSchedule().first).rangeTimes, hasLength(1));
  });
  test(
    'conflicting legacy manual edits are retained until explicitly chosen',
    () async {
      await repo.saveCourse(
        course('Thursday', start: 505, end: 600),
        synchronizeTimes: false,
      );
      await repo.saveCourse(
        course('Friday', start: 840, end: 935),
        synchronizeTimes: false,
      );
      await repo.seedIfEmpty();
      expect((await repo.watchSchoolSchedule().first).rangeTimes, isEmpty);
      expect(
        (await repo.watchCourses().first)
            .map((c) => c.sessions.single.timeLabel)
            .toSet(),
        {'08:25–10:00', '14:00–15:35'},
      );
      await repo.saveCourse(course('Friday', start: 840, end: 935));
      expect(
        (await repo.watchCourses().first)
            .map((c) => c.sessions.single.timeLabel)
            .toSet(),
        {'14:00–15:35'},
      );
    },
  );
  test(
    'complete Excel time takes priority over saved manual schedule',
    () async {
      await repo.saveCourse(course('Thursday', start: 505, end: 600));
      final incoming = course(
        'math',
        start: 840,
        end: 935,
        source: CourseTimeSource.imported,
        imported: true,
      );
      final preview = ImportPreview(semester: term, courses: [incoming]);
      final plan = ImportTimePlan(
        preview,
        await repo.watchSchoolSchedule().first,
      );
      expect(plan.conflicts, isEmpty);
      expect(plan.missingCount, 0);
      await repo.importTimetable(preview);

      expect(
        (await repo.watchCourses().first)
            .map((c) => c.sessions.single.timeLabel)
            .toSet(),
        {'14:00–15:35'},
      );
    },
  );
  test(
    'imported time and shared rule survive JSON backup and restore',
    () async {
      await repo.importTimetable(
        ImportPreview(
          semester: term,
          courses: [
            course(
              'math',
              start: 840,
              end: 935,
              source: CourseTimeSource.imported,
              imported: true,
            ),
          ],
        ),
      );
      final service = TimetableBackupService(db);
      final backup = service.previewRestore(await service.exportJson());
      expect(
        backup.backup.courses.single.sessions.single.timeSource,
        CourseTimeSource.imported,
      );
      expect(backup.backup.courses.single.sessions.single.startMinute, 840);
      await service.restore(backup.backup);
      await repo.saveCourse(course('new'));
      expect(
        (await repo.watchCourses().first)
            .map((c) => c.sessions.single.timeLabel)
            .toSet(),
        {'14:00–15:35'},
      );
    },
  );
  test('partial time is preserved and missing boundary is disclosed', () async {
    final preview = const ExcelTimetableImporter().parseRows([
      ['课程名称', '星期', '节次', '周次', '开始时间', '结束时间'],
      ['数学', '周五', '5-6', '1-18', '14:00', ''],
    ], fallbackSemester: term);
    expect(preview.courses.single.sessions.single.startMinute, 840);
    expect(ImportTimePlan(preview, SchoolSchedule.defaults()).missingCount, 1);
    await repo.importTimetable(preview);
    final saved = (await repo.watchCourses().first).single.sessions.single;
    expect(saved.startMinute, 840);
    expect(saved.endMinute, 915);
  });
  test('workbook reads its separate bell time sheet', () async {
    final book = Excel.createExcel();
    final sheet = book['课程'];
    sheet.appendRow(['课程名称', '星期', '节次', '周次'].map(TextCellValue.new).toList());
    sheet.appendRow(
      ['数学', '周五', '5-6', '1-18'].map(TextCellValue.new).toList(),
    );
    book['作息时间'].appendRow(
      ['第5-6节', '14:00', '15:35'].map(TextCellValue.new).toList(),
    );
    final preview = const SmartTimetableImporter().parseExcel(
      Uint8List.fromList(book.encode()!),
      term,
    );
    expect(preview.importedTimes, isNotEmpty);
    await repo.importTimetable(preview);
    expect(
      (await repo.watchCourses().first).single.sessions.single.timeLabel,
      '14:00–15:35',
    );
  });
  test('inline course time is kept out of the name and room', () {
    final preview = const SmartTimetableImporter().parseGrid([
      const GridCell('周一', 0, 1),
      const GridCell('周二', 0, 2),
      const GridCell('第5-6节', 1, 0),
      const GridCell('数学\n14:00–15:35\n1-18周\nA302', 1, 1),
    ], term);
    expect(preview.courses.single.name, '数学');
    expect(preview.courses.single.sessions.single.room, 'A302');
    expect(preview.courses.single.sessions.single.timeLabel, '14:00–15:35');
  });
}
