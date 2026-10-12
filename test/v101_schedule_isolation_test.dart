import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/data/import_time_plan.dart';
import 'package:qinghe_timetable/features/timetable/data/timetable_import.dart';

void main() {
  test(
    'templates isolate semesters, unknown stays unknown, JSON roundtrip',
    () {
      final s = SchoolSchedule.defaults().withSemesterSections(
        'a',
        [const SectionTime(1, 480, 525), const SectionTime(2, 535, 580)],
        lessonMinutes: 45,
        breakMinutes: 10,
      );
      final round = SchoolSchedule.decode(s.encode());
      expect(round.sectionFor('a', 1)?.startMinute, 480);
      expect(round.sectionFor('b', 1)?.startMinute, 505);
      expect(round.sectionFor('a', 3), isNull);
      expect(round.lessonMinutesFor('a'), 45);
      expect(round.breakMinutesFor('a'), 10);
    },
  );
  test(
    'explicit incoming single-section times update only matching semester',
    () {
      final s = SchoolSchedule.defaults()
          .withSemesterSections('a', [const SectionTime(1, 480, 525)])
          .withRangeTime(
            const SectionRangeTime(
              semesterId: 'a',
              startSection: 1,
              endSection: 1,
              startMinute: 500,
              endMinute: 540,
            ),
          );
      expect(s.sectionFor('a', 1)?.startMinute, 500);
      expect(s.sectionFor('b', 1)?.startMinute, 505);
      final c = CourseSession(
        weekday: 1,
        startSection: 1,
        endSection: 1,
        startWeek: 1,
        endWeek: 2,
        pattern: WeekPattern.everyWeek,
        room: '',
      );
      expect(s.resolve(c, semesterId: 'a').startMinute, 500);
    },
  );
  test('overlap and duplicate confirmed section templates rejected', () {
    expect(
      () => SchoolSchedule.defaults().withSemesterSections('a', [
        const SectionTime(1, 480, 550),
        const SectionTime(2, 540, 580),
      ]),
      throwsFormatException,
    );
  });
  test('manual rule removal clears scoped rules, never another semester', () {
    final original = SchoolSchedule.defaults()
        .withSemesterSections(
          'a',
          [const SectionTime(1, 480, 525)],
          lessonMinutes: 45,
          breakMinutes: 5,
        )
        .withSemesterSections('b', [
          const SectionTime(1, 500, 550),
        ], lessonMinutes: 50);
    final updated = original.withSemesterSections('a', [
      const SectionTime(1, 490, 535),
    ], replaceRules: true);
    expect(updated.lessonMinutesFor('a'), isNull);
    expect(updated.breakMinutesFor('a'), isNull);
    expect(updated.lessonMinutesFor('b'), 50);
  });
  test(
    'new paired Excel evidence invalidates stale slots without inventing individual times',
    () {
      final original = SchoolSchedule.defaults().withSemesterSections('a', [
        const SectionTime(1, 480, 525),
        const SectionTime(2, 530, 575),
      ]);
      final next = original.withRangeTime(
        const SectionRangeTime(
          semesterId: 'a',
          startSection: 1,
          endSection: 2,
          startMinute: 490,
          endMinute: 585,
        ),
      );
      expect(next.sectionFor('a', 1), isNull);
      const session = CourseSession(
        weekday: 1,
        startSection: 1,
        endSection: 2,
        startWeek: 1,
        endWeek: 20,
        pattern: WeekPattern.everyWeek,
        room: '',
      );
      expect(next.resolve(session, semesterId: 'a').timeLabel, '08:10–09:45');
    },
  );
  test('whole incoming Excel shift replaces old slots atomically', () {
    final old = SchoolSchedule.defaults().withSemesterSections('a', [
      const SectionTime(1, 480, 525),
      const SectionTime(2, 535, 580),
    ]);
    final preview = ImportPreview(
      semester: Semester(
        id: 'a',
        name: 'A',
        firstWeekStart: DateTime(2026, 9, 7),
        totalWeeks: 20,
      ),
      courses: [],
      importedTimes: [
        const SectionRangeTime(
          semesterId: 'a',
          startSection: 1,
          endSection: 1,
          startMinute: 540,
          endMinute: 585,
        ),
        const SectionRangeTime(
          semesterId: 'a',
          startSection: 2,
          endSection: 2,
          startMinute: 595,
          endMinute: 640,
        ),
      ],
    );
    final plan = ImportTimePlan(preview, old);
    expect(plan.schedule.sectionFor('a', 1)?.startMinute, 540);
    expect(plan.schedule.sectionFor('a', 2)?.startMinute, 595);
  });
}
